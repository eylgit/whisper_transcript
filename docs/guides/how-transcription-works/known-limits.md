# Known limits

Part of [how transcription works](../how-transcription-works.md).

- **A recording with no three-second pause gets no protection.** A loop can still happen and
  nothing in the output will flag it. Documented in the README as a deliberate trade.
- Each range costs about 3.2 seconds of fixed overhead (measured), so very frequent pauses are slow.
- Accuracy is scored only on three clear synthetic recordings (`./scripts/golden.sh`; see
  [`testing.md`](../testing.md)). Nothing measures it on real voices, accents or noise.
- The first limit above is not theoretical: the golden set holds a 107-second monologue on which
  the default settings repeat one sentence six times.
