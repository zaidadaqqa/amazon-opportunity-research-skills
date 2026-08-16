# Decision Gates, State Machine, and Pareto Ranking — Exact Rules

Canonical reference for `Amazon-products/src/engine/ranking/gates.py`,
`ranking/rank.py`, `ranking/scoring.py`, and `state_machine/states.py` +
`machine.py`, verified against source 2026-08-16. **This is the most
safety-critical reference file in this package.** Every number, enum
member, and formula below must be quoted exactly — do not paraphrase a
threshold, do not round a weight, do not reorder the state list. If this
file and a Skill's own prose ever disagree, this file (and the underlying
code it describes) wins.

---

## Part 1 — Hard gates (`ranking/gates.py`)

### GATE-01 — Critical invariant: gates fire ONLY on `CONFIRMED_*` findings

All three hard gates check for a **literal** `CONFIRMED_*` string. Nothing
else fires them:

| Gate | Fires only on |
|---|---|
| Lineage/contamination gate | `CONFIRMED_CONTAMINATION` |
| Supplier gate | `CONFIRMED_IMPOSSIBLE` |
| IP gate | `CONFIRMED_BLOCKER` |

`UNKNOWN`, `SUSPECTED_CONTAMINATION`, `PENDING_HUMAN_LEGAL_REVIEW`, and
`MANUAL_SOURCING_REQUIRED` **never** fire any gate, regardless of how
concerning they sound in a report. The module docstring calls this a
"CRITICAL INVARIANT, enforced by tests."

Source: `ranking/gates.py:1-13,33-58`. Tests:
`test_unknown_never_triggers_a_gate`,
`test_suspected_contamination_does_not_fail_gate`,
`test_pending_human_legal_review_does_not_fail_gate`; integration:
`test_rank_run_never_fires_gate_on_unknown_or_suspected`,
`test_rank_run_never_fires_supplier_gate_on_manual_sourcing_required`.
Immutable, core safety rule — see also `core-rules.md` rule #1.

**Skill behavior**: never tell a human "this candidate was rejected because
of suspected contamination" or "because IP review is pending" — those
statuses structurally cannot cause a rejection. If `hunt rank` shows
`REJECTED`, the actual fired gate reason (from `hunt show`) must be quoted,
and it will always trace back to one of the three literal `CONFIRMED_*`
values above, or a config-enabled gate outside this list.

### GATE-02 — Gate enable/disable is config-driven and auditable

`evaluate_gates` only evaluates (and returns a result entry for) a given
gate if `config.hard_gates.<name>` is truthy. A disabled gate produces **no
result entry at all** — not a silently-passing `True` result — so the
returned list itself is a complete, auditable record of which gates ran.
All three gates default to `true` in `config/default.yaml`.

Source: `ranking/gates.py:67-75`. Test:
`test_evaluate_gates_returns_one_result_per_enabled_gate`.

**Skill behavior**: if presenting gate results to a human, note which gates
actually ran (present in the result list) versus were disabled (absent) —
do not assume all three always ran.

### GATE-03 — `passes_all_gates` = AND of all enabled gate results

A candidate passes overall only if every gate that actually ran (per
GATE-02) passed. One fired gate is enough to fail the candidate regardless
of how many other gates passed.

Source: `ranking/gates.py:78-79`.

---

## Part 2 — State machine (`state_machine/states.py`, `machine.py`)

### SM-01 — 16-state enum, fixed vocabulary (verbatim)

```
DISCOVERED
PRE_FILTERED
DATA_PENDING
VALIDATING
ECONOMICS_CHECK
COMPETITOR_ANALYSIS
VOC_ANALYSIS
DIFFERENTIATION_ANALYSIS
RED_TEAM
HUMAN_REVIEW
QUALIFIED
REJECTED
INSUFFICIENTLY_OBSERVABLE
PENDING_HUMAN_REVIEW
STALE
REOPENED
```

Source: `states.py:11-27`. Test: every enum member has a
transition-table entry (no orphan states). A Skill must never reference a
state name outside this exact list of 16.

### SM-02 — Terminal states

`{QUALIFIED, REJECTED}` — and only these two. Once in a terminal state, an
opportunity does not naturally continue through further research.

### SM-03 — Paused states

