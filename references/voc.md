# VOC — Voice-of-Customer / Review Analysis Rules

Canonical reference for the deterministic VOC/review-analysis layer
(`Amazon-products/src/engine/analysis/review_analysis.py`,
`src/engine/validation/evidence_validator.py`, `hunt.py` VOC commands),
verified against source 2026-08-16. Applies to `hunt voc-prepare` /
`voc-submit` / `voc-add` / `voc-manual-complete`. A Skill never invents a
pain point or reclassifies one outside this vocabulary — it only records
what was actually observed and lets the engine validate/persist it.

---

## 1. Evidence anchoring — drop, never partially trust (VOC-01)

Every review is written to the Evidence Ledger **before** it is shown to the
LLM (or before a human/Skill records a manual finding). The model/finding
must cite a real `evidence_id`. `evidence_validator.validate_llm_output`
(VAL-01) walks the structured output and checks every `evidence_ids` list
against the real ledger.

**If a pain point cites even one invalid `evidence_id`, the entire pain
point is dropped — not partially trusted, not kept with the bad citation
stripped out.** This is the strictest of the three domain-specific
anti-hallucination strategies in this rule set (contrast with
`differentiation.md`'s collapse-to-LOW and `red-team.md`'s
downgrade-to-HYPOTHESIS — see `red-team.md` §1 for the full three-way
comparison). Source: `review_analysis.py:1-8`, `_persist_batch_result:216-221`.
Immutable/core — directly implements CLAUDE.md's "no evidence = no factual
claim."

## 2. Fixed pain-point vocabulary (VOC-02)

The exact same enums apply to both LLM-extracted findings (`voc-submit`)
and human/Skill-recorded findings (`voc-add`, `record_human_pain_point`).
Passing anything outside these sets raises `ValueError` — it is never
silently coerced to the nearest valid value.

| Field | Valid values |
|---|---|
| `category` | `product`, `packaging`, `shipping`, `expectation_mismatch`, `misuse`, `isolated` |
| `severity` | `LOW`, `MEDIUM`, `HIGH` |
| `frequency_signal` | `ISOLATED`, `RECURRING`, `DOMINANT` |
| `solvability` | `EASY`, `MODERATE`, `HARD`, `UNKNOWN` |

Source: `review_analysis.py:47-52`, enforced again in
`record_human_pain_point:351-358`.

Interpretation notes for a Skill choosing values, not new rules:
- `category=isolated` is for a pain point that is real but not about the
  product/packaging/shipping/expectations/misuse buckets — it is not a
  dumping ground for "don't know," which belongs in `frequency_signal` or
  `solvability=UNKNOWN` instead.
- `frequency_signal` describes how often you actually saw the same
  complaint across sources, not how severe it felt on one read — do not
  mark something `DOMINANT` from a single thread (see also
  `browser-research-protocol.md`'s SINGLE_ANECDOTE vs REPEATED_PATTERN vs
  STRONG_RECURRING_SIGNAL distinction, the same discipline applied to VOC
  findings).

## 3. Batch chunking (VOC-03)

`chunk_reviews(reviews, batch_size)` splits a review set into sequential
batches; `batch_size <= 0` raises `ValueError`. Batch size comes from
`research_depth.review_batch_size`. `voc-prepare` prints one system+user
prompt per batch — a Skill (or the LLM operator) analyzes each batch and
returns one `ReviewBatchAnalysis` result per batch, in the same order, in
the `voc-submit --file` payload (`{"results": [...]}`).

## 4. Reuse, never re-duplicate (VOC-04)

`prepare_review_batches` reuses reviews already recorded for an ASIN
instead of re-fetching or re-inserting them. Re-running `voc-prepare` on the
same opportunity does not create duplicate evidence rows for reviews already
in the ledger.

## 5. Manual-completion third path — the required real-mode route (VOC-05)

`voc_mark_manual_complete(conn, opportunity_id, confirm_no_findings=False)`:

- Requires state `COMPETITOR_ANALYSIS` (same precondition as
  `voc-submit`).
- **Refuses** (raises `ValueError`, never silently skips) unless:
  - at least one prior `hunt voc-add` finding exists for the opportunity,
    **or**
  - `confirm_no_findings=True` was passed explicitly.
- On success, advances `COMPETITOR_ANALYSIS → VOC_ANALYSIS`, same as
  `voc-submit` would.

**Why this exists:** `voc-submit`/`voc-prepare`'s automated path requires a
`ReviewProvider` capability. No real provider in this project implements
live review-text fetching (`hunt voc-prepare --mode real` always fails).
Without this manual-completion path, **every real-mode opportunity would
deadlock permanently at `COMPETITOR_ANALYSIS`** — unable to reach
`differentiation-prepare`, `redteam-prepare`, or `HUMAN_REVIEW` at all. This
is the only route a real-mode candidate has past `COMPETITOR_ANALYSIS`, and
it is exactly what the `reddit-voc` skill and manual browser-research VOC
findings feed into.

`--confirm-no-findings` must only be passed after a genuine, real search
turned up nothing worth recording — never as a shortcut to skip research.
Passing it without having actually looked is itself a violation of the
"no evidence = no factual claim" principle, applied in reverse (asserting
absence of evidence you never gathered).

Source: `hunt.py:665-727`. Tests
(`tests/integration/test_manual_voc_completion.py`):
`test_without_this_fix_no_findings_and_no_confirmation_is_refused`,
`test_manual_finding_then_complete_unblocks_differentiation`,
`test_confirm_no_findings_also_unblocks_without_fabricating_a_pain_point`,
`test_wrong_state_is_rejected_not_silently_advanced`. Hard rule/immutable.

## 6. Human-recorded pain-point evidence status (VOC-06)

`record_human_pain_point` (what `hunt voc-add` calls) writes evidence with
`source="human_user"`, `source_type=HUMAN_VERIFIED`, `status=FACT`. It
requires the opportunity to have a linked `asin_id`, else raises
`ValueError`. This is a stronger evidence tier than
`EXTERNAL_BROWSER_RESEARCH` (capped at `ESTIMATE` — see
`core-rules.md` rule 5) — only claim `HUMAN_VERIFIED`/`FACT` for something
actually directly observed by the human/Skill doing the recording, not for
a browser-research pack's findings, which route through
`browser-evidence-add` instead and stay capped at `ESTIMATE`.

Source: `review_analysis.py:376-385`.

---

## 7. Rule preservation

| Rule ID | This file's section | Source (Amazon-products file:line) | Test |
|---|---|---|---|
| VOC-01 | 1 | review_analysis.py:1-8, :216-221 | (evidence-anchoring suite in test_review_analysis.py) |
| VOC-02 | 2 | review_analysis.py:47-52, :351-358 | (enum-validation tests in test_review_analysis.py) |
| VOC-03 | 3 | review_analysis.py:60-65 | (chunking tests in test_review_analysis.py) |
| VOC-04 | 4 | review_analysis.py:83-121 | (reuse tests in test_review_analysis.py) |
| VOC-05 | 5 | hunt.py:665-727 | test_without_this_fix_no_findings_and_no_confirmation_is_refused, test_manual_finding_then_complete_unblocks_differentiation, test_confirm_no_findings_also_unblocks_without_fabricating_a_pain_point, test_wrong_state_is_rejected_not_silently_advanced |
| VOC-06 | 6 | review_analysis.py:376-385 | (human pain-point evidence-status tests) |
| VAL-01 | 1 (referenced) | evidence_validator.py:1-76 | (generic-walk validation suite; never repairs/invents evidence_ids) |
