#!/bin/bash
# Scores the model's actual output against recordings whose correct text is known.
#
# The unit tests cover the logic around the model. This is the only check on
# what the model itself returns. It needs the built CLI, the 3.1 GB model and a
# GPU, so it runs on your machine and never in CI.
#
#   ./scripts/golden.sh            one line per run
#   ./scripts/golden.sh --verbose  also print the escaped and fenced text
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/build/transcribe"
# GOLDEN_DIR points the run at another set, e.g. a scratch copy when checking
# that a wrong script really does fail.
GOLDEN="${GOLDEN_DIR:-$ROOT/golden}"
[ -x "$CLI" ] || { echo "error: build/transcribe missing; run scripts/build-app.sh" >&2; exit 1; }

VERBOSE=()
[ "${1:-}" = "--verbose" ] && VERBOSE=(--verbose)

# Inside build/, never /tmp: the sandbox only lets the pipeline write beside
# the audio, and nothing this tool touches should land outside the project.
WORKDIR="$(mktemp -d "$ROOT/build/golden-run.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; printf '%s' "${s%"${s##*[![:space:]]}"}"; }

echo "  golden set: ${GOLDEN#"$ROOT/"}/manifest.txt"
echo
fail=0; n=0
while IFS='|' read -r label audio options max_wer max_escaped expect; do
    label="$(trim "$label")"
    case "$label" in ''|'#'*) continue ;; esac
    audio="$(trim "$audio")"; options="$(trim "$options")"
    max_wer="$(trim "$max_wer")"; max_escaped="$(trim "$max_escaped")"; expect="$(trim "$expect")"
    n=$((n+1))

    # A folder per run, so two runs of the same recording cannot collide.
    run="$WORKDIR/$n"; mkdir -p "$run"
    cp "$GOLDEN/$audio" "$run/"
    # shellcheck disable=SC2086  # options are split into words on purpose
    if ! "$CLI" --quiet $options "$run/$audio" >/dev/null 2>"$run/stderr"; then
        printf "  %-34s transcription failed:\n" "$label"; sed 's/^/      /' "$run/stderr"
        fail=$((fail+1)); continue
    fi

    args=(--expect "$expect")
    [ "$max_wer" != "-" ] && args+=(--max-wer "$max_wer")
    [ "$max_escaped" != "-" ] && args+=(--max-escaped "$max_escaped")
    python3 "$ROOT/scripts/golden_score.py" "$label" "$GOLDEN/${audio%.*}.txt" "$run/${audio%.*}.md" \
        "${args[@]}" ${VERBOSE[@]+"${VERBOSE[@]}"} || fail=$((fail+1))
done < "$GOLDEN/manifest.txt"

echo
if [ "$fail" -eq 0 ]; then
    printf "  \033[32m%d runs as expected\033[0m\n" "$n"
else
    printf "  \033[31m%d of %d runs NOT as expected\033[0m\n" "$fail" "$n"
    exit 1
fi
