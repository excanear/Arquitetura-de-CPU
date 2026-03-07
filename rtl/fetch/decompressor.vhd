-- =============================================================================
-- decompressor.vhd
-- RV32C Instruction Decompressor  (RISC-V Compressed Instruction Set)
--
-- Converts a 16-bit compressed instruction to its canonical 32-bit equivalent.
-- Purely combinational, zero-latency.
--
-- Quadrant encoding:
--   [1:0] = 00  : CL / CS / CI / CIW  (Q0)
--   [1:0] = 01  : CI / CB / CJ / CA   (Q1)
--   [1:0] = 10  : CI / CR / CSS        (Q2)
--   [1:0] = 11  : 32-bit instruction (not compressed; output as-is)
--
-- Floating-point variants (C.FLD, C.FLW, C.FSD, C.FSW, etc.) are not
-- implemented here (no FPU); they expand to the 32-bit ILLEGAL instruction
-- (all-zero opcode, i.e. 0x00000000) so a subsequent illegal-instruction
-- trap is raised.
--
-- Register notation:
--   rdp / rs1p / rs2p  : 3-bit "prime" register field → maps to x8-x15
--   rd  / rs1  / rs2   : full 5-bit register field (from bits [11:7] or [6:2])
-- =============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity decompressor is
    port (
        -- The 16-bit instruction to decompress (lower 16 bits of the fetched word)
        instr16_i : in  std_logic_vector(15 downto 0);
        -- 32-bit equivalent output
        instr32_o : out std_logic_vector(31 downto 0);
        -- '1' when instr16_i is a valid compressed instruction (bits[1:0] /= "11")
        is_compressed_o : out std_logic
    );
end entity decompressor;

