# Decision Framework — What `PROMISING`/`REJECTED`/`NEEDS_MORE_DATA`/`QUALIFIED` Actually Mean

This file is a synthesis and explainer, not a rule table — it exists to
stop a Skill from over-interpreting `hunt rank`'s output. The exact rule
IDs behind everything stated here live in `references/decision-gates.md`
(`GATE-01` through `GATE-03`, `RANK-01` through `RANK-06`, `SM-01` through
`SM-11`); this file explains how those rules combine into the four
final-status values a human actually sees, and what a Skill's role is with
respect to each one.

---

## The four possible final statuses

### `REJECTED`

Reached one of two ways:

1. **A hard gate fired** — `hunt rank` found a literal `CONFIRMED_*`
   finding (`CONFIRMED_CONTAMINATION`, `CONFIRMED_IMPOSSIBLE`, or
   `CONFIRMED_BLOCKER`) on an enabled gate. This is `RANK-04` step 2 /
   `GATE-01` from `decision-gates.md`. This is an automated, deterministic
   rejection — no human judgment call was involved, and none is needed to
   trust it, because the gate can only fire on a `CONFIRMED_*` value that
   was itself only ever set by a human (`SUP-03` in `supplier-ip.md`).
2. **A human explicitly rejected it** via `hunt decide <opportunity_id>
   reject --reason ...` (`CLI-01`). This is the only human-driven path to
   `REJECTED`, and it always records a `decisions` row with
   `decided_by="human"`.

Both paths land on the same `REJECTED` state/status, but a Skill should
always be able to say *which* of the two actually happened when reporting
to a human — "rejected by the automated gate because of a confirmed IP
blocker" reads very differently from "rejected by you on [date] for
[reason]," and conflating them would misrepresent whose decision it was.

### `NEEDS_MORE_DATA`

Reached when hard gates **passed** but the candidate has **zero** computed
ranking dimensions yet (`RANK-04` step 3) — i.e. none of evidence
confidence, differentiation, red-team cleanliness, or pain-point severity
has been assessed at all. This is explicitly **not a rejection** and not a
negative finding about the product. It means the pipeline hasn't gathered
enough evidence to place the candidate on the Pareto frontier at all — the
correct response is to continue research (deepen-start, VOC, differentiation,
red-team, or whichever stage is missing), not to treat this as a soft
"no."

