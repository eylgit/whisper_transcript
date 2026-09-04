#!/usr/bin/env python3
"""Compile a .mlpackage to a .mlmodelc.

Upstream whisper.cpp uses `xcrun coremlc`, which ships only with the full Xcode
install. coremltools can do the same job through the CoreML framework, which
keeps this project buildable with Command Line Tools alone.
"""
import shutil
import sys
from pathlib import Path

import coremltools as ct


def main() -> int:
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <input.mlpackage> <output.mlmodelc>", file=sys.stderr)
        return 2

    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    if not src.exists():
        print(f"error: {src} does not exist", file=sys.stderr)
        return 1

    print(f"compiling {src} ...", flush=True)
    compiled = Path(ct.utils.compile_model(str(src)))

    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        shutil.rmtree(dst)
    shutil.move(str(compiled), str(dst))
    print(f"wrote {dst}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
