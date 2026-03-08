"""
toolchain/__init__.py — EduRISC-32v2 Toolchain Package
Expõe as interfaces públicas de linker e loader.
"""

from .linker import Linker, LinkerError
from .loader import Loader, LoaderError

__all__ = ["Linker", "LinkerError", "Loader", "LoaderError"]
__version__ = "2.0.0"
