# Supplier Validation & IP/Compliance — Vocabulary and Human-Origination Rules

Canonical reference for the supplier/IP validation layer
(`Amazon-products/src/engine/supplier/validation.py`,
`storage/repositories/supplier_validation.py`, `ranking/gates.py`), verified
against source 2026-08-16. This is the layer behind `hunt supplier-set` /
`hunt supplier-show` — the **only** mechanism in the entire engine that can
move the supplier and IP hard gates off their default `UNKNOWN` state. No
automated pipeline stage, no Skill, and no LLM inference is permitted to set
these values on its own judgment.

---

## 1. Vocabulary whitelists — hard-rejects unrecognized values (SUP-01)

```
VALID_SUPPLIER_STATUSES = {
    "UNKNOWN",
    "MANUAL_SOURCING_REQUIRED",
    "VALIDATED",
    "CONFIRMED_IMPOSSIBLE",
}

VALID_IP_STATUSES = {
    "UNKNOWN",
    "PENDING_HUMAN_LEGAL_REVIEW",
    "CLEARED_BY_HUMAN",
    "CONFIRMED_BLOCKER",
}
```

`set_supplier_validation` raises `ValueError` **immediately** if a supplied
value is not in these exact sets — it never silently coerces an unrecognized
string to `UNKNOWN` or drops it. A Skill must only ever pass one of these
eight literal strings to `hunt supplier-set --supplier-status` /
`--ip-status`; never a synonym, a lowercase variant, or a value invented for
the occasion.

Source: `supplier/validation.py:28-29,55-58`. Tests:
`test_set_supplier_validation_rejects_invalid_supplier_status`,
`test_set_supplier_validation_rejects_invalid_ip_status`. This is a hard,
immutable rule with a cross-module contract: `ranking.gates.
OpportunitySignals` expects these exact literal strings to match — a typo'd
status silently fails to fire (or silently fires) a gate, so exactness here
is a safety property, not a style preference.

---

## 2. Default status is `UNKNOWN` (SUP-02) — and a documented naming mismatch

`SupplierValidationInput.supplier_status` and `.ip_status` both default to
the plain string `"UNKNOWN"`. If `hunt supplier-set` is never called for an
opportunity at all, the gates layer resolves both signals to
`("UNKNOWN", "UNKNOWN")` via `_supplier_signals_for_opportunity` — never a
missing/null value that could be misread as "not yet checked" versus
"checked and found unknown"; both cases are the same literal `UNKNOWN`.

Source: `supplier/validation.py:33,40`; `ranking/scoring.py:101-109`. Tests:
`test_set_supplier_validation_defaults_stay_unknown_when_unspecified`,
`test_rank_run_no_supplier_validation_recorded_stays_unknown_never_rejects`.

