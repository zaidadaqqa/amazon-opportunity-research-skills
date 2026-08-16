---
name: differentiation
description: Use after VOC_ANALYSIS state to assess whether a candidate has a real, evidence-backed moat versus competitors. Drives differentiation-prepare/differentiation-submit.
---

# Differentiation

Assess whether this candidate has a genuine, defensible advantage over
competitors — grounded strictly in evidence already in the Evidence Ledger.
Never invent a moat claim without a citation: per
`references/differentiation.md` §2, the engine forcibly collapses any
ungrounded moat claim to `LOW_COPYCAT_RESISTANCE` with `moat_categories=[]`
regardless of what was submitted, so an ungrounded claim only wastes a turn
— it never survives into the persisted result.

## When to use this

Opportunity is in state `VOC_ANALYSIS` (after `reddit-voc` or automated
`voc-submit` completed).

## Steps

1. **Get the prompt.**
   ```
   hunt differentiation-prepare <opportunity_id>
   ```
   This requires `VOC_ANALYSIS` state and prints the system+user prompt.

2. **Build the `DifferentiationAssessment` JSON, grounded only in real
   evidence_ids.** Draw only on evidence already in the Evidence Ledger:
   - VOC findings (from `voc-submit` or `voc-add`) — a repeated,
     solvable pain point competitors haven't addressed is real
     differentiation evidence.
   - Competitor autopsy notes (`competition-analysis` output) — e.g.
     genuinely fragmented, low-quality competition with a specific
     addressable gap.
   - Browser research findings (`hunt browser-evidence-add` output, if
     collected) — e.g. a verified pattern in what competitors' own listings
     /pages claim vs. what they lack.
   - Every moat claim in the JSON must cite the `evidence_id`(s) it is
     actually based on.

3. **Default to `LOW_COPYCAT_RESISTANCE` unless the evidence clearly
   supports more.** Per `references/differentiation.md` §1, trivial
   differences — color, pack count, generic "premium" language — are never
   a moat by default. Only claim a stronger category when the evidence
   genuinely supports one of the fixed categories:
   `CAPITAL_MOAT`, `COMPLIANCE_MOAT`, `MANUFACTURING_MOAT`,
   `SOFTWARE_ECOSYSTEM_MOAT`, `BRAND_MOAT`, `DESIGN_MOAT`. Do not invent a
   category outside this set.

4. **Submit.**
   ```
   hunt differentiation-submit <opportunity_id> --file <path>
   ```
   Requires `VOC_ANALYSIS`; validates + persists; advances
   `VOC_ANALYSIS → DIFFERENTIATION_ANALYSIS`.

5. **If the LLM/analysis step fails**, the engine itself returns
   `copycat_resistance="UNKNOWN"` rather than crashing or guessing
   (`references/differentiation.md` §3) — if you hit this, report `UNKNOWN`
   as the result; do not retry with a fabricated assessment to force a
   non-`UNKNOWN` outcome.

## Next

Proceed to the `red-team` skill once state is `DIFFERENTIATION_ANALYSIS`.

See `references/differentiation.md` for the full moat vocabulary, the
default-LOW rule, and the evidence-downgrade mechanics in detail.
