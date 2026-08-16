# Economics — Deterministic Calculator, Stress Tests, and Disclosure Rules

Canonical reference for the deterministic economics layer
(`Amazon-products/src/engine/economics/calculator.py`, `stress_test.py`,
`models.py`, `cli_support.py`), verified against source 2026-08-16. This file
documents what `hunt economics-set` / `hunt economics-show` actually compute
— **a Skill never computes any of these numbers itself.** Every figure a
Skill reports (margin, cash margin, ROI, breakeven, stress-scenario results)
must be copy-through from the JSON/text the CLI printed, never re-derived,
never rounded differently, never estimated "roughly" from memory of this
file. If a number is needed and the CLI hasn't been called yet (or was
called with different inputs), call `hunt economics-set`/`economics-show`
again — do not approximate in the meantime.

---

## 1. Required inputs (ECON-01)

Base margin cannot be computed at all unless **all four** of these are
supplied:

```
REQUIRED_FOR_BASE_MARGIN = (
    "selling_price",
    "unit_cost",
    "referral_fee_pct",
    "fulfillment_fee_per_unit",
)
```

Missing any one of the four → the engine returns `EconomicsStatus.
INSUFFICIENT_DATA` and attempts **no computation at all** (not a partial
result, not a guess). This is a hard-coded Python constant, not a config
value — a Skill cannot change or work around this list.

