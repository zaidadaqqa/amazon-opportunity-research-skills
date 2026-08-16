# Amazon Discovery — Bulk Funnel Stages, Budgets, and Provenance

Canonical reference for the zero-cost bulk discovery funnel driven by `hunt
discover` (`run_bulk_discovery_hunt`, `expand_current_discovery`,
`_collect_competitor_snapshots` in `Amazon-products/src/engine/research/hunt.py`),
verified against source 2026-08-16. A Skill invokes `hunt discover` and reads
its output; it never re-implements or second-guesses any stage below — the
CLI already ran this exact deterministic pipeline.

For what happens to a candidate's *relevance* inside this funnel, see
`relevance-and-filtering.md`. This file covers the funnel's stage order and
its budgets/caps.

---

## 1. The funnel, in order

`hunt discover <query> --category ... [--with-market-data mock|real]` runs:

1. **Discovery** — pull candidates from the configured static/bulk source
   for the given `(query, category)`.
2. **Cheap eligibility filter** — deterministic, zero-cost rejection (ASIN
   shape, prohibited keywords, price band; see `relevance-and-filtering.md`
   §2). Runs before any paid/live call.
3. **Relevance classification** — deterministic token-overlap classification
   against the query (`relevance-and-filtering.md` §1). Produces RELEVANT /
   AMBIGUOUS / UNRESOLVED_TITLE / (rejected) IRRELEVANT.
4. **Pre-rank ordering** for the live-validation queue (STAGE-06) — cheapest,
   most-likely-useful candidates go first, so a budget cutoff drops the
   least-promising candidates, not an arbitrary subset.
5. **Live validation** (only if `--with-market-data` is used) — bounded by
   the advancement cap, the time/call budget, and a separate sub-budget for
   resolving UNRESOLVED_TITLE candidates.
6. **Title re-resolution** for UNRESOLVED_TITLE candidates that received a
   live snapshot — reclassified against the authoritative title.

Every stage that runs out of budget marks affected candidates
`INSUFFICIENTLY_OBSERVABLE` / `STAGE_CAPPED` and proceeds — it never drops
them silently and never crashes the run for a per-candidate provider failure.

---

## 2. Budgets and caps (exact config keys and defaults)

| Rule ID | Stage | Config key | Default | Behavior when exhausted |
|---|---|---|---|---|
| STAGE-01 | Non-bulk discovery-stage cap | `research_depth.max_candidates_discovery_stage` | 50 | Truncates the (non-bulk) `run_hunt` candidate list |
| STAGE-02 | Bulk static discovery target | `research_depth.static_discovery_max_candidates` | 500 | Discovery stops once this many candidates found (a ceiling, see STAGE-15) |
| STAGE-03 | Max candidates advanced to live market data | `research_depth.max_candidates_advanced_to_market_data` | `null` (unbounded); test configs often set small values e.g. 20 | Only the first N cheap-filter survivors (by STAGE-06 order) get a live current-market call; the rest proceed on discovery-stage evidence only, reason `STAGE_CAPPED` — never dropped |
| STAGE-04 | Live-enrichment time/call budget | `research_depth.live_enrichment_max_seconds` / `research_depth.live_enrichment_max_calls` | 240 seconds / `null` (unbounded calls) | Once exhausted, remaining candidates fall back to discovery-stage evidence only; reason string includes "Live-enrichment budget exhausted" |
| STAGE-05 | Unresolved-title resolution sub-budget | `research_depth.max_unresolved_title_resolutions_per_run` | 5 (lowered from an initial 10 after real-run observation) | A separate sub-budget of STAGE-03, so a large UNRESOLVED_TITLE pool cannot crowd out RELEVANT/AMBIGUOUS candidates' live-validation slots |
| STAGE-07 | Fetch price history toggle | `research_depth.bulk_discovery_fetch_price_history` | `true` | Set `false` to skip the second live call per candidate (snapshot only, no price history) |
| STAGE-15 | Current-discovery target | (current-discovery expansion path) `current_discovery_target_candidates` | 2000 | A ceiling, not a minimum — never fabricates candidates to reach it if the source has fewer |

`STAGE-04`'s 240-second default is documented as chosen so that a 3-stage
pipeline run (discovery → deepen → VOC, each with its own live-enrichment
budget) stays under an approximate 900-second ceiling in aggregate — a
real-observed tuning constraint, not an arbitrary number.

