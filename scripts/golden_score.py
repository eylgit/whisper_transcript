#!/usr/bin/env python3
"""Scores one transcript against the script it should have produced.

Called by scripts/golden.sh once per recording. Standard library only.

Two numbers come out:

  word error rate   of the text OUTSIDE fenced silence blocks, against the
                    script: (substituted + missing + extra words) / script words.
  escaped           runs of two or more consecutive output words, outside a
                    fence, that do not line up with the script. This is text
                    the reader would take as spoken and that the script does
                    not contain. It cannot tell an invented phrase from two
                    adjacent misheard words; both count, deliberately.

Text inside a fence is reported as a word count only. It is already labelled
unreliable in the transcript, so it is not held against the recording.

Normalisation is kept as small as is fair. Case and punctuation are dropped
and hyphens become spaces. Digits are spelled out ("4.2" -> "four point two"),
because the scripts are written as spoken and the model writes numerals; that
is a formatting choice, not a hearing error. Nothing else is forgiven: a
spelling variant such as "center" for "centre" counts as one wrong word.
"""
import argparse
import re
import sys

ONES = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
        "eighteen", "nineteen"]
TENS = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]


def int_words(n):
    """0..999,999 as spoken words. Larger numbers are left as digits by the caller."""
    if n < 20:
        return [ONES[n]]
    if n < 100:
        return [TENS[n // 10]] + ([ONES[n % 10]] if n % 10 else [])
    if n < 1000:
        rest = n % 100
        return [ONES[n // 100], "hundred"] + (["and"] + int_words(rest) if rest else [])
    rest = n % 1000
    return int_words(n // 1000) + ["thousand"] + (int_words(rest) if rest else [])


def spell_number(match):
    whole, _, frac = match.group(0).partition(".")
    if len(whole) > 6:
        return match.group(0)
    words = int_words(int(whole))
    if frac:
        words += ["point"] + [ONES[int(d)] for d in frac]
    return " " + " ".join(words) + " "


def words_of(text):
    text = text.lower()
    text = re.sub(r"(?<=\d),(?=\d{3}\b)", "", text)          # 1,200 -> 1200
    text = re.sub(r"\d+(?:\.\d+)?", spell_number, text)
    text = re.sub(r"[-‐-―]", " ", text)              # hyphens and dashes
    text = re.sub(r"[^a-z0-9' ]+", " ", text)
    return [w.strip("'") for w in text.split() if w.strip("'")]


def split_transcript(markdown):
    """Returns (text outside fences, text the model produced inside fences)."""
    lines = markdown.splitlines()
    if lines and lines[0].strip() == "---":                    # YAML header
        end = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
        lines = lines[end + 1:]
    outside, fenced = [], []
    for line in lines:
        if line.startswith("<details>"):                        # timestamped copy of the same text
            break
        if line.startswith("# "):
            continue
        if line.startswith(">"):
            body = line[1:].strip()
            # The fence's own wording is not model output.
            if not body or body.startswith(("⏸", "⏹", "Measured as quiet", "Treat anything below")):
                continue
            fenced.append(body)
        else:
            outside.append(line)
    return " ".join(outside), " ".join(fenced)


def align(ref, hyp):
    """Minimum-edit alignment. Returns one op per step: = S D I."""
    rows, cols = len(ref) + 1, len(hyp) + 1
    cost = [[0] * cols for _ in range(rows)]
    for i in range(rows):
        cost[i][0] = i
    for j in range(cols):
        cost[0][j] = j
    for i in range(1, rows):
        for j in range(1, cols):
            same = ref[i - 1] == hyp[j - 1]
            cost[i][j] = min(cost[i - 1][j - 1] + (0 if same else 1),
                             cost[i - 1][j] + 1, cost[i][j - 1] + 1)
    ops, i, j = [], len(ref), len(hyp)
    while i or j:
        if i and j and cost[i][j] == cost[i - 1][j - 1] + (0 if ref[i - 1] == hyp[j - 1] else 1):
            ops.append(("=" if ref[i - 1] == hyp[j - 1] else "S", hyp[j - 1]))
            i, j = i - 1, j - 1
        elif j and cost[i][j] == cost[i][j - 1] + 1:
            ops.append(("I", hyp[j - 1]))
            j -= 1
        else:
            ops.append(("D", ref[i - 1]))
            i -= 1
    return ops[::-1]


def escaped_phrases(ops):
    """Runs of >= 2 consecutive output words that match nothing in the script."""
    phrases, run = [], []
    for op, word in ops:
        if op in ("S", "I"):
            run.append(word)
            continue
        if op == "D":                                           # no output word here; the run continues
            continue
        if len(run) >= 2:
            phrases.append(" ".join(run))
        run = []
    if len(run) >= 2:
        phrases.append(" ".join(run))
    return phrases


def main():
    p = argparse.ArgumentParser()
    p.add_argument("name")
    p.add_argument("expected")
    p.add_argument("transcript")
    p.add_argument("--max-wer", type=float, default=None, help="percent; omit to report only")
    p.add_argument("--max-escaped", type=int, default=None)
    p.add_argument("--expect", choices=["pass", "known-failure"], default="pass")
    p.add_argument("--verbose", action="store_true")
    a = p.parse_args()

    ref = words_of(open(a.expected, encoding="utf-8").read())
    outside, fenced = split_transcript(open(a.transcript, encoding="utf-8").read())
    hyp = words_of(outside)
    ops = align(ref, hyp)
    errors = sum(1 for op, _ in ops if op != "=")
    wer = 100.0 * errors / len(ref)
    phrases = escaped_phrases(ops)

    if a.max_wer is None or a.max_escaped is None:
        verdict, code = "MEASURED", 0
    else:
        within = wer <= a.max_wer and len(phrases) <= a.max_escaped
        if a.expect == "pass":
            verdict, code = ("PASS", 0) if within else ("FAIL", 1)
        else:
            # A known failure that starts passing is news, and the manifest is now wrong.
            verdict, code = ("UNEXPECTED PASS", 1) if within else ("KNOWN FAILURE", 0)

    print(f"  {a.name:<34} words {len(ref):>4}   errors {wer:5.1f}%   escaped {len(phrases):>2}"
          f"   fenced {len(words_of(fenced)):>2} words   {verdict}")
    if a.verbose or verdict in ("FAIL", "UNEXPECTED PASS"):
        for phrase in phrases:
            shown = phrase if len(phrase) <= 90 else phrase[:87] + "..."
            print(f"      escaped: {shown}")
        if fenced and a.verbose:
            print(f"      fenced:  {fenced}")
    return code


if __name__ == "__main__":
    sys.exit(main())