**Skill behavior**: before calling `hunt economics-set`, ask the human for
whichever of these four fields are missing. Never invent a plausible
`selling_price` or `referral_fee_pct` (e.g. "Amazon referral fees are
usually 15%, so I'll assume 15%") — that is exactly the kind of assumption
this project forbids per `core-rules.md`'s anti-hallucination contract. If
the human genuinely doesn't know a required field yet, report the gap and
stop; do not call `economics-set` with a fabricated placeholder.

Source: `economics/models.py:35-43`, `calculator.py:22-24`.
Tests: `test_economics.py::test_insufficient_data_when_required_fields_missing`,
`test_economics_cli_support.py::test_insufficient_data_status_when_required_fields_missing`.

---

## 2. Optional cost fields — zero-filled but always disclosed (ECON-02)

```
_OPTIONAL_COST_FIELDS = (
    "inbound_shipping_per_unit",
    "prep_per_unit",
    "packaging_per_unit",
    "storage_fee_per_unit_monthly",
    "misc_cost_per_unit",
)
```

Any of these left `None` is treated as `0.0` in the running cost total, but
the field's name is appended to a `fields_treated_as_unknown` list in the
result. This is the one place the engine silently defaults a value — and it
compensates by never letting that default stay silent in the output.

**Skill behavior**: `fields_treated_as_unknown` must be surfaced prominently
in whatever the Skill shows the human — never buried, never omitted, never
paraphrased as "all costs accounted for." See section 8.

Source: `calculator.py:12-18,26-36`.

---

## 3. Margin formula (verbatim) (ECON-03)

```
referral_fee_amount   = selling_price * referral_fee_pct
total_cost_per_unit    = unit_cost + fulfillment_fee_per_unit
                          + referral_fee_amount
                          + sum(optional costs, None -> 0)
gross_margin_per_unit  = selling_price - total_cost_per_unit
gross_margin_pct       = gross_margin_per_unit / selling_price
                          (None if selling_price is 0/falsy)
```

Worked example from the test suite: `selling_price=20, unit_cost=5,
referral_fee_pct=0.15, fulfillment_fee_per_unit=4` →
`total_cost_per_unit=12.0`, `gross_margin_per_unit=8.0`,
`gross_margin_pct=0.4`.

Source: `calculator.py:28-40`. Test: `test_basic_margin_calculation`.
Hard, deterministic rule — no LLM involvement (CLAUDE.md ECONOMICS
requirement). A Skill must never re-derive this arithmetic itself, even to
"sanity check" — the calculator is the single source of truth.

---

## 4. Cash margin, ROI (ECON-04)

```
cash_margin_per_unit = gross_margin_per_unit
if return_rate_pct is not None:
    cash_margin_per_unit -= return_rate_pct * selling_price
else:
    (flagged as unknown, not silently treated as 0 return rate)
if ppc_cost_per_unit is not None:
    cash_margin_per_unit -= ppc_cost_per_unit
else:
    (flagged as unknown, not silently treated as $0 PPC)
cash_margin_pct = cash_margin_per_unit / selling_price
roi_pct = gross_margin_per_unit / unit_cost   (None if unit_cost is falsy)
```

Worked example: gross margin `8.0` on a `$20` selling price, with a `10%`
return rate and `$2` PPC cost per unit → cash margin `4.0`.

Source: `calculator.py:42-57`. Test:
`test_cash_margin_reduced_by_returns_and_ppc`. Hard rule — the engine never
assumes a "typical" return rate or a "typical" ad cost when these are not
supplied; it flags them unknown instead of defaulting to zero (this differs
from the optional-cost-field behavior in section 2, which does default to
zero — do not conflate the two).

---

## 5. Breakeven units (ECON-05)

```
breakeven_units = fixed_launch_cost / cash_margin_per_unit
```

...only computed if **both**:
- `fixed_launch_cost is not None`, and
- `cash_margin_per_unit > 0`.

If `cash_margin_per_unit <= 0` → `breakeven_units = None` (never a negative
or nonsensical number). If `fixed_launch_cost is None` → flagged unknown,
`breakeven_units = None`.

Worked example: `fixed_launch_cost=800, cash_margin_per_unit=8.0` →
`breakeven_units=100.0`.

Source: `calculator.py:59-68`. Tests:
`test_breakeven_units_when_fixed_cost_supplied`,
`test_breakeven_is_none_when_margin_non_positive`.

---

## 6. Rounding (ECON-06)

All monetary results are rounded to 4 decimal places, except
`breakeven_units` which is rounded to 2 decimal places. `None` values are
never rounded (rounding `None` would raise/behave incorrectly, so the engine
explicitly skips it). A Skill must not further round or reformat these
numbers when quoting them — report exactly what the CLI printed.

Source: `calculator.py:70-80`.

---

## 7. Stress-test scenarios — 5 named scenarios, exact multipliers (ECON-07)

Every `hunt economics-set` call also runs 5 stress scenarios automatically.
These multipliers are config-driven (`config/default.yaml`) but ship with
these exact default values — quote them exactly, never round or approximate:

| Scenario | Config key | Multiplier / delta |
|---|---|---|
| PPC increase | `ppc_stress_multiplier` | `1.5` (PPC cost **+50%**) |
| Shipping increase | `shipping_cost_stress_multiplier` | `1.3` (inbound shipping **+30%**) |
| Price drop | `price_drop_stress_pct` | `0.10` (selling price **-10%**) |
| Supplier cost increase | `supplier_cost_increase_stress_pct` | `0.15` (unit cost **+15%**) |
| Return-rate increase | `return_rate_increase_stress_pct_abs` | `0.05` (return rate **+5 percentage points, absolute**, not relative) |

**Never-fabricate-a-stress-base rule**: `ppc_increase`, `shipping_increase`,
`price_drop`, and `supplier_cost_increase` scenarios only run if the
underlying input field (`ppc_cost_per_unit`, `inbound_shipping_per_unit`,
`selling_price`, `unit_cost` respectively) was actually supplied by the
human. The engine never invents a plausible base value just to have
something to stress-test. `return_rate_increase` is the one exception — it
**always** runs; if `return_rate_pct` was never supplied, the scenario
treats the base as `0.0` for that scenario only, and this substitution is
disclosed in the scenario's description text (not silently assumed).

Source: `stress_test.py:14-79`. Tests:
`test_stress_tests_only_run_for_supplied_fields`,
`test_stress_tests_reduce_margin_relative_to_base`.

**Skill behavior**: present all 5 scenarios (or note which ones didn't run
and why — missing input field) exactly as returned. Never invent a 6th
scenario, never skip reporting one that did run, never re-label the return
rate delta as relative (it is a flat +5 point absolute shift, e.g. 10% →
15%, not 10% → 10.5%).

---

## 8. Robustness-under-stress gate — advisory, requires an explicitly configured threshold (ECON-08)

`is_robust_under_stress(base_status, scenarios)` reads
`config.capital.min_acceptable_cash_margin_pct`.

- If that config value is `None` (its tracked default) → the function
  returns `None` (`INSUFFICIENTLY_OBSERVABLE`), **never `False`**. This is
  the "never invents a robustness bar" rule: absent an explicit
  human-configured threshold, the engine refuses to silently manufacture one
  by assuming some default percentage is "obviously acceptable."
- If a threshold **is** configured, the result is `True` only if *every*
  computed scenario's `cash_margin_pct` is `>= min_acceptable_cash_margin_pct`.

Source: `stress_test.py:84-96`. Test:
`test_robustness_is_none_without_configured_threshold`.

**Skill behavior**: if `is_robust_under_stress` comes back `None`/
`INSUFFICIENTLY_OBSERVABLE`, report it exactly that way — never translate an
unconfigured threshold into an implied "yes" or "no." The threshold itself
is user-configurable (via `config/default.yaml`'s `capital:` section), but a
Skill must never configure it on the human's behalf or assume a value on
their behalf.

---

## 9. Evidence tier — `HUMAN_VERIFIED`/`FACT`, never observed-market tier (ECON-09)

`hunt economics-set` → `set_and_evaluate` records an Evidence Ledger row with
`source_type=HUMAN_VERIFIED`, `status=FACT`. This is a deliberately distinct
tier from automated market-data evidence (which caps at `ESTIMATE`) — cost
and price assumptions supplied through this command are being asserted by a
human (or Claude relaying a human-confirmed figure), not observed live from
a marketplace.

- Evidence is only recorded if the opportunity has a linked `asin_id`;
  otherwise `evidence_id=None`, but the economics inputs themselves are
  **still persisted** — never silently dropped just because no ASIN is
  linked yet.
- `set_and_evaluate` raises `ValueError` if the `opportunity_id` doesn't
  exist. It never silently creates a new opportunity row to absorb the call.

Source: `economics/cli_support.py:1-66`. Tests:
`test_set_and_evaluate_records_human_verified_evidence`,
`test_set_and_evaluate_without_asin_skips_evidence_but_still_persists`.

---

## 10. Storage is upsert, not append-only (ECON-10)

`economics_inputs` holds one row per opportunity — a second `hunt
economics-set` call with different values **replaces** the row (verified:
only 1 row exists after two calls; the latest values win). This is different
from the Evidence Ledger row recorded alongside each call, which remains
append-only (the historical evidence entries are preserved even though the
"current inputs" row is overwritten).

Source: `storage/repositories/economics_inputs.py:30-55`,
`schema.sql:333-350`. Test:
`test_set_and_evaluate_persists_across_calls_upsert_not_duplicate`.

**Skill behavior**: if a human wants to revise assumptions (e.g. a supplier
quote changed), simply call `economics-set` again with the new values — this
is the intended workflow, not a special case. But make clear to the human
that the previous inputs are being replaced, not appended alongside the new
ones, when discussing "what changed."

---

## 11. Reports never fabricate economics (ECON-11)

`hunt show` / `hunt report`'s `build_report_data` populates the
`report["economics"]` section **only if** the caller explicitly supplied
`EconomicsInputs` for that opportunity. If `economics-set` was never called,
the report shows `{"status": "NOT_PROVIDED", "note": "..."}` verbatim — not
a blank section, not an inferred estimate.

Source: `reporting/report.py:209-217`. Verified live per
`FINAL_PROJECT_AUDIT.md` ("all three reports show NOT_PROVIDED").

**Skill behavior**: if `hunt show`/`hunt economics-show` reports
`NOT_PROVIDED` (or "none supplied yet"), say exactly that to the human —
never describe a candidate as having "no meaningful economics data" framed
as a negative finding about the product; it is simply a gap in data
collection that `economics-set` would close.

---

## The one rule that supersedes all of the above

**A Skill never computes margin, cash margin, ROI, breakeven, or any stress
scenario itself — in natural language, in a spreadsheet-style aside, or
"as a sanity check."** Every number reported to the human must be a direct,
unmodified readout of what `hunt economics-set` or `hunt economics-show`
actually printed. If the Skill is unsure whether a number is current (e.g.
inputs may have changed since the last call), re-run `hunt economics-show`
rather than guess whether the cached figure is still accurate.

---

## Rule preservation

| Rule ID | This file's section | Source (Amazon-products file:line) | Test |
|---|---|---|---|
| ECON-01 | 1 | economics/models.py:35-43; calculator.py:22-24 | test_insufficient_data_when_required_fields_missing; test_insufficient_data_status_when_required_fields_missing |
| ECON-02 | 2 | calculator.py:12-18,26-36 | (disclosure behavior exercised by test_basic_margin_calculation's fields_treated_as_unknown assertions) |
| ECON-03 | 3 | calculator.py:28-40 | test_basic_margin_calculation |
| ECON-04 | 4 | calculator.py:42-57 | test_cash_margin_reduced_by_returns_and_ppc |
| ECON-05 | 5 | calculator.py:59-68 | test_breakeven_units_when_fixed_cost_supplied; test_breakeven_is_none_when_margin_non_positive |
| ECON-06 | 6 | calculator.py:70-80 | (implicit in numeric assertions across economics tests) |
| ECON-07 | 7 | stress_test.py:14-79 | test_stress_tests_only_run_for_supplied_fields; test_stress_tests_reduce_margin_relative_to_base |
| ECON-08 | 8 | stress_test.py:84-96 | test_robustness_is_none_without_configured_threshold |
| ECON-09 | 9 | economics/cli_support.py:1-66 | test_set_and_evaluate_records_human_verified_evidence; test_set_and_evaluate_without_asin_skips_evidence_but_still_persists |
| ECON-10 | 10 | storage/repositories/economics_inputs.py:30-55; schema.sql:333-350 | test_set_and_evaluate_persists_across_calls_upsert_not_duplicate |
| ECON-11 | 11 | reporting/report.py:209-217 | FINAL_PROJECT_AUDIT.md (live-verified); no unit test found in inventory — flagged as doc-verified only |