`{INSUFFICIENTLY_OBSERVABLE, PENDING_HUMAN_REVIEW, STALE}` — these can
return to active research; they are not terminal, just parked.

### SM-04 — Happy-path linear chain (verbatim order)

```
DISCOVERED
  -> PRE_FILTERED
  -> DATA_PENDING
  -> VALIDATING
  -> ECONOMICS_CHECK
  -> COMPETITOR_ANALYSIS
  -> VOC_ANALYSIS
  -> DIFFERENTIATION_ANALYSIS
  -> RED_TEAM
  -> HUMAN_REVIEW
  -> QUALIFIED   (only reachable from HUMAN_REVIEW)
```

Source: `states.py:46-57,73-78`. Tests: `test_happy_path_is_fully_walkable`,
`test_cannot_skip_stages`. This transition table is the **sole source of
truth** for which moves are legal — no Skill, prompt, or CLI flag can skip
a stage in this chain (this is exactly why `cli-command-reference.md`'s
precondition table exists: every `-prepare`/`-submit`/`-start` command
enforces its own required starting state and raises `ValueError` if the
opportunity isn't there yet).

### SM-05 — Divert-to-paused-or-rejected, from any linear-path state or `HUMAN_REVIEW`

Every state on the linear-path chain above, plus `HUMAN_REVIEW` itself, may
transition directly to any of `{REJECTED, INSUFFICIENTLY_OBSERVABLE,
PENDING_HUMAN_REVIEW}` at any point — "a bad candidate should die at the
earliest stage that reveals the problem," per the state machine's design
principle. A Skill should not assume a candidate must reach `HUMAN_REVIEW`
before it can be rejected or paused.

### SM-06 — Divert-to-`STALE`, from any linear-path state

Every linear-path state may also transition to `STALE` (evidence expired
before the candidate finished the pipeline).

### SM-07 — Paused states re-enter only via `REOPENED` or close via `REJECTED`

From any of the three paused states, the only legal transitions are to
`{REOPENED, REJECTED}` — **never directly to `QUALIFIED`.** A paused
candidate cannot be "waved through" to qualification; it must first be
reopened and pass back through fresh research.

Test: `test_paused_states_can_reopen_or_close`.

### SM-08 — `REOPENED` re-entry is restricted to fresh-data states

From `REOPENED`, the only legal next states are `{DATA_PENDING, REJECTED,
INSUFFICIENTLY_OBSERVABLE}` — "fresh data required before re-judging." A
reopened candidate cannot jump straight back to, say, `HUMAN_REVIEW` on
stale evidence.

Test: `test_reopened_requires_fresh_data_pending`.

### SM-09 — Terminal states exit only via `REOPENED`

From `QUALIFIED` or `REJECTED`, the only legal transition is to `REOPENED`.
This implements CLAUDE.md's rule that "a previously rejected product may be
reconsidered only when relevant market/data conditions change" — reopening
is always an explicit, deliberate action, never automatic.

Test: `test_cannot_leave_terminal_state_except_reopen`.

### SM-10 — Illegal transitions never persist

`advance()` validates the requested transition against the table **before**
calling the persistence callback. An illegal transition raises and the
persist callback is never invoked — verified by a test asserting
`calls == []` and the state left unchanged after a rejected illegal
transition attempt.

Test: `test_state_machine_wrapper_rejects_illegal_transition_without_persisting`.
No partial or corrupted writes can occur from a failed transition attempt.

### SM-11 — Atomic persistence, `state_transitions` + `opportunities.state` never drift apart

`record_state_transition` writes a `state_transitions` row and updates
`opportunities.state` in the same operation, with rollback on exception —
these two representations of "current state" must never be able to
disagree with each other.

---

## Part 3 — Pareto ranking (`ranking/rank.py`, `ranking/scoring.py`)

### RANK-01 — Never a single blended score; strict Pareto dominance

`_dominates(a, b)`: candidate `a` dominates candidate `b` if and only if,
on every dimension both candidates share, `a` is `>=` `b`, **and** `a` is
strictly `>` `b` on at least one shared dimension. If `a` and `b` share no
measured dimensions at all, `a` never dominates `b` (dominance requires at
least one real comparison, not a vacuous win). `pareto_frontiers` repeatedly
peels off the non-dominated set into successive tiers (frontier `1` =
best-ranked tier).

Source: `ranking/rank.py:23-56`. This is an immutable, core architectural
rule matching CLAUDE.md's explicit instruction: "do not hide fatal risks
inside one weighted score." **A Skill must never collapse the four
dimensions below into a single number of its own construction** (e.g. "I'll
average the four scores to get an overall rating out of 10") — that is
exactly the anti-pattern this architecture exists to prevent.

### RANK-02 — Missing dimension is omitted, never zero-filled

A dimension that has not yet been computed for a candidate (e.g. red-team
hasn't run yet) is **entirely omitted** from that candidate's dimension set
— it is never set to `0` or any "worst possible" placeholder value.
`_dominates` only compares dimensions both candidates actually have.

Source: `rank.py:23-33`, `scoring.py:30-33,164-226`. Tests:
`test_dimensions_empty_when_no_stage_has_run`,
`test_differentiation_dimension_omitted_until_stage_runs`. Immutable.

**Skill behavior**: never describe a candidate with an unrun stage as
"scoring 0 on differentiation" — say "differentiation not yet assessed"
instead. Zero-filling would make an under-researched candidate look
artificially worse (or, in dimensions where lower is better, artificially
better) than one that was actually evaluated.

### RANK-03 — Four ranking dimensions, exact formulas

**1. `evidence_confidence`**
- `1.0` if researchability is `OBSERVABLE`.
- `0.3` if researchability is `INSUFFICIENTLY_OBSERVABLE`.
- Omitted entirely otherwise (not `0.0`).
- This value can be **downgraded only, never upgraded**, by the latest
  current-market evidence status:
  - `CONTRADICTED` -> `min(current_value, 0.05)`
  - `STALE` -> `min(current_value, 0.1)`
- A known, disclosed limitation: this STALE/CONTRADICTED downgrade does not
  yet independently gate the Pareto frontier on its own (documented as a
  deferred gap in `FINAL_PROJECT_REPORT.md §7`) — carry this forward as a
  known limitation, not a silent assumption that staleness is fully
  enforced everywhere.

**2. `differentiation`**
```
_COPYCAT_SCORE = {
    "LOW_COPYCAT_RESISTANCE": 0.0,
    "MODERATE": 1.0,
    "HIGH": 2.0,
}
```
Taken from the latest `differentiation_analysis` record's copycat-resistance
classification. Omitted entirely if the differentiation stage has never
run for this candidate (see RANK-02).

**3. `red_team_clean`**
`-count(EVIDENCED red_team_findings)` — a negative count, so more
`EVIDENCED` findings (not `HYPOTHESIS`-tier findings) make the dimension
more negative, i.e. worse. `HYPOTHESIS`-tier findings do not count against
this dimension at all. Omitted entirely if red-team has never run.

**4. `pain_point_score`**
`-sum(_SEVERITY_WEIGHT[severity] for each pain point)`, where:
```
_SEVERITY_WEIGHT = {"HIGH": 3, "MEDIUM": 2, "LOW": 1}
```
A negative, severity-weighted sum — more/more-severe pain points make this
dimension more negative, i.e. worse. This dimension is included whenever
either the automated `review_analysis` stage has run, **or** any pain point
exists at all (including one added manually via `hunt voc-add`, which is
the mechanism the `reddit-voc` and `browser-research` Skills use) — it is
not gated solely on the automated VOC skill having run.

Source: `ranking/scoring.py:68-69,164-226`. Multiple exact-value tests pin
specific numeric outputs (e.g. `0.1`/`0.05` for the confidence downgrades,
`-4.0`/`-3.0`/`0.0` for pain-point/red-team sums) — treat these as
regression-tested constants, not approximations.

**Skill behavior**: when presenting a candidate's standing, list which of
the four dimensions are present versus omitted, and quote each present
dimension's actual numeric value and what produced it (e.g. "differentiation
= 1.0, from a MODERATE copycat-resistance rating"). Never invent a 5th
dimension, never re-weight these four against each other.

### RANK-04 — `rank_run` never sets `QUALIFIED`

`rank_run` processes every non-terminal opportunity in a run as follows:

1. Skip opportunities already in a terminal state.
2. Evaluate hard gates first. If any enabled gate fails -> `final_status =
   REJECTED`, reason recorded as `GATE_REJECTED`.
3. If gates pass but the candidate has **zero** computed ranking dimensions
   -> `final_status = NEEDS_MORE_DATA`, reason `INSUFFICIENT_EVIDENCE`,
   excluded from the Pareto frontier computation entirely.
4. Otherwise -> Pareto-ranked -> `final_status = PROMISING`, reason
   `RANKED`.

`rank_run` can only ever produce `REJECTED`, `NEEDS_MORE_DATA`, or
`PROMISING` — it structurally cannot produce `QUALIFIED`.

Source: `scoring.py:259-350`. Test:
`test_rank_run_qualified_candidate_reaches_promising_never_qualified`.
Immutable — this is the code-level enforcement of the human-in-the-loop
guarantee described further in `decision-framework.md`.

### RANK-05 — `rank_run` never silently drops candidates from a large run

`rank_run` uses `list_opportunities_for_run` (no row cap), specifically to
avoid `list_opportunities`'s default `limit=1000`, which would silently
truncate ranking for a very large run. This was a fixed real defect, not a
theoretical concern.

### RANK-06 — Deterministic, reproducible ordering

Within a frontier tier, candidates are sorted by `(frontier, candidate_id)`
— re-running `hunt rank` against unchanged evidence always produces the
same ordering. Test: `test_rank_run_deterministic_ordering`.

---

## Rule preservation

| Rule ID | This file's section | Source (Amazon-products file:line) | Test |
|---|---|---|---|
| GATE-01 | Part 1 | ranking/gates.py:1-13,33-58 | test_unknown_never_triggers_a_gate; test_suspected_contamination_does_not_fail_gate; test_pending_human_legal_review_does_not_fail_gate; test_rank_run_never_fires_gate_on_unknown_or_suspected; test_rank_run_never_fires_supplier_gate_on_manual_sourcing_required |
| GATE-02 | Part 1 | ranking/gates.py:67-75 | test_evaluate_gates_returns_one_result_per_enabled_gate |
| GATE-03 | Part 1 | ranking/gates.py:78-79 | (structural — exercised via test_evaluate_gates_returns_one_result_per_enabled_gate and integration rank tests) |
| SM-01 | Part 2 | state_machine/states.py:11-27 | (enum-completeness test: every member has a transition-table entry) |
| SM-02 | Part 2 | states.py | (implicit in terminal-state tests below) |
| SM-03 | Part 2 | states.py | (implicit in test_paused_states_can_reopen_or_close) |
| SM-04 | Part 2 | states.py:46-57,73-78 | test_happy_path_is_fully_walkable; test_cannot_skip_stages |
| SM-05 | Part 2 | states.py | (transition-table coverage tests) |
| SM-06 | Part 2 | states.py | (transition-table coverage tests) |
| SM-07 | Part 2 | states.py | test_paused_states_can_reopen_or_close |
| SM-08 | Part 2 | states.py | test_reopened_requires_fresh_data_pending |
| SM-09 | Part 2 | states.py | test_cannot_leave_terminal_state_except_reopen |
| SM-10 | Part 2 | machine.py | test_state_machine_wrapper_rejects_illegal_transition_without_persisting |
| SM-11 | Part 2 | machine.py (record_state_transition) | (atomicity/rollback behavior — see storage repositories tests) |
| RANK-01 | Part 3 | ranking/rank.py:23-56 | (dominance logic tests within rank.py test suite) |
| RANK-02 | Part 3 | rank.py:23-33; scoring.py:30-33,164-226 | test_dimensions_empty_when_no_stage_has_run; test_differentiation_dimension_omitted_until_stage_runs |
| RANK-03 | Part 3 | scoring.py:68-69,164-226 | exact-value tests for evidence_confidence (0.1/0.05 downgrades), differentiation (_COPYCAT_SCORE mapping), red_team_clean, pain_point_score sums |
| RANK-04 | Part 3 | scoring.py:259-350 | test_rank_run_qualified_candidate_reaches_promising_never_qualified |
| RANK-05 | Part 3 | scoring.py (list_opportunities_for_run usage) | (fixed-defect regression test for large-run candidate coverage) |
| RANK-06 | Part 3 | scoring.py | test_rank_run_deterministic_ordering |
