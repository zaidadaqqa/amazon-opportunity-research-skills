# Differentiation — Moat / Copycat-Resistance Rules

Canonical reference for the deterministic differentiation layer
(`Amazon-products/src/engine/analysis/differentiation.py`,
`llm/prompts/differentiation_v1.md`), verified against source 2026-08-16.
Applies to `hunt differentiation-prepare` / `differentiation-submit`. A
Skill's job is to assemble a `DifferentiationAssessment` grounded in real
evidence_ids and submit it — the engine, not the Skill, decides whether the
claim survives.

---

## 1. Default LOW copycat resistance (DIF-01)

Trivial differentiation — color variants, cosmetic changes, generic
"premium" positioning with nothing concrete behind it — must **not** be
classified as a moat. The default classification is
`LOW_COPYCAT_RESISTANCE` unless the evidence actually supports a stronger
category.

The fixed moat-category vocabulary (do not invent categories outside this
set):

| Moat category |
|---|
| `CAPITAL_MOAT` |
| `COMPLIANCE_MOAT` |
| `MANUFACTURING_MOAT` |
| `SOFTWARE_ECOSYSTEM_MOAT` |
| `BRAND_MOAT` |
| `DESIGN_MOAT` |

This rule is **advisory at the prompt layer** (`differentiation_v1.md:9-18`
instructs the model toward this default) but **hard at the code layer**
(`differentiation.py:55-64` enforces it regardless of what the model
claimed) — see DIF-02.

## 2. Evidence-downgrade rule (DIF-02)

If a moat claim cites **zero** surviving `evidence_ids` (i.e. after
`evidence_validator` strips invalid citations, none remain), the assessment
is forcibly downgraded regardless of what was asserted:

```
moat_categories = []
copycat_resistance = "LOW_COPYCAT_RESISTANCE"
```

This is unconditional — an ungrounded `HIGH` or `MODERATE` claim never
survives, no matter how confidently worded. Downstream, `ranking/scoring.py`
maps copycat resistance to a numeric score used in Pareto ranking:
`{"LOW_COPYCAT_RESISTANCE": 0.0, "MODERATE": 1.0, "HIGH": 2.0}` — so an
ungrounded moat claim cannot inflate a candidate's ranking dimension either.

**Practical implication for the `differentiation` skill:** never write a
moat claim into the assessment JSON without at least one real
`evidence_id` from the Evidence Ledger already backing it (from VOC
findings, competitor autopsy notes, or browser research). The engine will
collapse it to `LOW_COPYCAT_RESISTANCE` anyway — submitting an ungrounded
claim wastes a turn and produces a misleadingly confident intermediate
artifact even though the final persisted result is safe.

Source: `differentiation.py:55-64`.

## 3. LLM-failure handling — never crash, never guess (DIF-03)

If the LLM call fails after retries, the persisted result is:

```json
{"llm_failed": true, "moat_categories": [], "copycat_resistance": "UNKNOWN", "validator_result": "FAILED"}
```

Never a crash, never a fabricated best-guess assessment. `UNKNOWN` is a
legitimate, expected terminal state here — a Skill encountering this must
report it as `UNKNOWN`, not retry-and-paper-over it with its own invented
moat assessment.

Source: `differentiation.py:39-50`.

---

## 4. Rule preservation

| Rule ID | This file's section | Source (Amazon-products file:line) | Test |
|---|---|---|---|
| DIF-01 | 1 | llm/prompts/differentiation_v1.md:9-18 (prompt); differentiation.py:55-64 (code) | test_ungrounded_moat_claim_falls_back_to_low_resistance, test_grounded_moat_claim_is_kept |
| DIF-02 | 2 | differentiation.py:55-64; ranking/scoring.py:69 | test_ungrounded_moat_claim_falls_back_to_low_resistance |
| DIF-03 | 3 | differentiation.py:39-50 | test_llm_failure_returns_unknown_without_crashing |
| VAL-01 | 2 (referenced) | evidence_validator.py:1-76 | (generic-walk validation suite; never repairs/invents evidence_ids) |