`STAGE-05`'s reduction from 10 to 5 was a real-run-observed tuning change —
report it as such if asked why the default is 5, not "arbitrary."

---

## 3. Ordering rule for the live-validation queue

**STAGE-06**: The live-validation queue is sorted by:

1. Relevance tier: RELEVANT (0) before AMBIGUOUS (1) before UNRESOLVED_TITLE (2).
2. Then `serp_result_position` (candidates with no known position sort last).
3. Stable sort — ties preserve original discovery order.

This means when STAGE-03's cap is reached, the candidates cut off are
disproportionately UNRESOLVED_TITLE and low-relevance-order ones, not a
random subset. When reporting a `STAGE_CAPPED` result, you can accurately
say "the candidates most likely to be relevant were validated first."

---

## 4. Stop reasons and failure isolation

**STAGE-12**: `hunt discover`'s (current-discovery-expansion path) stop
reason is always exactly one of:

- `TARGET_REACHED`
- `SOURCE_EXHAUSTED`
- `BUDGET_EXHAUSTED`
- `PROVIDER_FAILURE`
- `NO_NEW_UNIQUE_RESULTS`

Report the stop reason verbatim from CLI output — do not paraphrase into a
different vocabulary.

**STAGE-10 / STAGE-11 — failure isolation (important for reporting)**:

- A single candidate's provider failure (snapshot or price-history call)
  never crashes the run. It is recorded distinctly from `NOT_FOUND` and from
  "no provider configured": `"PROVIDER_ERROR (not NOT_FOUND, not STALE):
  {exc}"`.
- A top-level discovery-call failure (the whole batch call, not one
  candidate) never crashes the run either — recorded as `discovery_error`
  with `stop_reason=PROVIDER_FAILURE` and 0 candidates; the run still
  completes and reports this cleanly rather than throwing.

**STAGE-13 / STAGE-14 — pagination discipline**: query expansion across
batches is strictly deeper pages of the *same* `(query, category)` search —
the engine never invents new search terms to keep filling a batch. A batch
with results but zero new unique ASINs stops with `NO_NEW_UNIQUE_RESULTS`
(pagination has started repeating), not a crash or infinite loop.

**STAGE-09**: A provider's own relevance/discovery classification is never
rewritten by the expansion logic — if a provider says a result is a given
classification, that classification is preserved as-is into storage.

---

## 5. Competitor-snapshot collection (`deepen-start` / `deepen-run`)

**STAGE-17**: `_collect_competitor_snapshots` reuses the *same* config keys
as STAGE-04 (`live_enrichment_max_seconds` / `live_enrichment_max_calls`),
with a fresh deadline computed per call. Per-ASIN provider failure is
isolated the same way as STAGE-10. Raw snapshots are written to the Evidence
Ledger immediately as each one completes — not batched at the end — so a
mid-run crash never loses already-collected evidence.

**STAGE-18**: `deepen-start`/`deepen-run` only collect live competitor
snapshots for opportunities whose discovery-stage transition reason actually
indicates current-market validation was attempted (`Lineage assessment:%` /
`NOT_FOUND:%` / `PROVIDER_ERROR%` reason prefixes). A candidate that was
`STAGE_CAPPED` or otherwise skipped at discovery time gets no live call at
this stage either — deep-research budget is never spent on a candidate the
funnel itself never validated.

---

## 6. Discovery provenance and dedup

**PROV-01 — classification → evidence status mapping**
(`_DISCOVERY_CLASSIFICATION_TO_EVIDENCE_STATUS`):

| Discovery classification | Evidence status |
|---|---|
| REAL_HISTORICAL | STALE |
| ESTIMATE | ESTIMATE |
| REAL_CURRENT | ESTIMATE |
| MOCK | UNKNOWN |
| UNKNOWN | UNKNOWN |

`REAL_CURRENT` is forward-looking/dead code today — no current discovery
provider actually emits it — not a mismatch, just currently unreachable.

**PROV-02 — parent ASIN identity**: `identity_level` is set to `PARENT_ASIN`
only when the raw provider result explicitly flags `is_parent_asin`;
otherwise `ASIN`. A child ASIN is never fabricated or inferred.

