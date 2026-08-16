---
name: economics
description: Use once a candidate reaches ECONOMICS_CHECK or later to gather cost/price assumptions (from the human or verifiable browser-observed supplier/marketplace data) and run them through the engine's deterministic economics calculator and stress tests. Never compute margin/ROI/breakeven yourself.
---

# Economics

Gathers the cost/price assumptions needed to evaluate a candidate's unit
economics, then hands them to `hunt economics-set`, which runs the real,
tested `engine.economics.calculator`/`stress_test` code. **This Skill never
performs the margin/cash-margin/ROI/breakeven arithmetic itself, in any
form** — not as a rough estimate, not as a sanity check, not as a preview
before calling the CLI. Every number reported to the human is a direct
readout of what `economics-set`/`economics-show` returned. Full formulas,
thresholds, and edge-case rules live in `references/economics.md` — read it
before using this Skill if any of the below is unclear.

## When to use this

Any time from `ECONOMICS_CHECK` state onward, whenever cost/price
assumptions are available or need to be gathered. Can be re-run any time
assumptions change (e.g. a supplier quote updates) — `economics-set` is an
upsert, not append-only (`references/economics.md` ECON-10).

## Step 1 — Check what's already recorded

Before asking the human anything, run:

```
hunt economics-show <opportunity_id>
```

If this shows `NOT_PROVIDED` / "none supplied yet," nothing is recorded.
If it shows a prior result, decide with the human whether it's still
current before re-collecting inputs (see `time-budget-controller.md` Rule
2 — don't re-ask for information already on file without reason).

## Step 2 — Gather the required inputs

Four fields are **required** for any result at all (ECON-01):

- `selling_price`
- `unit_cost`
- `referral_fee_pct`
- `fulfillment_fee_per_unit`

If any of these is missing, **ask the human for it directly** — do not
infer, estimate, or default it. In particular, do not assume "referral fees
are usually 15%" or a "typical" fulfillment fee; those are exactly the
kind of plausible-sounding fabrication this project forbids
(`core-rules.md`'s anti-hallucination contract: "Assumption → Margin
figure" is a forbidden conversion). If the human doesn't know a required
field yet, say so plainly and stop — do not call `economics-set` with a
guess in its place.

Optionally gather (these default to `0` in the total but are disclosed, see
Step 4): `inbound_shipping_per_unit`, `prep_per_unit`, `packaging_per_unit`,
`storage_fee_per_unit_monthly`, `misc_cost_per_unit`. Also optionally:
`return_rate_pct`, `ppc_cost_per_unit` (needed for cash margin/ROI, treated
as "unknown," not zero, if omitted — ECON-04), and `fixed_launch_cost`
(needed for breakeven — ECON-05).

Inputs can come from the human directly, or from a verifiable
browser-observed source (e.g. an actual current Amazon listing price, or a
supplier quote a human has confirmed) — but any browser-observed figure
still needs to be relayed to and confirmed by the human before being
treated as a real input, consistent with how this evidence tier is treated
elsewhere in this system.

## Step 3 — Call `hunt economics-set`

```
hunt economics-set <opportunity_id> \
  --selling-price <value> \
  --unit-cost <value> \
  --referral-fee-pct <value> \
  --fulfillment-fee-per-unit <value> \
  [--inbound-shipping-per-unit <value>] \
  [--prep-per-unit <value>] \
  [--packaging-per-unit <value>] \
  [--storage-fee-per-unit-monthly <value>] \
  [--misc-cost-per-unit <value>] \
  [--return-rate-pct <value>] \
  [--ppc-cost-per-unit <value>] \
  [--fixed-launch-cost <value>]
```

A `--file <path>` JSON file can be used instead of/alongside flags;
individual flags win over file contents on conflict (`CLI-09`). This
persists the inputs as `HUMAN_VERIFIED`/`FACT` evidence (ECON-09) and
immediately computes and prints the base case plus all 5 stress scenarios.

## Step 4 — Read and present the result exactly as returned

Present, verbatim, without re-deriving or re-rounding any of it:

- **Base case**: `total_cost_per_unit`, `gross_margin_per_unit`,
  `gross_margin_pct`, `cash_margin_per_unit`, `cash_margin_pct`, `roi_pct`,
  `breakeven_units` (or explain why any of these is `None` — e.g.
  `unit_cost` was 0 so `roi_pct` is `None`, or `cash_margin_per_unit <= 0`
  so `breakeven_units` is `None` — per ECON-05).
- **`fields_treated_as_unknown`**: present this list prominently and
  explicitly — it names every optional cost field that was left blank and
  silently treated as `$0` in the total. Never bury this list or omit it;
  a human reading only the margin number without this list would believe
  all costs were accounted for when they weren't.
- **All 5 stress scenarios** (PPC +50%, shipping +30%, price -10%, supplier
  cost +15%, return rate +5 points absolute — see `references/economics.md`
  section 7 for exact config keys), or note which ones didn't run because
  their underlying input field was never supplied.
- **Robustness-under-stress**, if requested: report `None`/
  `INSUFFICIENTLY_OBSERVABLE` exactly as returned when no
  `min_acceptable_cash_margin_pct` threshold is configured — never imply a
  pass or fail in that case (ECON-08).

If `hunt economics-show`/`hunt show` reports `NOT_PROVIDED`, report that
plainly — it is a data gap, not a negative finding about the product
(ECON-11).

## What this Skill must never do

- Never compute margin, cash margin, ROI, breakeven, or a stress scenario
  itself in prose, even as a rough approximation "to save a round trip."
- Never fabricate a required field to get a result — `INSUFFICIENT_DATA`
  is the correct outcome when inputs are genuinely missing.
- Never silently treat an optional cost field's `$0` default as "no cost" —
  always surface `fields_treated_as_unknown`.
- Never invent a robustness threshold on the human's behalf.

See `references/economics.md` for the full formula set, the exact stress
multipliers, and the complete rule-preservation table tracing every claim
in this Skill back to source code and tests.
