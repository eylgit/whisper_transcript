#!/bin/bash
# One-time setup for Transcribe. Needs the network exactly once, here.
# Everything afterwards runs entirely offline.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
WCPP="$ROOT/vendor/whisper.cpp"

# Pinned so a rebuild reproduces the same binary rather than whatever is on
# master today.
WHISPER_COMMIT="642b5d3260e020c2fc6f34a9569d10ddd7672963"
MODEL="large-v3"
MODEL_SHA256="64d182b440b98d5203c4f9bd541544d84c605196c4f7b845dfa11fb23594d1e2"

say() { printf "\n\033[1m==> %s\033[0m\n" "$*"; }
die() { printf "\033[31merror: %s\033[0m\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------- prereqs
say "checking prerequisites"
[ "$(uname -s)" = "Darwin" ] || die "macOS only"
xcode-select -p >/dev/null 2>&1 || die "Xcode Command Line Tools missing. Run: xcode-select --install"
[ -x /usr/bin/swiftc ] || die "swiftc not found; install the Command Line Tools"
[ -x /usr/bin/afconvert ] || die "afconvert not found (it ships with macOS)"
[ -x /usr/bin/sandbox-exec ] || die "sandbox-exec not found; the offline guarantee cannot be enforced"
echo "    macOS $(sw_vers -productVersion) on $(uname -m)"

# cmake is the only thing whisper.cpp needs that macOS does not ship.
if command -v cmake >/dev/null 2>&1; then
    CMAKE=cmake
elif [ -x "$HOME/.local/bin/cmake" ]; then
    CMAKE="$HOME/.local/bin/cmake"
else
    say "installing cmake (no sudo, no Homebrew)"
    if command -v uv >/dev/null 2>&1; then
        uv tool install cmake
    elif command -v pip3 >/dev/null 2>&1; then
        pip3 install --user cmake
    else
        die "cmake not found. Install it, or install uv (https://astral.sh/uv) and re-run."
    fi
    CMAKE="$(command -v cmake || echo "$HOME/.local/bin/cmake")"
fi
echo "    cmake: $($CMAKE --version | head -1)"

# ------------------------------------------------------------- whisper.cpp
say "fetching whisper.cpp @ ${WHISPER_COMMIT:0:12}"
mkdir -p "$ROOT/vendor"
if [ -f "$ROOT/.gitmodules" ] && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    # whisper.cpp is tracked as a submodule, which already pins the commit.
    git -C "$ROOT" submodule update --init --recursive vendor/whisper.cpp
elif [ ! -d "$WCPP/.git" ]; then
    git clone https://github.com/ggml-org/whisper.cpp.git "$WCPP"
    git -C "$WCPP" checkout -q "$WHISPER_COMMIT"
fi
actual_commit="$(git -C "$WCPP" rev-parse HEAD)"
if [ "$actual_commit" != "$WHISPER_COMMIT" ]; then
    echo "    note: whisper.cpp is at ${actual_commit:0:12}, expected ${WHISPER_COMMIT:0:12}"
    git -C "$WCPP" fetch origin "$WHISPER_COMMIT" 2>/dev/null || git -C "$WCPP" fetch origin
    git -C "$WCPP" checkout -q "$WHISPER_COMMIT"
fi
echo "    at $(git -C "$WCPP" rev-parse --short HEAD)"

say "building whisper.cpp (Metal GPU backend)"
# Core ML is deliberately OFF: on Apple Silicon the Neural Engine measured
# ~1.6x SLOWER than the GPU for large-v3 (2220 ms vs 1362 ms per encode).
# scripts/make-coreml-encoder.sh remains if you want to re-measure on other hardware.
"$CMAKE" -B "$WCPP/build" -S "$WCPP" -DWHISPER_COREML=0 -DCMAKE_BUILD_TYPE=Release
"$CMAKE" --build "$WCPP/build" -j"$(sysctl -n hw.perflevel0.logicalcpu)" --config Release
[ -x "$WCPP/build/bin/whisper-cli" ] || die "whisper-cli did not build"

# ------------------------------------------------------------------ model
say "downloading the $MODEL model (~3.1 GB, once)"
mkdir -p "$ROOT/models"
MODEL_FILE="$ROOT/models/ggml-$MODEL.bin"
if [ -f "$MODEL_FILE" ] && [ "$(shasum -a 256 "$MODEL_FILE" | cut -d' ' -f1)" = "$MODEL_SHA256" ]; then
    echo "    already present and verified"
else
    sh "$WCPP/models/download-ggml-model.sh" "$MODEL" "$ROOT/models"
    say "verifying model checksum"
    actual="$(shasum -a 256 "$MODEL_FILE" | cut -d' ' -f1)"
    [ "$actual" = "$MODEL_SHA256" ] || die "checksum mismatch!
  expected $MODEL_SHA256
  actual   $actual
The download may be corrupt or the upstream file changed. Not proceeding."
    echo "    sha256 ok"
fi

# -------------------------------------------------------------------- app
say "building Transcribe.app and the transcribe CLI"
"$ROOT/scripts/build-app.sh"

# ----------------------------------------------------------- verification
say "verifying the sandbox actually enforces the offline guarantee"
"$ROOT/scripts/verify-sandbox.sh"

say "smoke test"
cp "$WCPP/samples/jfk.wav" "$ROOT/build/setup-check.wav"
"$ROOT/build/transcribe" -q "$ROOT/build/setup-check.wav" >/dev/null
grep -q "country" "$ROOT/build/setup-check.md" \
    && echo "    transcribed the sample correctly" \
    || die "smoke test produced unexpected output"
rm -f "$ROOT/build/setup-check.wav" "$ROOT/build/setup-check.md"

cat <<DONE

  Setup complete.

    Transcribe.app   drag audio onto it, or onto its Dock icon
    build/transcribe command line: transcribe recording.m4a

  Nothing from here on needs the network.
DONE
