# Example Research Workflow

This is a real, executed transcript (`--mode mock`, run 2026-08-16) of the full
canonical flow from `SKILL.md`, run directly through the CLI to prove the flow
is walkable end-to-end (see `tests/parity/end_to_end_mock_workflow.sh`, which
you can re-run yourself). Fixture-tagged text below is clearly marked — this
is a demonstration of mechanics, not a real research finding.

## 1. Demand intelligence — generate the Trends request

```
$ hunt demand-request "silicone stretch lids" --compare "reusable food wrap" --geo US --timeframe "today 12-m"

GOOGLE TRENDS DATA REQUEST

Concept:      silicone stretch lids
Primary:      silicone stretch lids
Compare:      reusable food wrap
Geo:          US
Time:         today 12-m
Search:       WEB_SEARCH

Required exports:
    1. Interest over time
    2. Related queries
    3. Rising queries

STEP 1: Go to trends.google.com, search the Primary term (add Compare terms
if listed) with the Geo/Time/Search settings above.
STEP 2: Download the CSV for each required export.
STEP 3: Run `hunt demand-set "silicone stretch lids" --csv
<interest-over-time.csv> --related-csv <related-queries.csv> --geo US
--timeframe "today 12-m" --search-type WEB_SEARCH`
```

A Skill hands this exact text to the human, waits for the CSV files, then
calls `hunt demand-set` with the real paths. (Skipped in this demo run —
`amazon-discovery` doesn't require a recorded demand signal; `demand-rank`
is only a prioritization hint.)

## 2. Amazon discovery

```
$ hunt discover "silicone stretch lids" --category Home_and_Kitchen --mode mock

Scanned: 3  Discovered: 3  Rejected (cheap filters): 0  Rejected (no ASIN): 0
Rejected (duplicate): 0  (run run_9ea47da5ef7a4cb29dfdf22737271fb2)
Discovery stop reason: SOURCE_EXHAUSTED  (batches attempted=1 succeeded=1 failed=0)
Relevance: 3 relevant, 0 ambiguous, 0 unresolved-title, 0 rejected as irrelevant
Next: `hunt deepen-start run_9ea47da5ef7a4cb29dfdf22737271fb2` to continue.
```

Three candidates survived cheap filtering and relevance classification —
all deterministic, all happened inside the CLI call, nothing Claude judged.

## 3. Interim ranking check

```
$ hunt rank run_9ea47da5ef7a4cb29dfdf22737271fb2
Total: 3  Ranked (PROMISING): 3  Gate-rejected: 0  Insufficient evidence: 0
```

All three currently show `evidence_confidence: 0.3` only (researchability
`INSUFFICIENTLY_OBSERVABLE` — no live market data was fetched in this
discovery-only demo). `PROMISING` here is a gate-pass technicality, not a
verdict — see `references/decision-framework.md`.

## 4. Competitor autopsy

```
$ hunt deepen-start run_9ea47da5ef7a4cb29dfdf22737271fb2 --mode mock
{"opportunity_ids": ["opp_b634d741...", "opp_6e0a68a8...", "opp_e2f03bae..."], ...}
```

All three advance `ECONOMICS_CHECK → COMPETITOR_ANALYSIS`.

## 5. VOC — the Browser Edition path (manual/browser-sourced findings)

```
$ hunt voc-add opp_b634d741... \
    --category product --description "[FIXTURE] customers report the lids losing their seal after repeated washing" \
    --severity MEDIUM --frequency-signal RECURRING --solvability MODERATE \
    --source-note "[FIXTURE] parity-test fixture, not a real finding"

[HUMAN_VERIFIED VOC finding]

$ hunt voc-manual-complete opp_b634d741...
[VOC_ANALYSIS reached via manual human review]
```

This is exactly what `skills/reddit-voc/SKILL.md` and
`skills/browser-research/SKILL.md` do with real findings — one `voc-add` call
per real, sourced complaint, then `voc-manual-complete` once done (or
`--confirm-no-findings` if genuinely nothing was found after real search).
The mock ASIN in this demo already carried 4 fixture pain points from the
mock data provider itself; the 5th is the one this workflow added.

