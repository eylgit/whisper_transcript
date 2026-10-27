# Split the transcription guide into an overview and detail pages

**Date:** 2026-10-27 · **State:** done

## Background

`docs/guides/` was flat: four files of equal weight. `how-transcription-works.md` carried the
two faults, the cutting rule, the loudness measurement, the tuning numbers and the known limits
in one page, so any task touching one of those read all of them. The entry point already asks
agents to "open only the guides the task needs"; inside that guide there was no way to.

The second repository with the same documentation shape already does this: an overview page
and a folder of detail pages beneath it.

## Outcome

`how-transcription-works.md` is an overview: the two faults, the rule in one line, and a table
of three detail pages in `how-transcription-works/`. Each detail page says which overview it
belongs to. No sentence of the original is lost or reworded; sentences only moved.

## Constraints

- Documentation only. No change under `Sources/`, `Tests/`, `scripts/` or `golden/`.
- Every link in `CLAUDE.md`, `overall.md` and the guides resolves after the change.
- Nothing personal in files or commit metadata.

## Steps

1. Write this plan.
2. Create `how-transcription-works/` with `cutting-at-pauses.md`, `finding-the-pauses.md`,
   `known-limits.md`, each a section moved from the overview.
3. Rewrite the overview as faults · rule · table of detail pages.
4. Update the guide's row in `CLAUDE.md` and `overall.md` to say it is an overview.
5. Check every relative link resolves.

## Exit criteria

- [x] `docs/guides/how-transcription-works/` holds three pages; the overview links to each and
      each links back.
- [x] Every Markdown link under `docs/guides/` and in `CLAUDE.md` resolves to a file. *Checked
      with a script over every `](...)` target.*
- [x] The moved text is unchanged apart from headings and the "part of" line.
- [x] No change outside `docs/` and `CLAUDE.md`.

## What went wrong

- Nothing in the split itself. One thing is now true that was not before: there are two levels,
  and the entry file's table only names the top one. The rule "open only the guide the task
  needs" now also applies inside a guide, and nothing enforces that either.
