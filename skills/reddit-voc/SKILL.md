---
name: reddit-voc
description: Use for systematic Reddit research to find real customer pain points/praise for a candidate at COMPETITOR_ANALYSIS state or later, when no automated review-text provider is available. Feeds findings into hunt voc-add or the manual-VOC-completion path.
---

# Reddit VOC (Voice of Customer)

No automated review-text provider exists in this project
(`hunt voc-prepare --mode real` always fails — see
`references/cli-command-reference.md`). Reddit/community research done by
you (Claude), recorded through `hunt voc-add`, is the real substitute for
real-mode opportunities. Follow `references/browser-research-protocol.md`
for general search discipline and `references/voc.md` for the exact
vocabulary and the manual-completion rule this skill exists to satisfy.

## When to use this

An opportunity is in state `COMPETITOR_ANALYSIS` (after
`competition-analysis`/`hunt deepen-start`) and either:
- there is no automated review-provider path available (the normal
  real-mode case), or
- you want to supplement automated `voc-submit` findings with real
  community evidence.

## 1. Search systematically

- **Subreddit selection**: start with the product category's obvious
  subreddit(s) if one exists, plus general buying-advice subs
  (`r/BuyItForLife`, `r/ProductPorn`-adjacent, category-specific
  communities). Don't stop at the first subreddit that returns results.
- **Search terms**: derive from the product category and known
  competitor/brand names, not generic marketing terms. Vary phrasing
  across searches rather than re-running the same query
  (`browser-research-protocol.md` §4).
- **Distinguish a recurring complaint from a one-off** using the
  `SINGLE_ANECDOTE` / `REPEATED_PATTERN` / `STRONG_RECURRING_SIGNAL` tiers
  in `browser-research-protocol.md` §3 — require at least two independent
  threads/comments saying substantially the same thing before calling
  anything `RECURRING`, and reserve `DOMINANT` for genuinely widespread
  recurrence.
- Actively look for disconfirming evidence too (positive mentions of the
  same attribute, competing products with the same complaint) — don't stop
  the moment you find support for a hypothesis.

## 2. Classify each finding using voc.md's exact vocabulary

Every finding recorded must use these values, verbatim (`references/voc.md`
§2) — nothing else is valid, and the CLI will reject anything outside them:

| Field | Values |
|---|---|
| `category` | `product`, `packaging`, `shipping`, `expectation_mismatch`, `misuse`, `isolated` |
| `severity` | `LOW`, `MEDIUM`, `HIGH` |
| `frequency_signal` | `ISOLATED`, `RECURRING`, `DOMINANT` |
| `solvability` | `EASY`, `MODERATE`, `HARD`, `UNKNOWN` (optional; default to `UNKNOWN` if you can't tell) |

## 3. Record each real finding

```
hunt voc-add <opportunity_id> \
  --category product \
  --description "<what customers actually said, paraphrased, not invented>" \
  --severity MEDIUM \
  --frequency-signal RECURRING \
  --source-note "found on r/<subreddit>, thread '<title/URL or clear identifier>'"
```

- `--source-note` must point to something real and specific enough to be
  checked later — never a vague "seen on Reddit."
- Only record what was actually read. Do not paraphrase into something
  stronger than what was said (per the fabrication prohibitions in
  `browser-research-protocol.md` §1 — no invented sentiment).
- Each real finding gets its own `voc-add` call — do not batch multiple
  distinct complaints into one description.

## 4. Complete the VOC stage

After recording everything found (zero or more `voc-add` calls), advance
the opportunity out of `COMPETITOR_ANALYSIS`:

```
hunt voc-manual-complete <opportunity_id>
```

If at least one `voc-add` finding was recorded, this succeeds directly. If
genuinely **nothing** worth recording turned up after a real search:

```
hunt voc-manual-complete <opportunity_id> --confirm-no-findings
```

**`--confirm-no-findings` is only valid after an actual search happened.**
It is not a shortcut to skip this stage — passing it without having really
searched is itself a fabrication (asserting "we checked and found nothing"
when no checking occurred). See `references/voc.md` §5 for why this command
exists at all: without it, every real-mode opportunity would deadlock
permanently at `COMPETITOR_ANALYSIS`, since no automated provider can ever
satisfy `voc-submit`.

Calling `voc-manual-complete` with neither a prior finding nor
`--confirm-no-findings` will be refused by the engine (`ValueError`, not a
silent skip) — this is expected behavior, not a bug to route around.

## Next

Once VOC completes, the opportunity is in `VOC_ANALYSIS` — proceed to the
`differentiation` skill.
