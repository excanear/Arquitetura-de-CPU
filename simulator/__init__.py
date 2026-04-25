"""
__init__.py — Pacote simulator EduRISC-32v2
"""

from simulator.cpu_simulator import CPUSimulator, PipelineSnapshot, SimStats
from simulator.debugger import Debugger

__all__ = ["CPUSimulator", "PipelineSnapshot", "SimStats", "Debugger"]