**PROV-03 — within-run dedup**: a `seen_asins` set deduplicates within one
run — the first occurrence of an ASIN wins the opportunity row; every
subsequent duplicate is counted (`candidates_rejected_duplicate`), never
silently dropped without a count.

**PROV-04 — no-ASIN candidates**: a keyword-only discovery result (no ASIN
at all) is counted (`candidates_rejected_no_asin`) but never becomes an
opportunity row.

---

## 7. Rule preservation

| Rule ID | This file's section | Source (Amazon-products file:line) | Test |
|---|---|---|---|
| STAGE-01 | 2 | hunt.py:121-122 | — |
| STAGE-02 | 2 | hunt.py:1138 | test_max_candidates_cap_is_respected |
| STAGE-03 | 1, 2, 3 | hunt.py:1225-1227,1412-1414,1563-1576 | test_staged_funnel_caps_candidates_advanced_to_market_data, test_staged_validation_cap_independent_of_discovery_batch_count |
| STAGE-04 | 1, 2 | hunt.py:1210-1212,1457-1458,1553-1562 | test_live_enrichment_time_budget_stops_further_provider_calls, test_live_enrichment_call_budget_stops_after_configured_count |
| STAGE-05 | 1, 2 | hunt.py:1198-1199,1415-1419,1577-1593 | test_resolution_budget_cap_never_rejects_capped_candidates |
| STAGE-06 | 3 | hunt.py:1188,1392-1399 | test_relevant_candidates_are_validated_before_unresolved_title_candidates, test_ambiguous_candidates_are_validated_before_unresolved_title_candidates |
| STAGE-07 | 2 | hunt.py:1213,1517-1523 | test_bulk_discovery_fetch_price_history_false_skips_second_live_call |
| STAGE-08 | 1 | hunt.py:1464-1513 | test_resolution_confirms_relevant_and_proceeds, test_resolution_confirms_irrelevant_and_rejects_with_distinct_reason, test_provider_failure_during_resolution_never_auto_rejects |
| STAGE-09 | 4 | hunt.py:1004 (docstring) | test_classification_from_provider_is_never_altered |
| STAGE-10 | 4 | hunt.py:138-155,1446-1456,1542-1552 | test_one_candidates_provider_failure_never_crashes_the_whole_run, test_price_history_failure_does_not_discard_a_successful_snapshot, test_no_provider_at_all_uses_distinct_message_from_not_found, test_market_data_provider_returning_none_falls_back_to_insufficiently_observable |
| STAGE-11 | 4 | hunt.py:116-120,1084-1090 | test_discovery_call_failure_never_crashes_run_bulk_discovery_hunt, test_all_batches_failing_reports_provider_failure_not_source_exhausted |
| STAGE-12 | 4 | hunt.py:921-923,1092 | test_current_discovery_expansion.py (multiple) |
| STAGE-13 | 4 | hunt.py:942-957,1001 | test_source_exhausted_for_non_paginating_provider_after_one_call, test_multiple_batches_merge_correctly |
| STAGE-14 | 4 | hunt.py:1061-1074 | (covered indirectly by pagination tests) |
| STAGE-15 | 2 | hunt.py:989-995 | test_target_never_fabricates_candidates_when_source_has_fewer, test_target_reached_stops_before_exhausting_the_source |
| STAGE-16 | 1 | hunt.py:975-982 | test_staged_validation_cap_independent_of_discovery_batch_count |
| STAGE-17 | 5 | hunt.py:271-373 | (co-located, no dedicated file) |
| STAGE-18 | 5 | hunt.py:242-268,395-408,506-516 | (enforced in code, no dedicated unit test read) |
| PROV-01 | 6 | hunt.py:860-866 | test_asin_and_evidence_are_persisted_with_real_historical_classification, test_estimate_classified_discovery_evidence_is_not_mislabeled_unknown |
| PROV-02 | 6 | hunt.py:1249-1252 | test_parent_asin_identity.py (5 tests) |
| PROV-03 | 6 | hunt.py:1241-1244 | test_dedup_within_run_creates_one_opportunity_per_asin, test_duplicate_asin_within_run_is_counted_not_silently_dropped |
| PROV-04 | 6 | hunt.py:1238-1240 | test_candidate_without_asin_is_skipped_not_crashed |
