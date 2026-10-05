# How transcription works

## The two faults being contained

1. **The model invents text during silence.** Given quiet audio it still writes something, most
   often "Thank you."
2. **The model can lock into repeating a sentence.** It carries text forward between its
   30-second windows to keep punctuation coherent, and sometimes that feedback catches.

Neither can be switched off without cost. Disabling the carry-forward globally was measured and
made every transcript worse (lost punctuation, severed sentences), so it is on by default and
`--no-carry-context` turns it off per file. The design contains the faults instead.

## The rule

A recording of two minutes or more is cut at every pause of three seconds or more. Around each
pause, three overlapping ranges are produced:

```text
  ...speech A...  [========= pause =========]  ...speech B...
  speech   [ ...A... --- pauseStart + 1.5 s ]
  silence          [ pauseStart ------- pauseEnd ]
  speech                     [ pauseEnd - 1.5 s --- ...B... ]
```

- Each range is transcribed on its own, with nothing carried across. A repetition loop cannot
  pass a cut.
- Ranges overlap on purpose. A gap would lose speech; an overlap repeats a moment of quiet.
- The quiet range is transcribed too, in case the loudness measurement was wrong, then fenced and
  labelled in the output. `--skip-silence` skips it, and the label says which happened.
- A speech range is only produced when speech actually precedes the pause. A recording that
  opens with a pause starts with a silence range.
- whisper reads fixed 30-second windows and overruns a range's end, so a segment is kept only if
  its midpoint falls inside the range that produced it.

Code: `Sources/Core/ChunkPlanner.swift` (the ranges), `Sources/Core/Transcriber.swift` (the
midpoint rule), `Sources/Core/MarkdownBuilder.swift` (the fence and its wording).

## Finding the pauses

Loudness is judged relative to each recording: its own noise floor (5th percentile of frame
loudness) and its own speech level (90th). A fixed threshold is wrong for half of all recordings.
If the two levels are within 15 dB the recording is too noisy to cut safely and is transcribed
in one pass.

Code: `Sources/Core/SilenceDetector.swift`.

## The numbers

Every tunable number is in `Sources/Core/Tuning.swift`, each with a comment saying what it does
and why. Change a number there, never inline. They are **starting values**: chosen from how
speech behaves and a few test recordings, not validated across a set of real ones.

## Known limits

- **A recording with no three-second pause gets no protection.** A loop can still happen and
  nothing in the output will flag it. Documented in the README as a deliberate trade.
- Each range costs about 3.2 seconds of fixed overhead (measured), so very frequent pauses are slow.
- Accuracy is scored only on three clear synthetic recordings (`./scripts/golden.sh`; see
  [`testing.md`](testing.md)). Nothing measures it on real voices, accents or noise.
- The first limit above is not theoretical: the golden set holds a 107-second monologue on which
  the default settings repeat one sentence six times.