architecture rtl of decompressor is

    -- =========================================================================
    -- Helper functions to build 32-bit instruction fields
    -- =========================================================================

    -- Build I-type instruction
    --   imm12 | rs1 | funct3 | rd | opcode
    function mk_i(imm12  : std_logic_vector(11 downto 0);
                  rs1    : std_logic_vector(4 downto 0);
                  funct3 : std_logic_vector(2 downto 0);
                  rd     : std_logic_vector(4 downto 0);
                  opcode : std_logic_vector(6 downto 0))
        return std_logic_vector is
    begin
        return imm12 & rs1 & funct3 & rd & opcode;
    end function mk_i;

    -- Build S-type instruction
    --   imm[11:5] | rs2 | rs1 | funct3 | imm[4:0] | opcode
    function mk_s(imm12  : std_logic_vector(11 downto 0);
                  rs2    : std_logic_vector(4 downto 0);
                  rs1    : std_logic_vector(4 downto 0);
                  funct3 : std_logic_vector(2 downto 0);
                  opcode : std_logic_vector(6 downto 0))
        return std_logic_vector is
    begin
        return imm12(11 downto 5) & rs2 & rs1 & funct3 & imm12(4 downto 0) & opcode;
    end function mk_s;

    -- Build R-type instruction
    --   funct7 | rs2 | rs1 | funct3 | rd | opcode
    function mk_r(funct7 : std_logic_vector(6 downto 0);
                  rs2    : std_logic_vector(4 downto 0);
                  rs1    : std_logic_vector(4 downto 0);
                  funct3 : std_logic_vector(2 downto 0);
                  rd     : std_logic_vector(4 downto 0);
                  opcode : std_logic_vector(6 downto 0))
        return std_logic_vector is
    begin
        return funct7 & rs2 & rs1 & funct3 & rd & opcode;
    end function mk_r;

    -- Build B-type instruction from a 9-bit signed byte-offset (bimm9, bit0=0)
    -- bimm9(8) = sign, bimm9(7:1) = bits of offset, bimm9(0) = 0 ignored
    function mk_b(bimm9  : std_logic_vector(8 downto 0);
                  rs2    : std_logic_vector(4 downto 0);
                  rs1    : std_logic_vector(4 downto 0);
                  funct3 : std_logic_vector(2 downto 0))
        return std_logic_vector is
        -- Full branch imm: imm[12:1]
        -- imm[12:9] = sign extension of bimm9[8]
        -- imm[8:1]  = bimm9[8:1]
        variable sign   : std_logic;
        variable imm12  : std_logic_vector(11 downto 0);
    begin
        sign        := bimm9(8);
        imm12(11)   := sign;          -- imm[12]
        imm12(10)   := sign;          -- imm[11] sign-extend
        imm12(9)    := sign;          -- imm[10] sign-extend
        imm12(8)    := sign;          -- imm[9]  sign-extend
        imm12(7)    := sign;          -- imm[8]  = bimm9[8] (sign bit)
        imm12(6)    := bimm9(7);      -- imm[7]
        imm12(5)    := bimm9(6);      -- imm[6]
        imm12(4)    := bimm9(5);      -- imm[5]
        imm12(3)    := bimm9(4);      -- imm[4]
        imm12(2)    := bimm9(3);      -- imm[3]
        imm12(1)    := bimm9(2);      -- imm[2]
        imm12(0)    := bimm9(1);      -- imm[1]
        -- B-type: imm[12]|imm[10:5]|rs2|rs1|funct3|imm[4:1]|imm[11]|opcode
        return imm12(11) & imm12(9 downto 4) & rs2 & rs1 & funct3 &
               imm12(3 downto 0) & imm12(10) & "1100011";
    end function mk_b;

    -- Build JAL from a 12-bit signed byte-offset (jimm12, bit0=0)
    -- jimm12(11) = sign, jimm12(10:1) = bits, jimm12(0) = 0 ignored
    function mk_jal(jimm12 : std_logic_vector(11 downto 0);
                    rd     : std_logic_vector(4 downto 0))
        return std_logic_vector is
        variable sign : std_logic;
        -- J-type imm [20:1]: sign-extend jimm12 to 20 bits
        variable imm20 : std_logic_vector(19 downto 0);
    begin
        sign := jimm12(11);
        -- Sign-extend jimm12 to 20 bits
        imm20(19 downto 12) := (others => sign);  -- imm[20:12]
        imm20(11 downto 0)  := jimm12;
        -- J-type: imm[20]|imm[10:1]|imm[11]|imm[19:12]|rd|opcode
        return imm20(19) & imm20(9 downto 0) & imm20(10) &
               imm20(18 downto 11) & rd & "1101111";
    end function mk_jal;

    -- Build U-type instruction
    function mk_u(imm20  : std_logic_vector(19 downto 0);
                  rd     : std_logic_vector(4 downto 0);
                  opcode : std_logic_vector(6 downto 0))
        return std_logic_vector is
    begin
        return imm20 & rd & opcode;
    end function mk_u;

    -- Illegal instruction marker (all-zero opcode = reserved)
    constant ILLEGAL32 : std_logic_vector(31 downto 0) := (others => '0');
    constant NOP32     : std_logic_vector(31 downto 0) := x"00000013"; -- addi x0,x0,0

    -- "Prime" register: 3-bit field → x8..x15
    function prime(r3 : std_logic_vector(2 downto 0)) return std_logic_vector is
    begin
        return "01" & r3;  -- maps r3=[0..7] to [8..15]
    end function prime;

    -- Sign-extend N-bit value to 12 bits
    function sext12(v : std_logic_vector) return std_logic_vector is
        variable r : std_logic_vector(11 downto 0);
    begin
        r := (others => v(v'high));
        r(v'length-1 downto 0) := v;
        return r;
    end function sext12;

    -- Zero-extend to 12 bits
    function zext12(v : std_logic_vector) return std_logic_vector is
        variable r : std_logic_vector(11 downto 0);
    begin
        r := (others => '0');
        r(v'length-1 downto 0) := v;
        return r;
    end function zext12;

begin

    is_compressed_o <= '0' when instr16_i(1 downto 0) = "11" else '1';

    -- =========================================================================
    -- Decompression process (the bulk of the logic)
    -- =========================================================================
    decomp_proc : process(instr16_i)
        -- Aliases for clarity
        variable op   : std_logic_vector(1 downto 0);  -- quadrant
        variable f3   : std_logic_vector(2 downto 0);  -- funct3 [15:13]
        variable rd   : std_logic_vector(4 downto 0);  -- [11:7]
        variable rs2  : std_logic_vector(4 downto 0);  -- [6:2]
        variable rdp  : std_logic_vector(4 downto 0);  -- bits[4:2]+8
        variable rs1p : std_logic_vector(4 downto 0);  -- bits[9:7]+8
        variable rs2p : std_logic_vector(4 downto 0);  -- bits[4:2]+8 (same as rdp in some)

        -- Various immediates
        variable imm6  : std_logic_vector(5 downto 0);  -- CI 6-bit signed
        variable uimm6 : std_logic_vector(5 downto 0);  -- unsigned 6-bit
        variable nzuimm10 : std_logic_vector(9 downto 0); -- CIW unsigned
        variable cl_off   : std_logic_vector(6 downto 0); -- CL/CS word offset (byte)
        variable j_imm12  : std_logic_vector(11 downto 0);
        variable b_imm9   : std_logic_vector(8 downto 0);
        variable sp_off_w : std_logic_vector(7 downto 0); -- LWSP/SWSP
        variable addi16sp_imm : std_logic_vector(9 downto 0);
    begin
        op   := instr16_i(1 downto 0);
        f3   := instr16_i(15 downto 13);
        rd   := instr16_i(11 downto 7);
        rs2  := instr16_i(6 downto 2);
        rdp  := prime(instr16_i(4 downto 2));
        rs1p := prime(instr16_i(9 downto 7));
        rs2p := prime(instr16_i(4 downto 2));

        instr32_o <= NOP32; -- default

        case op is

            -- =================================================================
            -- Quadrant 0  (op = 00)
            -- =================================================================
            when "00" =>
                case f3 is

                    -- C.ADDI4SPN : addi rdp, sp, nzuimm
                    -- nzuimm = {instr[10:7], instr[12:11], instr[5], instr[6]} * 4
                    when "000" =>
                        -- nzuimm[9:2] = {instr[10:7], instr[12:11], instr[5], instr[6]}
                        -- nzuimm[1:0] = 00  (word offset, always aligned)
                        nzuimm10 := instr16_i(10 downto 7) &
                                    instr16_i(12 downto 11) &
                                    instr16_i(5) & instr16_i(6) & "00";
                        instr32_o <= mk_i(
                            zext12(nzuimm10),          -- 10-bit byte offset, zero-extend to 12
                            "00010",                   -- sp = x2
                            "000",                     -- ADDI funct3
                            rdp, "0010011");

                    -- C.LW : lw rdp, offset(rs1p)
                    -- offset = {instr[5], instr[12:10], instr[6]} * 4
                    when "010" =>
                        cl_off := instr16_i(5) & instr16_i(12 downto 10) & instr16_i(6) & "00";
                        instr32_o <= mk_i(
                            zext12(cl_off),
                            rs1p, "010", rdp, "0000011"); -- LW

                    -- C.SW : sw rs2p, offset(rs1p)
                    when "110" =>
                        cl_off := instr16_i(5) & instr16_i(12 downto 10) & instr16_i(6) & "00";
                        instr32_o <= mk_s(
                            zext12(cl_off),
                            rs2p, rs1p, "010", "0100011"); -- SW

                    when others =>
                        instr32_o <= ILLEGAL32;
                end case;

            -- =================================================================
            -- Quadrant 1  (op = 01)
            -- =================================================================
            when "01" =>
                case f3 is

                    -- C.NOP / C.ADDI : addi rd, rd, imm
                    when "000" =>
                        imm6 := instr16_i(12) & instr16_i(6 downto 2);
                        if rd = "00000" then
                            instr32_o <= NOP32;         -- NOP
                        else
                            instr32_o <= mk_i(sext12(imm6), rd, "000", rd, "0010011");
                        end if;

                    -- C.JAL (RV32 only) : jal x1, offset
                    -- offset = sign_extend({i12,i8,i10:9,i6,i7,i2,i11,i5:3}, 12)
                    when "001" =>
                        j_imm12 := instr16_i(12) & instr16_i(8) &
                                   instr16_i(10 downto 9) & instr16_i(6) &
                                   instr16_i(7) & instr16_i(2) &
                                   instr16_i(11) & instr16_i(5 downto 3);
                        instr32_o <= mk_jal(j_imm12, "00001"); -- x1 = ra

                    -- C.LI : addi rd, x0, imm
                    when "010" =>
                        imm6 := instr16_i(12) & instr16_i(6 downto 2);
                        instr32_o <= mk_i(sext12(imm6), "00000", "000", rd, "0010011");

                    -- C.ADDI16SP / C.LUI
                    when "011" =>
                        if rd = "00010" then
                            -- C.ADDI16SP : addi sp, sp, nzimm16
                            -- nzimm = sign_ext({i12, i4:3, i5, i2, i6} * 16)
                            addi16sp_imm := instr16_i(12) & instr16_i(4 downto 3) &
                                            instr16_i(5) & instr16_i(2) & instr16_i(6) &
                                            "0000"; -- * 16
                            instr32_o <= mk_i(sext12(addi16sp_imm),
                                             "00010", "000", "00010", "0010011");
                        else
                            -- C.LUI : lui rd, nzimm
                            -- nzimm[17:12] = {i12, i6:2} sign-extended to 20 bits
                            -- lui takes upper 20 bits → store sign_ext({i12,i6:2}) at bits [17:12]
                            imm6 := instr16_i(12) & instr16_i(6 downto 2);
                            instr32_o <= mk_u(sext12(imm6)(11 downto 0) &
                                             (7 downto 0 => '0'), rd, "0110111");
                            -- Note: LUI imm goes to rd[31:12]; the compressed imm represents
                            -- a 6-bit signed value that becomes imm[17:12], sign-extended to 20b.
                            -- Correct encoding: imm20 = sign_extend(i12:i6:i5:i4:i3:i2, 20)
                            -- placed at bits [31:12] of rd. So:
                            instr32_o <= mk_u(
                                (19 downto 6 => instr16_i(12)) & instr16_i(6 downto 2),
                                rd, "0110111");
                        end if;

                    -- C.SRLI / C.SRAI / C.ANDI / C.SUB / C.XOR / C.OR / C.AND
                    when "100" =>
                        case instr16_i(11 downto 10) is
                            when "00" => -- C.SRLI
                                uimm6 := '0' & instr16_i(6 downto 2); -- shamt, bit[12] must be 0 for RV32
                                instr32_o <= mk_i(
                                    "0000000" & uimm6(4 downto 0),
                                    rs1p, "101", rs1p, "0010011"); -- SRLI: funct7=0000000

                            when "01" => -- C.SRAI
                                uimm6 := '0' & instr16_i(6 downto 2);
                                instr32_o <= mk_i(
                                    "0100000" & uimm6(4 downto 0),
                                    rs1p, "101", rs1p, "0010011"); -- SRAI: funct7=0100000

                            when "10" => -- C.ANDI
                                imm6 := instr16_i(12) & instr16_i(6 downto 2);
                                instr32_o <= mk_i(sext12(imm6), rs1p, "111", rs1p, "0010011");

                            when "11" =>
                                case instr16_i(6 downto 5) is
                                    when "00" => -- C.SUB
                                        instr32_o <= mk_r("0100000", rs2p, rs1p, "000", rs1p, "0110011");
                                    when "01" => -- C.XOR
                                        instr32_o <= mk_r("0000000", rs2p, rs1p, "100", rs1p, "0110011");
                                    when "10" => -- C.OR
                                        instr32_o <= mk_r("0000000", rs2p, rs1p, "110", rs1p, "0110011");
                                    when others => -- C.AND (11)
                                        instr32_o <= mk_r("0000000", rs2p, rs1p, "111", rs1p, "0110011");
                                end case;

                            when others =>
                                instr32_o <= ILLEGAL32;
                        end case;

                    -- C.J : jal x0, offset (unconditional jump)
                    when "101" =>
                        j_imm12 := instr16_i(12) & instr16_i(8) &
                                   instr16_i(10 downto 9) & instr16_i(6) &
                                   instr16_i(7) & instr16_i(2) &
                                   instr16_i(11) & instr16_i(5 downto 3);
                        instr32_o <= mk_jal(j_imm12, "00000"); -- x0

                    -- C.BEQZ : beq rs1p, x0, offset
                    when "110" =>
                        b_imm9 := instr16_i(12) & instr16_i(6 downto 5) &
                                  instr16_i(2) & instr16_i(11 downto 10) &
                                  instr16_i(4 downto 3) & '0';
                        instr32_o <= mk_b(b_imm9, "00000", rs1p, "000"); -- BEQ

                    -- C.BNEZ : bne rs1p, x0, offset
                    when "111" =>
                        b_imm9 := instr16_i(12) & instr16_i(6 downto 5) &
                                  instr16_i(2) & instr16_i(11 downto 10) &
                                  instr16_i(4 downto 3) & '0';
                        instr32_o <= mk_b(b_imm9, "00000", rs1p, "001"); -- BNE

                    when others =>
                        instr32_o <= ILLEGAL32;
                end case;

            -- =================================================================
            -- Quadrant 2  (op = 10)
            -- =================================================================
            when "10" =>
                case f3 is

                    -- C.SLLI : slli rd, rd, shamt
                    when "000" =>
                        uimm6 := '0' & instr16_i(6 downto 2);
                        instr32_o <= mk_i(
                            "0000000" & uimm6(4 downto 0),
                            rd, "001", rd, "0010011"); -- SLLI

                    -- C.LWSP : lw rd, offset(sp)
                    -- offset = {instr[3:2], instr[12], instr[6:4]} * 4
                    when "010" =>
                        sp_off_w := instr16_i(3 downto 2) & instr16_i(12) &
                                    instr16_i(6 downto 4) & "00";
                        instr32_o <= mk_i(
                            zext12(sp_off_w),
                            "00010", "010", rd, "0000011"); -- LW from sp

                    -- C.JR / C.MV / C.EBREAK / C.JALR / C.ADD
                    when "100" =>
                        if instr16_i(12) = '0' then
                            if rs2 = "00000" then
                                -- C.JR : jalr x0, rs1, 0
                                instr32_o <= mk_i(x"000", rd, "000", "00000", "1100111");
                            else
                                -- C.MV : add rd, x0, rs2
                                instr32_o <= mk_r("0000000", rs2, "00000", "000", rd, "0110011");
                            end if;
                        else
                            if rd = "00000" and rs2 = "00000" then
                                -- C.EBREAK
                                instr32_o <= x"00100073"; -- ebreak
                            elsif rs2 = "00000" then
                                -- C.JALR : jalr x1, rs1, 0
                                instr32_o <= mk_i(x"000", rd, "000", "00001", "1100111");
                            else
                                -- C.ADD : add rd, rd, rs2
                                instr32_o <= mk_r("0000000", rs2, rd, "000", rd, "0110011");
                            end if;
                        end if;

                    -- C.SWSP : sw rs2, offset(sp)
                    -- offset = {instr[8:7], instr[12:9]} * 4
                    when "110" =>
                        sp_off_w := instr16_i(8 downto 7) & instr16_i(12 downto 9) & "00";
                        instr32_o <= mk_s(
                            zext12(sp_off_w),
                            rs2, "00010", "010", "0100011"); -- SW to sp

                    when others =>
                        instr32_o <= ILLEGAL32;
                end case;

            -- =================================================================
            -- Not compressed (op = 11) — caller should not call decompressor
            -- =================================================================
            when others =>
                -- Pass lower 16 bits (caller will use the full 32-bit word directly)
                instr32_o <= (others => '0');

        end case;
    end process decomp_proc;

end architecture rtl;
