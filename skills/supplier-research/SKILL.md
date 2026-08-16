---
name: supplier-research
description: Use to research supplier feasibility for a promising candidate via legitimate web research, then record the human-confirmed result via hunt supplier-set. Never fabricates MOQ/pricing/certifications.
---

# Supplier Research

Researches whether a candidate product can actually be sourced, then
records the outcome via `hunt supplier-set` — the **only** mechanism in the
engine that can move the supplier hard gate off its default `UNKNOWN`
state. Full vocabulary and human-origination rules live in
`references/supplier-ip.md`; read it before using this Skill.

## When to use this

For a promising candidate (typically at `COMPETITOR_ANALYSIS` or later —
supplier feasibility matters most once a candidate has survived earlier,
cheaper filters; see `time-budget-controller.md`) where sourcing feasibility
is still unknown.

## Step 1 — Check what's already recorded

```
hunt supplier-show <opportunity_id>
```

`NOT_YET_VALIDATED` means nothing is recorded yet. Otherwise, review the
existing record before deciding whether new research is warranted
(`time-budget-controller.md` Rule 2).

## Step 2 — Legitimate research approaches

Treat manufacturer directories (Alibaba, Global Sources, similar B2B
marketplaces), trade-show listings, and direct manufacturer/brand websites
as **research targets** — sources to search and read, the same way any web
search works. This is not scraping and not automated data extraction; it is
using a browser or search tool to find publicly available supplier
listings, MOQs, and stated pricing, the same way a human sourcing manager
would.

Useful signals to look for:
- Whether multiple suppliers appear to manufacture this product category at
  all (a complete absence of any listed manufacturer is itself a finding).
- Stated MOQ, unit pricing ranges, and lead times as published by the
  supplier (these are the supplier's own claims, not verified facts, until
  a human actually engages and confirms them).
- Stated certifications relevant to the category (e.g. FDA, CPSIA, CE) —
  note what's claimed, but do not treat a claimed certification as
  confirmed without evidence.

## Step 3 — What counts as which status

Per `references/supplier-ip.md` SUP-01, only these four literal values are
valid for `--supplier-status`:

| Status | When it applies |
|---|---|
| `UNKNOWN` | Default — no assessment recorded, or research inconclusive |
| `MANUAL_SOURCING_REQUIRED` | Sourcing looks plausible in principle (suppliers exist, no confirmed dead end) but has not been validated with an actual quote/confirmed terms yet |
| `VALIDATED` | A human has an actual, confirmed supplier quote/terms they are willing to stand behind |
| `CONFIRMED_IMPOSSIBLE` | Sourcing has been genuinely ruled out — e.g. every identifiable supplier has confirmed they cannot produce it, or a confirmed regulatory/manufacturing blocker exists |

`CONFIRMED_IMPOSSIBLE` is the status that fires the supplier hard gate — it
must be reserved for genuinely confirmed dead ends, never for "sourcing
looks hard" or "I couldn't find many suppliers in a quick search," which is
`MANUAL_SOURCING_REQUIRED` territory instead.

## Step 4 — The hard rule: human confirmation required before recording

`hunt supplier-set` must only ever be called with a status value that:

1. **A human explicitly told this Skill to record** ("I got a quote, mark
   it VALIDATED"), or
2. **Claude Browser found in a verifiable primary source AND the human then
   explicitly confirmed that finding as accurate.**

Claude Browser research alone — however thorough, however confident the
findings look — is **never sufficient by itself** to call
`hunt supplier-set` with `VALIDATED` or `CONFIRMED_IMPOSSIBLE`. Present the
research findings to the human first, and only record the status after the
human has confirmed it. This is because `supplier_status` is the single
lever that can move the supplier hard gate (`references/supplier-ip.md`
SUP-03), and no pipeline stage — including this Skill — is permitted to
infer it on its own authority.

```
hunt supplier-set <opportunity_id> \
  --supplier-status <UNKNOWN|MANUAL_SOURCING_REQUIRED|VALIDATED|CONFIRMED_IMPOSSIBLE> \
  [--supplier-name ...] [--unit-cost-quoted ...] [--moq ...] \
  [--lead-time-days ...] [--certifications ...] [--supplier-notes ...]
```

Never fabricate `--unit-cost-quoted`, `--moq`, `--lead-time-days`, or
`--certifications` — these must be the actual figures a supplier stated (and
ideally a human confirmed), never a plausible estimate for the category.

## What this Skill must never do

- Never call `hunt supplier-set` with a status inferred solely from its own
  research judgment.
- Never invent MOQ, unit pricing, lead times, or certifications not
  actually observed from a real source.
- Never treat "I couldn't quickly find a supplier" as `CONFIRMED_IMPOSSIBLE`
  — that requires a genuinely confirmed dead end, not an inconclusive
  search.
- Never scrape, bypass access controls, or attempt automated data
  extraction from supplier sites — this is legitimate research (searching,
  reading, relaying), not automated harvesting.

See `references/supplier-ip.md` for the full vocabulary, the documented
`SUPPLIER_UNKNOWN`/`UNKNOWN` naming mismatch (use the code's actual
`UNKNOWN`), and the rule-preservation table.