**Doc/code naming mismatch (state this once, do not repeat it as if it were
ambiguous)**: the repository's `CLAUDE.md` (line 364) refers to a distinct
sentinel value `SUPPLIER_UNKNOWN` (with an underscore). That literal token
does not exist anywhere in the actual code, schema, or CLI — the real
vocabulary is plain `"UNKNOWN"`, identical to the IP status default. The two
are semantically equivalent (both mean "no supplier assessment has been
recorded yet") but textually different. **A Skill must use the code's
actual vocabulary — plain `UNKNOWN`** — when calling `hunt supplier-set` or
describing status to a human, never the `SUPPLIER_UNKNOWN` token from
CLAUDE.md.

---

## 3. Human-only origination — no pipeline stage infers these (SUP-03)

`ip_status` and `supplier_status` are set **exclusively** through `hunt
supplier-set`. No discovery, validation, economics, competitor-autopsy, VOC,
differentiation, or red-team stage ever derives or infers a value for
either field — the `ranking/scoring.py` docstring states this explicitly:
"no stage in this pipeline may infer these itself." Every record written
this way is persisted at `source_type=HUMAN_VERIFIED`, `status=FACT`.

Source: `supplier/validation.py:1-11,64-75`; `ranking/scoring.py:101-109`.

**This is the single most important rule in this file for a Skill's
behavior**: a Skill must never call `hunt supplier-set` with a status value
it inferred itself from research — not from a Claude Browser finding alone,
not from "the listing looks legitimate," not from general category
knowledge about sourcing difficulty. `hunt supplier-set` may only be called
with:

1. A value a human explicitly told the Skill to record (e.g. "yes, I got a
   quote, mark it VALIDATED"), or
2. A value Claude Browser found in a verifiable primary source (e.g. a
   specific Alibaba supplier listing, a USPTO trademark record) **and** the
   human then explicitly confirmed that finding as accurate before it is
   recorded.

Claude's own research or judgment, by itself, is never sufficient grounds
to call `supplier-set` with `VALIDATED`, `CONFIRMED_IMPOSSIBLE`, or
`CONFIRMED_BLOCKER`. See `skills/supplier-research/SKILL.md` and
`skills/ip-risk/SKILL.md` for the exact workflow this implies.

---

## 4. Upsert storage — one row per opportunity (SUP-04)

`supplier_validations` holds exactly one current row per opportunity,
matching the same upsert pattern as `economics_inputs`
(`references/economics.md` section 10). A second `hunt supplier-set` call
replaces the prior row rather than appending a new one.

Source: same file as SUP-01/03. Test:
`test_set_supplier_validation_upserts_not_duplicates`.

**Skill behavior**: if new information changes a supplier/IP assessment
(e.g. a previously `MANUAL_SOURCING_REQUIRED` candidate now has a confirmed
quote), calling `supplier-set` again with the updated status is the correct
workflow — but make clear to the human that this replaces, not
supplements, the prior recorded assessment.

---

## 5. Unknown opportunity_id raises, never silently creates (SUP-05)

`set_supplier_validation` raises `ValueError` if `get_opportunity` returns
`None` for the given `opportunity_id`. It never silently creates a new
opportunity row to absorb an otherwise-orphaned call.

Source: same file as SUP-01/03. Test:
`test_set_supplier_validation_unknown_opportunity_raises`.

---

## 6. IP hard gate — `CONFIRMED_BLOCKER` only (IP-01)

`_gate_ip_blocker` fires **iff** `ip_status == "CONFIRMED_BLOCKER"` —
literally that string and nothing else. `PENDING_HUMAN_LEGAL_REVIEW`,
`UNKNOWN`, and `CLEARED_BY_HUMAN` never fire this gate, no matter how
concerning the underlying research looks.

Source: `ranking/gates.py:42-48`. Tests:
`test_confirmed_ip_blocker_fails_gate`,
`test_pending_human_legal_review_does_not_fail_gate`. This is a hard gate,
enabled via `config.hard_gates.reject_on_confirmed_ip_blocker` (default
`true`) — the gate can be toggled on/off in config, but the CONFIRMED-only
firing condition itself is immutable code, not configurable. Matches
CLAUDE.md's IP/COMPLIANCE section exactly: "Use PENDING_HUMAN_LEGAL_REVIEW
when meaningful IP/compliance verification is incomplete. Never claim
patent/trademark/design-patent clearance without appropriate evidence."

**Skill behavior**: `skills/ip-risk/SKILL.md` can only ever recommend
`PENDING_HUMAN_LEGAL_REVIEW` as its own conclusion, or flag a genuinely
obvious, undisputed conflict for human/lawyer confirmation of
`CONFIRMED_BLOCKER` — the Skill itself never calls `supplier-set
--ip-status CONFIRMED_BLOCKER` on its own authority (see SUP-03 above and
`skills/ip-risk/SKILL.md`).

---

## 7. Interaction with the hard-gates layer (cross-reference)

See `references/decision-gates.md` GATE-01/GATE-02/GATE-03 for how these
statuses actually flow into `hunt rank`. In summary: only literal
`CONFIRMED_IMPOSSIBLE` (supplier) or `CONFIRMED_BLOCKER` (IP) can reject a
candidate via a hard gate; every other value — including
`MANUAL_SOURCING_REQUIRED` and `PENDING_HUMAN_LEGAL_REVIEW`, which sound
negative in prose — is explicitly non-rejecting. A Skill must never tell a
human "this was rejected because sourcing looked hard" when the actual
status recorded was `MANUAL_SOURCING_REQUIRED` — that status structurally
cannot fire the gate.

---

## Rule preservation

| Rule ID | This file's section | Source (Amazon-products file:line) | Test |
|---|---|---|---|
| SUP-01 | 1 | supplier/validation.py:28-29,55-58 | test_set_supplier_validation_rejects_invalid_supplier_status; test_set_supplier_validation_rejects_invalid_ip_status |
| SUP-02 | 2 | supplier/validation.py:33,40; ranking/scoring.py:101-109 | test_set_supplier_validation_defaults_stay_unknown_when_unspecified; test_rank_run_no_supplier_validation_recorded_stays_unknown_never_rejects |
| SUP-03 | 3 | supplier/validation.py:1-11,64-75; ranking/scoring.py:101-109 (docstring) | (structural rule; enforced by absence of any inferring call site — cross-checked against ranking/scoring.py) |
| SUP-04 | 4 | storage/repositories/supplier_validation.py | test_set_supplier_validation_upserts_not_duplicates |
| SUP-05 | 5 | supplier/validation.py | test_set_supplier_validation_unknown_opportunity_raises |
| IP-01 | 6 | ranking/gates.py:42-48 | test_confirmed_ip_blocker_fails_gate; test_pending_human_legal_review_does_not_fail_gate |
