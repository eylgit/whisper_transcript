# The offline guarantee

## What is claimed, precisely

| | Status |
| --- | --- |
| Every process that reads the audio (`afinfo`, `afconvert`, `whisper-cli`) | **Enforced.** Run under `sandbox-exec` with the network denied by the kernel |
| The app and CLI processes themselves | **Audited.** They contain no networking code, but nothing blocks them |
| Setup (`setup.sh`) | Uses the network, for three named downloads. See the README |

Use those two words exactly. Do not write "enforced" for something that is only audited.

## The profile

Built in `Sources/Core/Sandbox.swift` and passed inline, so no profile file is written to disk.

```scheme
(version 1)
(allow default)          ; permissive base, so the GPU keeps working
(deny network*)          ; the offline guarantee
(deny file-write*)       ; no writes anywhere...
(allow file-write* (subpath "<the audio's folder>"))   ; ...except beside the audio
(allow file-write* (subpath "<GPU shader cache>"))
```

Things that are easy to break:

- **Order.** The profile language is last-match-wins. The deny rules must come before the allow
  rules for specific folders, or the folder is not writable.
- **Deny-list, not allow-list.** A strict allow-list cuts off the GPU and the app silently falls
  back to much slower CPU inference.
- **Resolved paths.** The kernel matches on fully resolved paths, so paths go through
  `realpath(3)`. A rule naming `/var/folders/...` never matches `/private/var/folders/...`.
- **Never a broad writable root.** `/` or `/private` as a writable folder would void the restriction.
- **The shader cache stays writable.** Without it every run recompiles the GPU shaders: 19 s
  against 3 s on the same clip (measured).

## Proving it

```sh
./scripts/verify-sandbox.sh
```

It reads the profile back from the built CLI (`--print-sandbox-profile`), so it tests what the
app applies and not a copy. Four probes: the network must be unreachable, a write outside the
audio's folder must fail, a write beside the audio must work, the GPU must still initialise.

**When not to trust a green result:** with no internet connection the network probe is skipped,
because "blocked" and "no network" look the same. The script prints `SKIP` and can still finish
with "checks passed". Read each line.
