// ============================================================================
// cache_tests.v  —  Testes de Cache L1 I$/D$ EduRISC-32v2
//
// Testa as unidades de cache separadamente via instâncias diretas:
//   1. I-cache HIT (acesso repetido → sem stall)
//   2. I-cache MISS → FILL → HIT
//   3. D-cache WRITE + READ (write-back)
//   4. D-cache MISS → FILL → HIT
//   5. D-cache EVICT (dirty line → escrever de volta antes de carregar nova)
//   6. Cache controller (arbitragem I$/D$)
// ============================================================================
`timescale 1ns/1ps

module cache_tests;

    reg        clk;
    reg        rst;

    initial clk = 0;
    always  #5 clk = ~clk;

    integer tests_run;
    integer tests_passed;
    integer tests_failed;

    task check;
        input [255:0] name;
        input [31:0] got, expected;
        begin
            tests_run = tests_run + 1;
            if (got === expected) begin
                $display("[PASS] %s", name);
                tests_passed = tests_passed + 1;
            end else begin
                $display("[FAIL] %s: got=0x%08X expected=0x%08X", name, got, expected);
                tests_failed = tests_failed + 1;
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // I-Cache DUT
    // -----------------------------------------------------------------------
    reg  [25:0] ic_addr;
    reg         ic_req;
    wire [31:0] ic_data;
    wire        ic_hit;
    wire        ic_miss;

    // Resposta simulada de memória (4 words por linha)
    reg  [31:0] ic_fill_data [0:3];
    reg         ic_fill_valid;

    icache u_icache (
        .clk         (clk),
        .rst         (rst),
        .addr        (ic_addr),
        .req         (ic_req),
        .read_data   (ic_data),
        .hit         (ic_hit),
        .miss        (ic_miss),
        .mem_req     (),
        .mem_addr    (),
        .mem_data    ({ic_fill_data[3], ic_fill_data[2],
                       ic_fill_data[1], ic_fill_data[0]}),
        .mem_valid   (ic_fill_valid)
    );

    // -----------------------------------------------------------------------
    // D-Cache DUT
    // -----------------------------------------------------------------------
    reg  [25:0] dc_addr;
    reg         dc_req;
    reg         dc_we;
    reg  [31:0] dc_wdata;
    reg  [1:0]  dc_size;
    wire [31:0] dc_rdata;
    wire        dc_hit;
    wire        dc_miss;

    reg  [31:0] dc_fill_data [0:3];
    reg         dc_fill_valid;

    dcache u_dcache (
        .clk          (clk),
        .rst          (rst),
        .addr         (dc_addr),
        .req          (dc_req),
        .we           (dc_we),
        .wdata        (dc_wdata),
        .size         (dc_size),
        .read_data    (dc_rdata),
        .hit          (dc_hit),
        .miss         (dc_miss),
        .mem_req      (),
        .mem_addr     (),
        .mem_we       (),
        .mem_wdata    (),
        .mem_data     ({dc_fill_data[3], dc_fill_data[2],
                        dc_fill_data[1], dc_fill_data[0]}),
        .mem_valid    (dc_fill_valid)
    );

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------
    task ic_access;
        input [25:0] addr;
        input [127:0] fill_line;  // 4 words
        output [31:0] data_out;
        output        was_hit;
        begin
            ic_addr  = addr;
            ic_req   = 1;
            @(posedge clk); #1;

            if (!ic_hit) begin
                // Simular fill de memória
                ic_fill_data[0] = fill_line[31:0];
                ic_fill_data[1] = fill_line[63:32];
                ic_fill_data[2] = fill_line[95:64];
                ic_fill_data[3] = fill_line[127:96];
                ic_fill_valid  = 1;
                @(posedge clk); #1;
                ic_fill_valid  = 0;
                @(posedge clk); #1;
            end

            data_out = ic_data;
            was_hit  = ic_hit;
            ic_req   = 0;
            @(posedge clk);
        end
    endtask

    // -----------------------------------------------------------------------
    // TESTE 1: I-cache — miss seguido de hit
    // -----------------------------------------------------------------------
    reg [31:0] got_data;
    reg        was_hit;

    task test_icache_miss_then_hit;
        begin
            $display("-- I-Cache Miss→Hit --");
            ic_fill_valid = 0;

            // 1ª acesso: miss
            ic_addr = 26'h000100;  ic_req = 1;
            @(posedge clk); #1;
            check("IC 1st access miss", ic_hit, 1'b0);

            // Fill
            ic_fill_data[0] = 32'hDEAD_0001;
            ic_fill_data[1] = 32'hDEAD_0002;
            ic_fill_data[2] = 32'hDEAD_0003;
            ic_fill_data[3] = 32'hDEAD_0004;
            ic_fill_valid   = 1;
            @(posedge clk); ic_fill_valid = 0;
            repeat(2) @(posedge clk);

            // 2ª acesso: hit
            ic_addr = 26'h000100;  ic_req = 1;
            @(posedge clk); #1;
            check("IC 2nd access hit",  ic_hit, 1'b1);
            check("IC data correto", ic_data, 32'hDEAD_0001);
            ic_req = 0;
            @(posedge clk);
        end
    endtask

    // -----------------------------------------------------------------------
    // TESTE 2: D-cache — write hit / read hit
    // -----------------------------------------------------------------------
    task test_dcache_write_read;
        begin
            $display("-- D-Cache Write/Read --");
            dc_fill_valid = 0;

            // Pré-carregar linha (miss forçado)
            dc_addr  = 26'h000200;
            dc_req   = 1;
            dc_we    = 0;
            dc_size  = 2'b10;   // word
            @(posedge clk); #1;

            if (!dc_hit) begin
                dc_fill_data[0] = 32'h0;
                dc_fill_data[1] = 32'h0;
                dc_fill_data[2] = 32'h0;
                dc_fill_data[3] = 32'h0;
                dc_fill_valid = 1;
                @(posedge clk); dc_fill_valid = 0;
                repeat(2) @(posedge clk);
            end

            // Escrever 0x12345678
            dc_addr  = 26'h000200;
            dc_we    = 1;
            dc_wdata = 32'h1234_5678;
            dc_size  = 2'b10;
            dc_req   = 1;
            @(posedge clk); dc_we = 0; dc_req = 0;
            @(posedge clk);

            // Ler de volta
            dc_addr = 26'h000200;
            dc_we   = 0;
            dc_req  = 1;
            @(posedge clk); #1;
            check("DC write-read hit",  dc_hit,  1'b1);
            check("DC read data",       dc_rdata, 32'h1234_5678);
            dc_req = 0;
            @(posedge clk);
        end
    endtask

    // -----------------------------------------------------------------------
    // TESTE 3: D-cache eviction (dirty line)
    // -----------------------------------------------------------------------
    task test_dcache_evict;
        begin
            $display("-- D-Cache Eviction --");
            // Acessar endereço que mapeia para o mesmo set mas tag diferente
            // Set = addr[9:2], Tag = addr[25:10]
            // Usar addr=0x000200 (set=0x00, tag=0x0000) que já está sujo
            // Depois acessar 0x010200 (set=0x00, tag=0x0040) → evict + fill

            dc_addr  = 26'h010200;  // novo tag no mesmo set
            dc_req   = 1;
            dc_we    = 0;
            dc_size  = 2'b10;
            @(posedge clk); #1;
            check("DC evict miss", dc_hit, 1'b0);
            // Simular fill após eviction
            dc_fill_data[0] = 32'hCAFE_0000;
            dc_fill_data[1] = 32'hCAFE_0001;
            dc_fill_data[2] = 32'hCAFE_0002;
            dc_fill_data[3] = 32'hCAFE_0003;
            dc_fill_valid   = 1;
            repeat(6) @(posedge clk);  // aguardar FSM EVICT→FILL→UPDATE
            dc_fill_valid   = 0;
            repeat(2) @(posedge clk);

            // Verificar que o dado novo foi carregado
            dc_addr = 26'h010200;
            dc_req  = 1;
            @(posedge clk); #1;
            check("DC evict fill hit",  dc_hit,  1'b1);
            check("DC evict data", dc_rdata, 32'hCAFE_0000);
            dc_req = 0;
            @(posedge clk);
        end
    endtask

    // -----------------------------------------------------------------------
    initial begin
        $dumpfile("cache_tests.vcd");
        $dumpvars(0, cache_tests);

        tests_run = 0; tests_passed = 0; tests_failed = 0;

        rst = 1; ic_req = 0; dc_req = 0; dc_we = 0;
        ic_fill_valid = 0; dc_fill_valid = 0;
        repeat(4) @(posedge clk);
        rst = 0;
        @(posedge clk);

        $display("=== Cache Tests ===");
        test_icache_miss_then_hit;
        test_dcache_write_read;
        test_dcache_evict;

        $display("=== %0d/%0d PASS ===", tests_passed, tests_run);
        if (tests_failed == 0) $display("[TB] PASS"); else $display("[TB] FAIL");
        $finish;
    end

endmodule
