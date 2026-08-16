---
name: competition-analysis
description: Use after amazon-validation, to run competitor autopsy and interpret concentration/dominance/lineage signals for a candidate. Drives `hunt deepen-start` and interprets its competitor_result output. Use before VOC/differentiation/red-team stages.
---

# Competition Analysis

**This skill computes nothing itself.** Every number and label below is
already computed by deterministic, tested Python in the wrapped engine —
`hunt deepen-start` runs the competitor autopsy and lineage checks and
prints the result. Your job is only to read that result correctly and
interpret it using the exact thresholds in `references/competition.md` —
never recompute a concentration figure, never round differently, never
relabel a level the engine already assigned.

## When to use this

After a candidate has reached `ECONOMICS_CHECK` (via `amazon-validation`
and economics being set). This is the entry point to the "deepen" pipeline:
`COMPETITOR_ANALYSIS → VOC_ANALYSIS → DIFFERENTIATION_ANALYSIS → RED_TEAM →
HUMAN_REVIEW`.

## Steps

1. **Run the autopsy.**
   ```
   hunt deepen-start <run_id>
   ```
   This is deterministic, no LLM involved. It advances every eligible
   `ECONOMICS_CHECK` opportunity in the run to `COMPETITOR_ANALYSIS` and
   prints a JSON `competitor_result` per opportunity. Note every printed
   `opportunity_id` — each needs its own pass through the rest of this
   pipeline.

2. **Read the concentration figures, not just the labels.** For each of
   `review_concentration`, `brand_concentration`, `oos_frequency`, check:
   - The reported value (or `None`/`UNKNOWN`).
   - `competitor_set_size` (post parent-ASIN-dedup — this is the number
     that matters) vs `competitor_set_size_before_parent_dedup` (raw
     rows). If these differ a lot, sibling variants were correctly
     collapsed — do not describe them as separate competitors in any
     summary you write.
   - The assigned level: `HIGH` / `MODERATE` / `LOW` / `UNKNOWN` /
     `INSUFFICIENT_SAMPLE`. See `references/competition.md` §3 for the
     exact thresholds (0.6 review/brand concentration, 0.15 OOS
     frequency, `min_sample_size=3`).

3. **Interpret levels correctly — do not upgrade or downgrade them
   yourself:**
   - `HIGH` review or brand concentration → a small number of
     listings/brands dominate the visible competitor set. Worth flagging
     as a headwind, but this is advisory, not itself a hard reject.
   - `MODERATE` → between half and full threshold; note it, don't treat it
     as equivalent to HIGH.
   - `LOW` → no obvious dominance signal in what was observed.
   - `UNKNOWN` → the underlying value was `None` (empty/degenerate input).
     Never describe this as "low concentration" — it means the metric
     could not be computed, not that it was computed and came out low.
   - `INSUFFICIENT_SAMPLE` → fewer than 3 competitor observations. Never
     report the raw ratio behind this (e.g. "100% concentrated" from one
     competitor) as if it were a reliable figure — the engine deliberately
     withholds the precise decimal below the sample gate
     (`competition.md` §4); do not reconstruct it from other output.

4. **Check the lineage result for each opportunity.** The `lineage_status`
   will be one of `CLEAN`, `SUSPECTED_CONTAMINATION`, or `UNKNOWN` — it can
   never be `CONFIRMED_CONTAMINATION` at this stage (`competition.md` §5.1).
   - `SUSPECTED_CONTAMINATION` → **flag for human attention explicitly in
     your summary.** Say what triggered it (parent ASIN + high review
     count + short history, per `competition.md` §5.2; or an abrupt ≥25%
     review-count jump, per §5.3). Do **not** treat this as disqualifying
     and do not skip the candidate — only a recorded human decision can
     promote this to `CONFIRMED_CONTAMINATION`, and only that literal
     value fires the hard gate (`competition.md` §5.5). Continue the
     candidate through the rest of the pipeline unless a human tells you
     otherwise.
   - `UNKNOWN` → note that lineage could not be assessed (no or thin price
     history) — this is not evidence of either a clean or contaminated
     listing.
   - `CLEAN` → at least 3 stable observed snapshots with no red flags.

5. **Move on.** Once you've recorded the interpretation (concentration
   levels + lineage flag) in whatever running summary you're keeping for
   this candidate, proceed to `reddit-voc` / the automated VOC path for
   each `opportunity_id` still in `COMPETITOR_ANALYSIS`.

## What NOT to do

- Do not compute `max(counts)/sum(counts)` or any other formula yourself —
  read the engine's output.
- Do not report a precise decimal for a metric the engine marked
  `INSUFFICIENT_SAMPLE` or `UNKNOWN`.
- Do not reject or silently deprioritize a candidate because of
  `SUSPECTED_CONTAMINATION` — surface it, don't decide on it.
- Do not call `hunt deepen-start` again on the same run expecting new
  competitor data beyond the budget cap — it is scoped and budget-limited
  by design (`competition.md` §1.2); repeated calls will not fetch more
  than the configured window allows.

See `references/competition.md` for the full rule set with exact source
line references and tests.
