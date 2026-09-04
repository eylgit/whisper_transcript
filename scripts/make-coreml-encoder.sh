#!/bin/sh
# Generate the Core ML encoder for the Neural Engine.
#
# Build-time only: nothing here runs during transcription. The PyTorch checkpoint
# is downloaded into build/ inside this project (not ~/.cache) so it stays visible
# and is removed with the rest of the build scratch.
set -e

MODEL="${1:-large-v3}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV="$ROOT/build/coreml-venv"
WCPP="$ROOT/vendor/whisper.cpp"

[ -x "$VENV/bin/python" ] || { echo "error: $VENV missing; run setup.sh first" >&2; exit 1; }

echo "==> converting $MODEL encoder to Core ML (downloads the OpenAI checkpoint on first run)"
cd "$WCPP"
XDG_CACHE_HOME="$ROOT/build/torch-cache" \
  "$VENV/bin/python" models/convert-whisper-to-coreml.py \
    --model "$MODEL" --encoder-only True --optimize-ane True

echo "==> compiling .mlpackage -> .mlmodelc (via coremltools; no Xcode required)"
"$VENV/bin/python" "$ROOT/scripts/compile_mlpackage.py" \
  "$WCPP/models/coreml-encoder-$MODEL.mlpackage" \
  "$ROOT/models/ggml-$MODEL-encoder.mlmodelc"

echo "==> done: $ROOT/models/ggml-$MODEL-encoder.mlmodelc"
