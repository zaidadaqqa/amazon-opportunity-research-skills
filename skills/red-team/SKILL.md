---
name: red-team
description: Use after DIFFERENTIATION_ANALYSIS state to adversarially attack a candidate before it reaches human review. Drives redteam-prepare/redteam-submit.
---

# Red Team

The goal of this stage is **honest adversarial pressure, not reassurance.**
Your job is to find real reasons this candidate should NOT be built, using
only evidence already gathered — not to confirm it's a good idea. This is
the last automated stage before `HUMAN_REVIEW`; whatever you don't surface
here, the human reviewer won't see flagged for them.

## When to use this

Opportunity is in state `DIFFERENTIATION_ANALYSIS` (after the
`differentiation` skill completed).

## Steps

1. **Get the prompt.**
   ```
   hunt redteam-prepare <opportunity_id>
   ```
   Requires `DIFFERENTIATION_ANALYSIS` state.

2. **Work through the full checklist actively**, from
   `references/red-team.md` §2 — for each item, ask whether evidence
   already gathered (competitor autopsy, VOC findings, browser research,
   demand intelligence, economics) plausibly connects to it. Do not
   manufacture a risk with no evidence connection, and do not soften a
   well-evidenced negative finding to make the candidate look better:
   - Demand illusion
   - Seasonal illusion
   - Temporary OOS (out-of-stock) illusion
   - Review contamination
   - Suspicious review patterns
   - Margin illusion
   - PPC (advertising) dependence
   - Logistics problems
   - Supplier problems
   - IP/compliance risk
   - Dominant incumbents
   - Copycat vulnerability
   - Stale/expired data
   - Cross-source contradictions

3. **Cite `evidence_id`s for every `EVIDENCED`-labeled finding.** If a
   finding you believe is real can't actually be tied to a surviving
   evidence_id, the engine will automatically downgrade it to `HYPOTHESIS`
   rather than drop it (`references/red-team.md` §1) — still worth
   recording, because it stays visible to the human as a flag even without
   a solid citation. This is deliberately different from how VOC (drops
   ungrounded findings entirely) and differentiation (collapses to
   `LOW_COPYCAT_RESISTANCE`) each handle the same problem — see
   `references/red-team.md` §1 for why all three are intentional, not
   inconsistent.

4. **Submit.**
   ```
   hunt redteam-submit <opportunity_id> --file <path>
   ```
   Requires `DIFFERENTIATION_ANALYSIS`; validates + persists; advances
   `DIFFERENTIATION_ANALYSIS → RED_TEAM → HUMAN_REVIEW`.

## What "done well" looks like

- A red-team pass with **zero findings on one genuinely strong candidate**
  is fine — not every candidate has a real, evidenced flaw.
- A red-team pass that **suspiciously never finds anything on any
  candidate** is a signal this skill is being run wrong — either the
  checklist isn't being applied seriously, or evidence that should have
  been gathered upstream (VOC, competitor autopsy, browser research)
  wasn't. If you notice this pattern across multiple candidates, stop and
  reconsider whether earlier stages were actually thorough rather than
  concluding every candidate is simply clean.
- Do not make the final accept/reject call yourself — that happens at
  `HUMAN_REVIEW` via `hunt decide`, run by the human, never by this skill
  or any automated stage (`core-rules.md` rule 2).

See `references/red-team.md` for the full rule set, including the exact
EVIDENCED-vs-HYPOTHESIS mechanics and source references.