## 6. Differentiation

```
$ hunt differentiation-prepare opp_b634d741...
```
prints a system+user prompt built from the actual evidence on file (5 real
pain points cited by `evidence_id`, competitor concentration: `review_concentration=HIGH,
brand_concentration=MODERATE, oos_frequency=MODERATE`). Claude analyzes and
submits a `DifferentiationAssessment`:

```json
{"moat_categories": [], "copycat_resistance": "LOW_COPYCAT_RESISTANCE",
 "reasoning": [{"statement": "[FIXTURE] no grounded evidence for a stronger moat claim was supplied.",
                "evidence_ids": [], "confidence_status": "UNKNOWN"}]}
```
```
$ hunt differentiation-submit opp_b634d741... --file assessment.json
```
advances `VOC_ANALYSIS → DIFFERENTIATION_ANALYSIS`.

## 7. Red team

```
$ hunt redteam-prepare opp_b634d741...
```
prints the adversarial-analysis prompt. Claude submits:
```json
{"findings": [{"category": "commoditization",
  "statement": "[FIXTURE] silicone lids are a commoditized category with many existing sellers.",
  "label": "HYPOTHESIS", "evidence_ids": []}]}
```
```
$ hunt redteam-submit opp_b634d741... --file findings.json
{"findings_persisted": 1, "llm_failed": false, "validator_passed": true}
```
advances `DIFFERENTIATION_ANALYSIS → RED_TEAM → HUMAN_REVIEW`.

## 8. Economics

```
$ hunt economics-set opp_b634d741... --selling-price 14.99 --unit-cost 3.20 \
    --referral-fee-pct 0.15 --fulfillment-fee-per-unit 4.10 \
    --return-rate-pct 0.04 --ppc-cost-per-unit 0.90

Revenue/unit: 14.99  Total cost/unit: 9.5485  Gross margin/unit: 5.4415 (0.363)
Cash margin/unit: 3.9419 (0.263)  ROI: 1.7005  Breakeven units: None
Treated as UNKNOWN (not supplied, not assumed): [fixed_launch_cost,
  inbound_shipping_per_unit, misc_cost_per_unit, packaging_per_unit,
  prep_per_unit, storage_fee_per_unit_monthly]

  [stress: ppc_increase]           cash_margin_pct=0.2329
  [stress: price_drop]             cash_margin_pct=0.2022
  [stress: supplier_cost_increase] cash_margin_pct=0.2309
  [stress: return_rate_increase]   cash_margin_pct=0.213
```

Every number here came from the real deterministic calculator — Claude never
computed a margin. Note `breakeven_units: None` — `fixed_launch_cost` was
never supplied, so it correctly stays unknown rather than a guessed number.

## 9. Supplier / IP

```
$ hunt supplier-set opp_b634d741... --supplier-status MANUAL_SOURCING_REQUIRED --ip-status PENDING_HUMAN_LEGAL_REVIEW
[HUMAN_VERIFIED supplier/IP assessment]
```
Neither hard gate can fire from this state — only `CONFIRMED_IMPOSSIBLE` /
`CONFIRMED_BLOCKER` would, and only a human sets those.

## 10. Final ranking + decision

```
$ hunt rank run_9ea47da5ef7a4cb29dfdf22737271fb2
opp_b634d741...  frontier 2  {evidence_confidence: 0.3, differentiation: 0.0,
                               red_team_clean: 0.0, pain_point_score: -11.0}
```

`hunt show opp_b634d741...` confirms `final_status` is **not** `QUALIFIED` at
this point — it can only be `PROMISING`/`REJECTED`/`NEEDS_MORE_DATA` until a
human acts. The Skill's `final-decision` stage compiles this full report and
stops here, handing the decision to the human:

```
$ hunt decide opp_b634d741... approve --reason "[FIXTURE] parity-test fixture approval"
opp_b634d741... -> QUALIFIED
```

Only this explicit human command moves the state to `QUALIFIED`. No Skill in
this package ever runs `hunt decide` on its own.