**Skill behavior**: never describe `NEEDS_MORE_DATA` to a human as "this
candidate looks weak." Say plainly that gates passed and more evidence is
needed before any ranking can happen, and identify which stage(s) haven't
run yet (cross-reference `cli-command-reference.md`'s precondition table).

### `PROMISING`

Reached when hard gates passed **and** the candidate has at least one
computed ranking dimension, so it was placed into a Pareto frontier tier
(`RANK-04` step 4). Per `CLAUDE_PROJECT_OPERATING_SPEC.md` and this
package's `core-rules.md`, `PROMISING` is **a gate-pass technicality, not a
business verdict.** It means: "no hard gate rejected this, and it has been
compared against other candidates on whichever dimensions have been
measured so far." It does **not** mean:

- the economics are good (economics may still be `NOT_PROVIDED` — see
  `references/economics.md` ECON-11),
- the supplier is validated (may still be plain `UNKNOWN` — see
  `references/supplier-ip.md` SUP-02),
- red-team found nothing concerning (red-team may not have run at all — a
  missing dimension is omitted, not assumed clean, per RANK-02),
- a human has looked at it at all.

A candidate can be `PROMISING` with almost no evidence collected, simply
because nothing has rejected it yet and one dimension happened to compute.
**A Skill must never present `PROMISING` as equivalent to "this is a good
opportunity"** — it must always be paired with an explicit statement of
which dimensions were actually measured (see RANK-03 in
`decision-gates.md`) and which stages remain outstanding.

### `QUALIFIED`

Reached **only** via `hunt decide <opportunity_id> approve --reason ...`,
run by an actual human (`CLI-01`, `RANK-04`). No automated stage — not
`rank`, not any `-submit` command, not a Skill's own recommendation — can
ever produce this status. This is the single strongest guarantee in the
whole system and is repeated three times across the reference set
(`core-rules.md` rule #2, `decision-gates.md` RANK-04, this file) because
it is the rule most likely to be violated by an over-eager Skill trying to
be "helpful" by summarizing a recommendation as if it were final.

---

## The relationship between `hunt rank` and `hunt decide`

These are two structurally separate commands with different authorities:

- **`hunt rank <run_id>`** is a deterministic, automated, re-runnable
  computation. It reads only evidence already collected (fetches nothing
  new), applies the hard gates, and Pareto-ranks whatever passed. It can
  set `REJECTED`, `NEEDS_MORE_DATA`, or `PROMISING`. Run it after any stage
  that added new evidence (economics, supplier/IP, VOC, differentiation,
  red-team) to see whether standing changed. It is safe to run repeatedly
  — it has no side effects beyond recording the (re-)computed
  `final_status`.
- **`hunt decide <opportunity_id> approve|reject`** is the sole human
  action that produces a terminal decision the system treats as final
  (`QUALIFIED` or human-initiated `REJECTED`). It is never invoked
  autonomously by a Skill on the human's behalf (`core-rules.md` rule #2;
  `cli-command-reference.md`'s Decision section: "This command must always
  be presented to the actual human operator, never invoked autonomously by
  a Skill").

`hunt rank` never sets `QUALIFIED`. `hunt decide` is the only path to
`QUALIFIED`. A Skill's role sits entirely on the `rank` side of that line.

---

## A Skill's final-decision role, precisely

When a candidate reaches a point where a decision might be warranted
(typically `HUMAN_REVIEW`, but `hunt rank` can be run as an interim standing
check at any point), a Skill's job is exactly three steps, no more:

1. **Run `hunt rank <run_id>`** to get the current, up-to-date
   `PROMISING` / `REJECTED` / `NEEDS_MORE_DATA` standing — never rely on a
   stale status from an earlier point in the conversation.
2. **Present the full evidence** behind that standing to the human: which
   gates ran and passed/failed and why, which of the four ranking
   dimensions are present and their actual values, and — critically —
   what's still missing (economics `NOT_PROVIDED`, supplier/IP still
   `UNKNOWN`, VOC/differentiation/red-team not yet run, etc.). See
   `skills/final-decision/SKILL.md` for the exact command sequence
   (`hunt rank` then `hunt show`).
3. **Hand the approve/reject choice to the human explicitly**, via `hunt
   decide <opportunity_id> approve|reject --reason ...`. The Skill does not
   draft the reason on the human's behalf, does not recommend one outcome
   and then call the task done as if that recommendation were the decision,
   and does not run `hunt decide` itself under any circumstance.

A Skill may summarize the evidence and, if asked, describe tradeoffs — but
the moment a Skill's output could be mistaken for the decision itself
rather than an input to it, that is a violation of `core-rules.md` rule #2
and must be corrected.

---

## Quick-reference table

| Status | Set by | Meaning | Skill's obligation |
|---|---|---|---|
| `REJECTED` (gate) | `hunt rank`, automatically | A `CONFIRMED_*` finding fired an enabled hard gate | State exactly which gate and which `CONFIRMED_*` value; never imply human judgment was involved |
| `REJECTED` (human) | `hunt decide reject`, human only | A human explicitly rejected | State the recorded reason verbatim; never paraphrase into a stronger or weaker claim |
| `NEEDS_MORE_DATA` | `hunt rank`, automatically | Gates passed, zero ranking dimensions computed | Identify missing stages; never treat as a negative signal |
| `PROMISING` | `hunt rank`, automatically | Gates passed, Pareto-ranked on whatever dimensions exist | Present as a gate-pass technicality with explicit dimension coverage, never as a verdict |
| `QUALIFIED` | `hunt decide approve`, human only | Human approved | Never set, imply, or shortcut this from a Skill |
