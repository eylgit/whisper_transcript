# Correct what the README says the randomised test found

**Date:** 2026-10-05 · **State:** done

## Background

The README said, in two places, that the randomised chunk-coverage test "found a real bug": a
recording that opens with a pause produced a "speech" chunk lying inside the silence.

That sentence came from the agent's summary on the day the tests were written, and was copied
into the README without being checked. While writing `docs/guides/testing.md` the fault was put
back in a scratch copy and the tests were run. The randomised test still passed. The named test
for a pause at the very start failed.

The reason is simple once seen. The fault mislabels a range; it does not leave any audio
uncovered. The randomised test checks coverage only.

## Outcome

The README says what is true: writing the tests found the bug, a named test pins it, and the
randomised test guards a different rule.

## Constraints

- Change only the wording of the claim. No source, test or script changes.
- Do not weaken the claim further than the evidence requires. The bug was real and is pinned.
- Rule 4 in `CLAUDE.md`: never state a guarantee more strongly than it is checked.

## Steps

1. Put the fault back in a scratch copy (`if cursor < silence.start` becomes always true in
   `ChunkPlanner.swift`) and run `./scripts/test.sh --filter ChunkPlannerTests`.
2. Record which tests fail.
3. Correct the feature table row and the Tests section of the README.
4. Check `docs/guides/testing.md` already says the same thing. It does; no change needed.

## Exit criteria

- [x] With the fault put back: `testCoverageHoldsAcrossManyRandomRecordings` passes and
      `testSilenceAtTheVeryStartDoesNotProduceAZeroWidthChunk` fails.
- [x] The README no longer credits the randomised test with finding the bug, in either place.
- [x] The README and `docs/guides/testing.md` agree.
- [x] `./scripts/test.sh` passes, 41 tests, on the unmodified source.

## What went wrong

- **An agent's summary of its own work was published as fact.** The summary was plausible and
  mostly right, which is why it was not questioned.
- **A test was trusted without ever being seen to fail for the stated reason.**

What changed because of it: `docs/guides/testing.md` now has the rule "to trust a test, see it
fail", and `CLAUDE.md` rule 4 covers claims in general.

**Left open:** the randomised test could check labelling as well as coverage (no speech range
may lie wholly inside a pause). That would make the original sentence true. Not done here,
because this task changes no test.
