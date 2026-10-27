# Finding the pauses

Part of [how transcription works](../how-transcription-works.md).

Loudness is judged relative to each recording: its own noise floor (5th percentile of frame
loudness) and its own speech level (90th). A fixed threshold is wrong for half of all recordings.
If the two levels are within 15 dB the recording is too noisy to cut safely and is transcribed
in one pass.

Code: `Sources/Core/SilenceDetector.swift`.

## The numbers

Every tunable number is in `Sources/Core/Tuning.swift`, each with a comment saying what it does
and why. Change a number there, never inline. They are **starting values**: chosen from how
speech behaves and a few test recordings, not validated across a set of real ones.
