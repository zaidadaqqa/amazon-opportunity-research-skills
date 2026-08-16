# Competition — Competitor Autopsy and ASIN Lineage Rules

Canonical reference for the deterministic competitor-autopsy layer
(`Amazon-products/src/engine/analysis/competitor_autopsy.py`) and the
ASIN-lineage/contamination layer (`Amazon-products/src/engine/lineage/analysis.py`,
`src/engine/ranking/gates.py`), verified against source 2026-08-16. This is
what `hunt deepen-start <run_id>` actually computes — a Skill never
recomputes any of this, it only reads and correctly interprets the JSON the
engine already produced.

---

## 1. Competitor autopsy pipeline

### 1.1 Parent-ASIN dedup (CMP-01)

`_dedupe_by_parent` keys every competitor snapshot by `parent_asin or asin`
and keeps only the first-seen representative per key. This runs on
`asin_market_snapshots` **before** any concentration metric is computed, so
sibling variants of the same parent listing (colors, sizes, pack counts) are
never counted as separate competitors in `review_concentration`,
`brand_concentration`, or `oos_frequency`.

- Every raw observation is still persisted as its own row — dedup only
  affects the shared aggregate figures, never the underlying evidence.
- Reported alongside the aggregates: `competitor_set_size` (post-dedup) vs
  `competitor_set_size_before_parent_dedup` (raw row count) — always read
  both, never assume they are equal.
- Immutable/hard rule (anti-double-count safety, not advisory).

### 1.2 Competitor-set scoping and budget (CMP-07, CMP-08)

- `deepen_start`/`deepen_run` only collects competitor snapshots for
  opportunities whose current-market validation was actually attempted at
  discovery — it never expands the competitor set beyond what discovery
  already touched.
- The pass is bounded by `research_depth.live_enrichment_max_seconds` /
  `max_calls` (a fresh window, independent of the discovery budget),
  per-ASIN error-isolated (one competitor's failed fetch never aborts the
  rest), and persists each successful snapshot immediately — crash-safe,
  not all-or-nothing.

---

## 2. Concentration formulas (verbatim)

All three take a list of per-competitor observations and return a float in
`[0, 1]`, or `None` when the input is empty/degenerate. `None` always means
**UNKNOWN**, never a fabricated `0.0` and never `LOW`.

### 2.1 Review concentration (CMP-02)

```
review_concentration(counts) = max(counts) / sum(counts)
```
`None` if the list is empty or `sum(counts) == 0`. A single competitor
(`n=1`) returns `1.0` (full share) — correct by formula, but see §3 for why
that `1.0` must still not be reported as a precise HIGH concentration.

### 2.2 Brand concentration (CMP-03)

```
brand_concentration(brands) = top_brand_count / len(brands)
```
`None` if `brands` is empty.

### 2.3 Out-of-stock frequency (CMP-04)

Fraction of **observed** (non-`None`) stock-status entries that are `False`
(out of stock). `None` entries (never actually observed) are excluded from
both the numerator and the denominator — they do not silently count as
"in stock."

---

## 3. Concentration level thresholds — HIGH / MODERATE / LOW / UNKNOWN / INSUFFICIENT_SAMPLE (CMP-05)

`_level(value, n, min_sample, threshold)`:

| Condition | Level |
|---|---|
| `value is None` | `UNKNOWN` |
| `n < min_sample` | `INSUFFICIENT_SAMPLE` |
| `value >= threshold` | `HIGH` |
| `threshold/2 <= value < threshold` | `MODERATE` |
| `value < threshold/2` | `LOW` |

The `INSUFFICIENT_SAMPLE` check runs **before** the HIGH/MODERATE/LOW split
— a small sample never reaches a level label at all, regardless of how
extreme its raw value looks.

Configured thresholds (`config/default.yaml:221-243`, verbatim):

| Config key | Value |
|---|---|
| `competition.high_review_concentration_threshold` | `0.6` |
| `competition.high_brand_concentration_threshold` | `0.6` |
| `competition.high_oos_frequency_threshold` | `0.15` |
| `competition.min_sample_size` | `3` |

- Boundary is inclusive at the top: `value >= threshold` → `HIGH` (e.g.
  review concentration `0.6` → HIGH, `0.59` → not HIGH).
- `n=1`, `value=1.0` → `INSUFFICIENT_SAMPLE`, **not** HIGH — a lone
  competitor observation is never enough to call the market concentrated.
  `n=3` is the first sample size that clears the gate.
- These labels are **advisory interpretation only** — they are not
  themselves a hard reject gate. A HIGH concentration label does not reject
  a candidate by itself; it is one signal to weigh, same as everything else
  in this file.
- Thresholds are configurable (values above are the shipped defaults);
  the *shape* of the rule (None≠LOW, insufficient-sample≠a precise decimal)
  is immutable.

## 4. Reportable-value rounding and sample gate (CMP-06)

`_reportable(value, n, min_sample)`: returns `None` if `value is None or n <
min_sample`, else `round(value, 2)`.

**Never report a precise-looking decimal computed from fewer than
`min_sample_size` (3) observations.** A `1.0` or `0.83` from 1–2
observations is misleading, not evidence — the engine itself withholds it
(returns `None`/`INSUFFICIENT_SAMPLE`) and a Skill must not "fill in" a
number the engine declined to report, nor restate the raw underlying ratio
as if it were the reportable value.

---

