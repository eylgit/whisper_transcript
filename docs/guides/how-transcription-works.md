# How transcription works

This is the overview. It names the two faults being contained and the one rule that contains
them, then points to the detail. Open a detail page only when the task touches that part.

## The two faults being contained

1. **The model invents text during silence.** Given quiet audio it still writes something, most
   often "Thank you."
2. **The model can lock into repeating a sentence.** It carries text forward between its
   30-second windows to keep punctuation coherent, and sometimes that feedback catches.

Neither can be switched off without cost. Disabling the carry-forward globally was measured and
made every transcript worse (lost punctuation, severed sentences), so it is on by default and
`--no-carry-context` turns it off per file. The design contains the faults instead.

## The rule, in one line

A recording of two minutes or more is cut at every pause of three seconds or more, each piece is
transcribed on its own with nothing carried across, and every quiet stretch is fenced and
labelled in the output.

## The detail

| Page | Open it when the task touches |
| --- | --- |
| [`how-transcription-works/cutting-at-pauses.md`](how-transcription-works/cutting-at-pauses.md) | the ranges around a pause, overlap, the midpoint rule, the fence in the output |
| [`how-transcription-works/finding-the-pauses.md`](how-transcription-works/finding-the-pauses.md) | loudness measurement, the noise-floor and speech-level percentiles, the tuning numbers |
| [`how-transcription-works/known-limits.md`](how-transcription-works/known-limits.md) | what is not protected, what is not measured, the cost per range |
