# Add a small golden set for the model's output

**Date:** 2026-10-05 · **State:** done

## Background

The unit tests cover the logic around the speech model: the chunk plan, the silence detector,
the Markdown labels, the sandbox. Nothing checks the model's own output. Whether a transcript is
accurate has been judged by eye, once, on a few practice recordings.

Those practice recordings were made by a synthetic voice reading known scripts, so the correct
text is known. That is everything a golden set needs: fixed inputs, known answers, a score, and
a command that can be run again after any change. It was never assembled.

## Outcome

- One command transcribes a fixed set of recordings and scores each against its known script.
- Two numbers per recording: the word error rate of the text outside fenced silence blocks, and
  the count of invented phrases that appear outside a fence.
- The command exits non-zero when a recording scores worse than its threshold.

## Constraints

- No change under `Sources/` or `Tests/`.
- Synthetic voice only. No real person's voice enters the repository, and no audio file carries
  a name, username, hostname or path in its metadata.
- A recording is used only if its script is verified by transcribing it and reading the result.
  Two honest recordings are better than three doubtful ones.
- No new dependencies. Bash and the Python 3 standard library only.
- The set runs on the owner's machine, not in CI: the model is 3.1 GB and needs a GPU.
- Do not tune the normalisation or the thresholds to flatter the numbers.

## Steps

1. Write this plan and its exit criteria before building anything.
2. Pair each candidate recording with its script and verify the pairing by a real run.
3. Put the chosen recordings and expected text in `golden/`.
4. Write `scripts/golden.sh` and its helper.
5. Run it and record the baseline numbers.
6. Set thresholds from the baseline, with a margin.
7. See the command fail for the right reason, then remove the sabotage.
8. Update `docs/guides/testing.md`, `CLAUDE.md` and the other guides that list this as missing.

**About the order of steps 5 and 6.** A sensible pass threshold cannot be written before the
first run, because nobody knows what this model scores on these recordings. So the baseline is
measured first and the thresholds are set afterwards. What is fixed in advance is the method:
how text is normalised, what counts as an error, and what counts as an escaped invention.

## Exit criteria

Written before the build. Ticked afterwards, with what checks each.

- [x] `./scripts/golden.sh` runs every recording in `golden/` and prints one line each with the
      word error rate, the escaped-invention count, and PASS or FAIL. *Four runs over three recordings.*
- [x] Every recording's script has been checked against a real transcription by reading both.
- [x] The baseline numbers are recorded in this file, exactly as measured. *Below.*
- [x] Thresholds are stated in one place, with the margin and the reason. *`golden/manifest.txt`.*
- [x] The command has been seen to exit non-zero for a real mismatch, and that is recorded here. *Below.*
- [x] `./scripts/test.sh` still passes, 41 tests.
- [x] `docs/guides/testing.md` says how to run it and what it does not prove.
- [x] No audio in the repository carries personal metadata. *Checked with `afinfo` and by reading
      the files' text atoms: a FLAC vendor string and an AAC gapless-playback tag, nothing else.*

## What was chosen

| In `golden/` | What it is | Script |
| --- | --- | --- |
| `standup.flac` | 2 m 19 s. Four spoken passages separated by three gaps of 30 s or more | four short passages, 127 words |
| `meeting-roomtone.flac` | 46 s. Two passages with a 30 s gap filled with faint room noise | two passages, 54 words |
| `monologue.m4a` | 1 m 47 s of continuous speech with no pause long enough to cut at | 323 words |

All three are a synthetic voice reading text written for the purpose. The two WAV sources were
stored as FLAC, which is lossless, to keep the repository small (5.9 MB of WAV became 2.8 MB).
The monologue was already a 0.4 MB AAC file and is stored as it was.

Not used: two more copies of the standup recording under other names (byte-identical), and a
second 46 s recording that differs from `meeting-roomtone` only in having digital silence in the
gap. It has the same script and scored the same, so it would have added run time and no
information.

## Baseline, as first measured

First run, before any threshold existed:

| Run | Script words | Word errors | Escaped | Fenced |
| --- | --- | --- | --- | --- |
| `standup` | 127 | 0.0 % | 0 | 6 words ("Thank you." three times) |
| `meeting-roomtone` | 54 | 0.0 % | 0 | 0 |
| `monologue` | 323 | 30.7 % | 8 | 0 |
| `monologue --no-carry-context` | 323 | 0.3 % | 0 | 0 |

Two further full runs gave the same numbers. One run takes about 1 m 45 s.

The one error in the last row is "center" where the script has "centre". It is counted.

## Thresholds, set after the baseline

At most 2 % word errors and no escaped text, for every run. On scripts this short, 2 % is a word
or two of spelling or run-to-run difference; a single lost sentence is 8 % or worse.

`monologue` with default settings does not meet that, and is not going to: it is the known
limitation in the README, reproduced. It is marked `known-failure` against the same 2 % and 0,
and was not given a threshold loose enough to pass. If it ever starts passing, the run fails
with UNEXPECTED PASS so the manifest is corrected.

## Seeing it fail

Done in a scratch copy of `golden/` under `build/`, pointed to with `GOLDEN_DIR`, then deleted.

| Sabotage | Result | Exit code |
| --- | --- | --- |
| One sentence removed from `meeting-roomtone`'s script, so the transcript holds text the script does not | 63.6 % errors, 1 escaped, **FAIL**. The escaped text printed was the removed sentence | 1 |
| `monologue` marked as an ordinary recording | 30.7 % errors, 8 escaped, **FAIL**. The escaped text printed was the repeated sentence | 1 |
| `meeting-roomtone` wrongly marked `known-failure` | 0.0 %, **UNEXPECTED PASS** | 1 |

## What went wrong, and what is left

- **The first definition of "escaped" would have missed the loop.** It was going to count only
  extra words. A repetition loop mostly *replaces* script words with wrong ones, so it would have
  scored zero. The count is now any run of two or more output words that line up with nothing.
  The cost is that it cannot tell an invention from two adjacent misheard words.
- **Numerals had to be handled.** The model writes "4.2 million" where the script says "four
  point two million". Numerals are spelled out before comparing. Nothing else is normalised
  beyond case, punctuation and hyphens.
- **A stray file appeared once.** During one full run a `monologue.whisper-tmp.wav` was found in
  `golden/`. The runner copies each recording into `build/` before transcribing and could not be
  made to reproduce it in a watched re-run; its origin is not known. `.gitignore` now excludes
  that suffix and `.md` files under `golden/` so a recording transcribed in place cannot be
  committed by accident.
- **This is three recordings in one clear synthetic voice.** It proves the method and guards
  these three against regressions. It says nothing about real voices, accents or noise.
- **Nothing forces anyone to run it.** It cannot run in CI. The numbers in the testing guide are
  only as current as the last manual run.

**Not done, on purpose:** recordings of real speech (privacy, and a licence question for public
corpora); checking that fenced blocks sit at the right timestamps; a score for punctuation, which
is the thing the carry-forward setting actually trades against.