## 5. ASIN lineage / contamination

Source: `src/engine/lineage/analysis.py`, `src/engine/ranking/gates.py`.

### 5.1 Never auto-confirms (LIN-01)

`assess_lineage` returns only one of `CLEAN | SUSPECTED_CONTAMINATION |
UNKNOWN`. It can **never** return `CONFIRMED_CONTAMINATION` — that value can
only be written by a recorded human decision. This is a core safety
invariant, not a modeling limitation to work around.

### 5.2 Heuristic A — parent ASIN + high reviews + short history (LIN-02)

`SUSPECTED_CONTAMINATION` fires when **all** of:
- `parent_asin` is set, AND
- `review_count >= lineage.min_reviews_for_new_listing_flag` (**500**), AND
- `len(observed_snapshots) < lineage.min_history_points_for_established`
  (**3**)

i.e. a listing that already carries hundreds of reviews but has almost no
independently observed history of its own — a classic sign of inherited
reviews from a merged/relisted parent.

### 5.3 Heuristic B — abrupt review-count jump (LIN-03)

```
jump_ratio = (curr.review_count - prev.review_count) / max(prev.review_count, 1)
```
`jump_ratio >= lineage.review_jump_ratio_threshold` (**0.25**, i.e. a 25%+
jump between consecutive observations) → `SUSPECTED_CONTAMINATION`. Small
organic growth (e.g. 100 → 110 → 118) does **not** trigger this — the
threshold is deliberately set above normal review-velocity noise.

### 5.4 UNKNOWN when history is absent or thin (LIN-04)

- No `price_history` at all → `UNKNOWN`.
- Fewer than 3 observed snapshots, and neither heuristic above already fired
  `SUSPECTED` → `UNKNOWN`, **never** `CLEAN`. `CLEAN` requires at least 3
  observed, stable snapshots.

### 5.5 Hard gate only fires on the literal CONFIRMED string (GATE-01)

`evaluate_gates` (`src/engine/ranking/gates.py`) rejects an opportunity for
contamination only when `lineage_status == "CONFIRMED_CONTAMINATION"`
literally. `UNKNOWN` and `SUSPECTED_CONTAMINATION` never fire this gate —
they are reasons to flag for human review, not reasons to reject. Config:
`hard_gates.reject_on_confirmed_asin_contamination: true` (independently
toggleable from the IP and supplier gates). A gate fire moves the
opportunity to `REJECTED` and records `rejection_reason="hard_gate"`.

---

## 6. Rule preservation

| Rule ID | This file's section | Source (Amazon-products file:line) | Test |
|---|---|---|---|
| CMP-01 | 1.1 | competitor_autopsy.py:18-36, invoked at :142 | test_dedupe_by_parent_keeps_one_representative_per_parent, test_dedupe_by_parent_never_merges_distinct_standalone_asins, test_run_competitor_autopsy_does_not_double_count_sibling_variants |
| CMP-07 | 1.2 | hunt.py:395-411, :506-521 | test_deepen_start_never_calls_provider_for_stage_capped_candidates |
| CMP-08 | 1.2 | (deepen budget logic) | test_deepen_start_one_competitor_failure_does_not_crash_the_whole_pass, test_deepen_start_time_budget_stops_further_calls, test_deepen_start_call_budget_stops_after_configured_count, test_competitor_snapshots_persist_incrementally_not_only_at_the_end, test_competitor_evidence_survives_even_when_process_is_interrupted_before_autopsy_runs |
| CMP-02 | 2.1 | competitor_autopsy.py:39-47 | test_review_concentration_normal (0.6), test_review_concentration_empty_list_is_unknown, test_review_concentration_all_zero_is_unknown, test_review_concentration_single_item_is_full_share (1.0) |
| CMP-03 | 2.2 | competitor_autopsy.py:50-56 | (formula, same suite as CMP-02) |
| CMP-04 | 2.3 | competitor_autopsy.py:59-67 | (formula, same suite as CMP-02) |
| CMP-05 | 3 | competitor_autopsy.py:70-85; config/default.yaml:221-243 | boundary-inclusive-at-0.6 tests; n=1 value=1.0 → INSUFFICIENT_SAMPLE test; n=3-clears-gate test |
| CMP-06 | 4 | competitor_autopsy.py:88-97 | test_run_competitor_autopsy_small_sample_never_reports_precise_decimal |
| LIN-01 | 5.1 | lineage/analysis.py:1-9; gates.py:9-12 | test_never_returns_confirmed_contamination |
| LIN-02 | 5.2 | lineage/analysis.py:44-58 | test_suspected_contamination_parent_asin_high_reviews_short_history (6100 reviews, 2 snapshots → SUSPECTED) |
| LIN-03 | 5.3 | lineage/analysis.py:60-73 | test_suspected_contamination_abrupt_review_jump (105→500), test_small_organic_growth_not_flagged (100→110→118, not flagged) |
| LIN-04 | 5.4 | lineage/analysis.py:36-40, :78-85 | test_unknown_when_no_history, test_unknown_when_insufficient_history_points, test_clean_with_stable_established_history (3 points stable → CLEAN) |
| GATE-01 | 5.5 | ranking/gates.py:33-75; config/default.yaml:282-290 | test_unknown_never_triggers_a_gate, test_suspected_contamination_does_not_fail_gate, test_confirmed_contamination_fails_gate (and siblings for IP/supplier) |
