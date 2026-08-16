---
name: final-decision
description: use once a candidate has reached HUMAN_REVIEW (or you want an interim standing check at any point via hunt rank) to compile the full evidence-based report and present it to the human for their approve/reject decision. Never sets QUALIFIED itself.
---

# Final Decision

Compiles the complete, evidence-based standing of a candidate and presents
it to the human so **they** can approve or reject it. This Skill drafts
nothing on the human's behalf and never implies its own summary or
recommendation IS the decision. Full explanation of what each status means
lives in `references/decision-framework.md`; the exact gate/state/ranking
mechanics live in `references/decision-gates.md`. Read both before using
this Skill.

## When to use this

- Once a candidate reaches `HUMAN_REVIEW` (the natural end of the happy-path
  chain — see `decision-gates.md` SM-04).
- Or at any earlier point, as an interim standing check, via `hunt rank`
  alone — this is safe to run repeatedly and has no side effects beyond
  recording the recomputed `final_status` (`decision-framework.md`).

## Step 1 — Get current standing

```
hunt rank <run_id>
```

This re-applies hard gates and Pareto ranking using only evidence already
collected (fetches nothing new). It sets `final_status` to `REJECTED`
(gate fired), `NEEDS_MORE_DATA` (gates passed, zero ranking dimensions
computed), or `PROMISING` (gates passed, Pareto-ranked) — **never**
`QUALIFIED`. Always re-run this rather than relying on a standing computed
earlier in the conversation; new evidence may have changed it.

## Step 2 — Get the full evidence report

```
hunt show <opportunity_id>
```

This is the full evidence-first report. Every section without data says so
explicitly (`NOT_YET_ANALYZED`, `NO_DATA`, `NOT_PROVIDED`, etc.) — never a
silent omission (`REP-01`). Use this, not memory of earlier conversation
turns, as the source of truth for what's actually recorded.

## Step 3 — Present everything, organized and complete

Present to the human, in full:

- **Which gates ran and their result** (per `decision-gates.md` GATE-01/02)
  — and if any fired, exactly which `CONFIRMED_*` value fired it. Never
  imply a gate fired on a `SUSPECTED_*`/`PENDING_*`/`UNKNOWN` value — that
  is structurally impossible.
- **The four ranking dimensions** (`decision-gates.md` RANK-03) — which are
  present, their actual values, and which are omitted because that stage
  hasn't run yet. Never treat an omitted dimension as if it scored zero.
- **Demand** — from `hunt demand-show`/report data, including the
  qualification and its advisory (non-enforced) status.
- **Competition** — competitor autopsy findings from `hunt show`.
- **VOC / customer pain points** — from review analysis and/or manually
  recorded pain points, including severity distribution.
- **Differentiation** — the copycat-resistance classification if the stage
  has run, `NOT_YET_ANALYZED` if not.
- **Red team** — `EVIDENCED` vs. `HYPOTHESIS` findings, distinctly labeled.
- **Economics** — the full base case and stress-test results from
  `hunt economics-show`, or `NOT_PROVIDED` if `economics-set` was never
  called (`economics.md` ECON-11). Never compute or restate these numbers
  differently than what the CLI printed.
- **Supplier/IP status** — the recorded `supplier_status`/`ip_status`
  (default `UNKNOWN` if never set), and whether either is human-confirmed.
- **What's still missing** — explicitly list every stage/field not yet
  recorded, so the human can see the gaps as clearly as the findings.

## Step 4 — Hand the decision to the human, explicitly

State the current `final_status` (`PROMISING`/`REJECTED`/
`NEEDS_MORE_DATA`) and what it actually means per
`decision-framework.md` — in particular, if `PROMISING`, say plainly that
this is a gate-pass technicality, not a business verdict, and summarize
exactly which dimensions support it. Then present the decision command for
the human to run themselves:

```
hunt decide <opportunity_id> approve --reason "<human's own reasoning>"
hunt decide <opportunity_id> reject --reason "<human's own reasoning>"
```

This Skill may summarize tradeoffs if asked, but must not draft the
`--reason` text as if it were the human's own words, must not run `hunt
decide` itself under any circumstance, and must not phrase its own summary
in a way that could be mistaken for the decision itself having already been
made.

## What this Skill must never do

- Never call `hunt decide` itself, for either `approve` or `reject`.
- Never present a `PROMISING` result as if it were a positive verdict on
  the product's viability.
- Never imply that a `REJECTED` gate result reflects human judgment when it
  was actually automatic (or vice versa) — always be clear which is which
  (`decision-framework.md`).
- Never omit a "still missing" section — an incomplete picture presented as
  if it were complete is itself a form of hallucination by omission.

See `references/decision-framework.md` for the full explanation of what
each status means and the relationship between `hunt rank` and `hunt
decide`, and `references/decision-gates.md` for the exact gate/state/
ranking mechanics and rule-preservation table.
