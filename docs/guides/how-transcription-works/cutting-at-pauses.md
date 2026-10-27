# Cutting at pauses

Part of [how transcription works](../how-transcription-works.md).

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
