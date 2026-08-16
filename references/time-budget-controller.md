# Time & Cost Budget Discipline

This is a discipline document, not a rule table — it states the general
principle every research Skill in this package must follow about *when* to
spend expensive research effort. The exact staged-funnel budget numbers
(e.g. `research_depth.static_discovery_max_candidates`,
`max_candidates_advanced_to_market_data`, and similar config-driven caps)
are owned by, and documented in, `skills/amazon-discovery/SKILL.md` and its
references — this file deliberately does not duplicate those numbers here.
If a specific numeric budget is needed, look it up there rather than
guessing or restating a remembered figure.

---

## The general principle

Cheap discovery and cheap filtering exist specifically to eliminate weak
candidates **before** any expensive step runs on them. "Expensive" in this
project means anything that costs real API spend, real human time, or real
Claude Browser research effort — not just literal dollars. The expensive
steps this applies to include, at minimum:

- Live market-data validation (`--with-market-data real` / real-mode
  acquisition)
- `hunt deepen-start`'s competitor-snapshot autopsy
- `hunt browser-brief` and the Claude Browser research it triggers
- Google Trends requests (`hunt demand-request`) and the human time spent
  running them in an actual browser and uploading CSVs
- Supplier/IP research (`skills/supplier-research`, `skills/ip-risk`) —
  this is real human/Claude time spent on outreach, search, and
  verification, not just an API call

None of these should run on a candidate that a cheap, already-available
signal would have eliminated. This is the practical meaning of CLAUDE.md's
"COST CONTROL" section's "CHEAP DISCOVERY → CHEAP FILTER → MEDIUM DATA →
ECONOMICS → DEEP COMPETITOR DATA → REVIEW/VOC ANALYSIS → RED TEAM → HUMAN
REVIEW" funnel, restated for a Skill-driven, browser-edition workflow.

---

## Rule 1 — Verify precondition state before spending budget

Every deep-research Skill in this package (`supplier-research`, `ip-risk`,
`browser-research`, `reddit-voc`, `red-team`, `differentiation`,
`competition-analysis`, `final-decision`) must verify — via `hunt show
<opportunity_id>` or the printed output of the previous command — that the
candidate has actually reached the state that stage requires, per
`cli-command-reference.md`'s "Command → required precondition state" table,
**before** generating a browser-research request, a Google Trends request,
or a supplier outreach effort for it.

This is not merely a courtesy — the underlying CLI commands themselves
enforce these preconditions and raise `ValueError` on a mismatch
(`cli-command-reference.md`: "Calling a `-prepare`/`-submit`/`deepen-start`
command against the wrong state raises `ValueError`... it never silently
coerces or skips"). Checking first avoids wasted research effort that would
just be rejected by the engine anyway. Concretely: `hunt browser-brief`
itself refuses below `COMPETITOR_ANALYSIS` (`CLI-07`) — a Skill should
never attempt to generate that brief for an earlier-stage candidate in the
first place, rather than relying on the CLI's refusal as the only defense.

---

## Rule 2 — Never re-run a question that already has an answer

Before generating any new request or spending any new research effort on a
candidate, check whether the answer is already recorded:

- `hunt show <opportunity_id>` — full evidence-first report; check before
  assuming any section is empty.
- `hunt demand-show <concept_query>` — check before generating a new
  `hunt demand-request` for the same concept; a `NOT_RECORDED` result means
  genuinely nothing is recorded yet, anything else means it already is.
- `hunt supplier-show <opportunity_id>` — check before starting new
  supplier research; `NOT_YET_VALIDATED` means genuinely nothing recorded.
- `hunt browser-evidence-show <opportunity_id>` — check before generating a
  new `hunt browser-brief`; `EXTERNAL_RESEARCH_PENDING` means genuinely
  nothing recorded yet.

A concept, opportunity, or question that already has a recorded answer
should not be re-researched "just to be sure" — that duplicates human
browser time (Google Trends, supplier outreach) and Claude Browser research
effort for no new evidence. If the existing answer looks stale or was
recorded under different assumptions, that is a reason to say so explicitly
and ask the human whether to re-run it — not to silently re-run it without
comment, and not to silently reuse it without checking it's still
applicable either.

---

## Rule 3 — Stop researching a candidate the moment it's `REJECTED`, or once evidence is sufficient

- If `hunt rank` (or any stage transition) has already put a candidate into
  `REJECTED`, no further research skill should be run on it. Per
  `decision-gates.md` SM-09, a terminal state exits only via `REOPENED` —
  a Skill continuing to spend research budget on an already-`REJECTED`
  candidate without an explicit human decision to reopen it is exactly the
  wasted effort this document exists to prevent.
- Even for a non-terminal candidate, once the evidence already collected is
  sufficient to answer the specific question a Skill exists to answer (e.g.
  supplier-research has already produced a clear `VALIDATED` or
  `CONFIRMED_IMPOSSIBLE` outcome with human confirmation), stop — do not
  keep researching "for extra confidence" once the recorded status is
  already decisive. Additional research effort is better spent on the next
  unresolved question or the next candidate in the run.

---

## Relationship to `amazon-discovery`'s staged funnel

`skills/amazon-discovery/SKILL.md` (and its references) own the actual
numeric caps that implement "cheap discovery eliminates weak candidates
before expensive steps" at the top of the funnel — e.g. how many candidates
survive static discovery before any live market-data call is attempted.
This document is the general principle those numbers implement, extended
downstream to every deep-research Skill past discovery. When in doubt about
a specific number, defer to `amazon-discovery`'s reference material rather
than restating a number here from memory.
