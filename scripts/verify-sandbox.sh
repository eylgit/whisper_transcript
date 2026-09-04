#!/bin/bash
# Proves the sandbox actually enforces what the README claims, using the exact
# profile the app applies at runtime rather than a copy of it.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/build/transcribe"
[ -x "$CLI" ] || { echo "error: build/transcribe missing; run scripts/build-app.sh" >&2; exit 1; }

WORKDIR="$(mktemp -d "$ROOT/build/sandbox-check.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

PROFILE="$("$CLI" --print-sandbox-profile "$WORKDIR")"
sandboxed() { /usr/bin/sandbox-exec -p "$PROFILE" "$@"; }

pass=0; fail=0
ok()   { printf "    \033[32mPASS\033[0m %s\n" "$1"; pass=$((pass+1)); }
bad()  { printf "    \033[31mFAIL\033[0m %s\n" "$1"; fail=$((fail+1)); }
skip() { printf "    \033[33mSKIP\033[0m %s\n" "$1"; }

echo "  profile applied to every child process:"
echo "$PROFILE" | sed 's/^/    | /'
echo
echo "  checks:"

# 1. Network must be blocked. Only meaningful if the network works unsandboxed.
if /usr/bin/curl -s -m 8 -o /dev/null https://example.com 2>/dev/null; then
    if sandboxed /usr/bin/curl -s -m 8 -o /dev/null https://example.com 2>/dev/null; then
        bad "network reached from inside the sandbox"
    else
        ok "network is blocked inside the sandbox"
    fi
else
    skip "network check (no internet available to test against)"
fi

# 2. Writing outside the audio folder must be refused.
# Probe somewhere genuinely outside the permitted set -- the home directory.
OUTSIDE="$HOME/.transcribe-sandbox-probe.$$"
rm -f "$OUTSIDE"
if sandboxed /usr/bin/touch "$OUTSIDE" 2>/dev/null && [ -f "$OUTSIDE" ]; then
    bad "wrote outside the permitted folder ($OUTSIDE)"
    rm -f "$OUTSIDE"
else
    ok "writing outside the audio folder is refused"
fi

# 3. Writing beside the audio file must still work, or nothing can run.
if sandboxed /usr/bin/touch "$WORKDIR/probe" 2>/dev/null && [ -f "$WORKDIR/probe" ]; then
    ok "writing beside the audio file is permitted"
else
    bad "could not write into the audio folder; transcription would fail"
fi

# 4. The GPU must survive the sandbox, or we silently fall back to slow CPU.
if [ -x "$ROOT/vendor/whisper.cpp/build/bin/whisper-cli" ]; then
    ERR="$WORKDIR/metal.err"
    cp "$ROOT/vendor/whisper.cpp/samples/jfk.wav" "$WORKDIR/" 2>/dev/null
    MODEL="$(ls "$ROOT"/models/ggml-*.bin 2>/dev/null | head -1)"
    if [ -n "$MODEL" ] && [ -f "$WORKDIR/jfk.wav" ]; then
        sandboxed "$ROOT/vendor/whisper.cpp/build/bin/whisper-cli" \
            -m "$MODEL" -f "$WORKDIR/jfk.wav" -l en -t 4 >/dev/null 2>"$ERR"
        if grep -q "ggml_metal_init: found device" "$ERR"; then
            ok "Metal GPU still initialises under the sandbox"
        else
            bad "Metal did not initialise under the sandbox (would fall back to CPU)"
        fi
    else
        skip "GPU check (model or sample missing)"
    fi
fi

echo
if [ "$fail" -eq 0 ]; then
    printf "  \033[32m%d checks passed\033[0m\n" "$pass"
else
    printf "  \033[31m%d passed, %d FAILED\033[0m\n" "$pass" "$fail"
    exit 1
fi
