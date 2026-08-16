---
name: browser-research
description: Use for systematic web research on a serious candidate (COMPETITOR_ANALYSIS state or later) to fill evidence gaps no automated provider can — customer complaints/praise beyond Amazon, competitor websites, alternative products, non-Amazon market context, regulatory/IP signals. Never for raw discovery-stage candidates.
---

# Browser Research

This Skill fills the exact capability gaps documented in
`references/provider-capability.md` — no automated provider in this project
has a live review-text API, discovers by free-text concept reliably, or looks
outside Amazon at all. It does not replace the deterministic engine; it feeds
evidence into it, at the engine's own defined tier, through the engine's own
commands.

## 0. Precondition check — do this first, every time

Browser research is expensive (your time, and the human's time reviewing
results). It is reserved for candidates that have already survived cheap
discovery, cheap filtering, economics check, and competitor autopsy.

Run `hunt show <opportunity_id>` and confirm `state` is one of:
`COMPETITOR_ANALYSIS`, `VOC_ANALYSIS`, `DIFFERENTIATION_ANALYSIS`, `RED_TEAM`,
`HUMAN_REVIEW`, `QUALIFIED`, `PENDING_HUMAN_REVIEW`. This is the exact same
`ELIGIBLE_STATES` allow-list `hunt browser-brief` itself enforces (I3 in the
rule inventory) — it will refuse (`ValueError`, not a silent no-op) below
`COMPETITOR_ANALYSIS`. **Do not attempt this Skill on a raw
`DISCOVERED`/`PRE_FILTERED`/`VALIDATING`/`ECONOMICS_CHECK` candidate** — the
engine's own refusal exists precisely because running this against the full
discovery pool (often 100+ candidates) would violate cost discipline
(`core-rules.md`, time/cost section).

## 1. Step one — generate the brief

```
hunt browser-brief <opportunity_id>
```

This prints (and by default saves) an **EXTERNAL BROWSER RESEARCH BRIEF**
built entirely from evidence already in the project (existing Amazon
market/competition/demand data) — it makes no network call itself. The brief
already contains:

- 14 lettered investigation areas (demand context, community discussion, real
  customer problems, alternatives/workarounds, non-Amazon competition,
  publicly-visible Amazon evidence, failures/complaints, desired
  improvements, commercial intent, persistence vs. hype, seasonality,
  differentiation gaps, red-team evidence, contradictory evidence).
- **Seven explicit fabrication prohibitions** the brief generator itself
  writes into the prompt: fabricated statistics; invented search volume;
  invented review sentiment; treating one anecdote as a market-wide trend;
  treating affiliate/SEO content as primary evidence; double-counting
  parent/child ASIN variants as separate competitors; unsupported claims of
  sales figures or profitability.
- A requirement that every claim cite a real source URL — no source, no
  claim — and that you distinguish `SINGLE_ANECDOTE` from
  `REPEATED_PATTERN` from `STRONG_RECURRING_SIGNAL` for every pattern you
  report, never collapsing one comment into "a trend."

**You must follow these prohibitions literally, not as loose guidance.**
They are the engine's own anti-hallucination contract for this step, not a
suggestion you may relax because the research "feels" solid.

## 2. Step two — conduct the actual research

Do the real web/Reddit/forum/competitor-site research the brief's 14 areas
describe. Do not log into Amazon, do not automate Amazon page access beyond
normal public browsing, do not attempt any of the "must not build" items in
`CLAUDE.md` (no scraping-as-architecture, no CAPTCHA bypass, no anti-bot
evasion). Publicly accessible pages only.

## 3. Step three — package findings and ingest them

Build an `ExternalEvidencePack`-shaped JSON matching the 16-section format
the brief requested (executive finding, demand evidence, customer problems,
customer language, community evidence, external competition, Amazon
evidence, review pain points, alternatives/workarounds, gaps, opportunity
hypotheses, red-team findings, evidence strength, missing evidence,
recommendation, source index). Then:

```
hunt browser-evidence-add <opportunity_id> --file <evidence-pack.json>
```

## 4. Tier reminder — read this every time before writing a report

Everything ingested through `browser-evidence-add` is recorded at
`source_type=EXTERNAL_BROWSER_RESEARCH`, `status=ESTIMATE` — **never
`FACT`**, because this project did not itself observe the primary source
(I1 in `evidence-model.md`/`provider-capability.md`). This is a distinct
trust tier from `HUMAN_VERIFIED` (a human's own direct observation, see
`references/human-input-protocol.md`) and from `LLM_INFERENCE` (reasoning
over evidence already in the project) — never conflate the three when
writing a report.

Only **traceable** findings — those with real, non-empty `source_urls` —
become VOC `pain_points` rows automatically. Untraceable findings (no
source) are preserved in the raw pack JSON (nothing is discarded) but never
promoted into VOC. If a finding matters but has no source URL, that is a
signal to go find the source, not to report it as if it were traceable.

Do not manually re-type a Claude Browser finding into `hunt voc-add` as if a
human personally observed it — that would mislabel the evidence tier. Use
`browser-evidence-add` for anything that came from browser research; use
`voc-add` only when a human is relaying their own direct observation.

## 5. Time and cost discipline

This step is expensive. It exists only for survivors. Never run it:

- against a candidate below `COMPETITOR_ANALYSIS` (the engine refuses this
  anyway, but don't even attempt it),
- speculatively across many candidates "just in case" — reserve it for
  candidates a human has indicated are worth the deeper look,
- repeatedly on the same candidate without new information to look for —
  check `hunt browser-evidence-show <opportunity_id>` first; if research was
  already recorded and nothing material has changed, don't redo it.

## Cross-references

- `references/provider-capability.md` — the exact capability gaps this Skill exists to fill (Keepa/Logimu/DataForSEO/static-dataset limitations).
- `references/evidence-model.md` — the `EXTERNAL_BROWSER_RESEARCH` tier definition and why it's capped at `ESTIMATE`.
- `references/human-input-protocol.md` — how this differs from the `HUMAN_VERIFIED` commands (`market-snapshot-set`, `supplier-set`, `voc-add` for direct human observation).
- `references/cli-command-reference.md` — full `browser-brief` / `browser-evidence-add` / `browser-evidence-show` command syntax.
