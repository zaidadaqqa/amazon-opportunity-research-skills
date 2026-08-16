---
name: amazon-business-research
description: Orchestrates a complete, evidence-based Amazon product/business opportunity research cycle — from niche demand intelligence through Amazon discovery, live validation, competition, VOC, differentiation, red team, economics, supplier, and IP — ending in a human decision. Use when the user asks to research a product opportunity, find a business idea worth building, evaluate an Amazon niche, or continue a research run already in progress. Wraps the existing deterministic Amazon-products engine via its `hunt` CLI; adds Claude Browser research, Reddit VOC, and Google Trends human-in-the-loop on top of it.
---

# Amazon Business Research — Browser Edition (Master Orchestrator)

## What this is

A Claude Skills package that lets Claude run the full Amazon product-opportunity
research workflow implemented in the separate `Amazon-products` engine
(`/home/zaid/Desktop/Amazon-products` in this environment, or wherever the
user's checkout lives — locate it before starting; see **Prerequisite** below),
while adding real research capability the engine's own automated providers
cannot: Claude Browser web/Reddit research and a Google Trends
human-in-the-loop workflow.

**This package does not reimplement the engine's business logic.** Every gate,
threshold, state transition, and economics/ranking calculation is enforced by
the engine's own tested Python code (568 passing tests as of this build). This
Skill's job — and every specialized Skill under `skills/` — is to drive that
engine's `hunt` CLI correctly, interpret its output honestly, and add research
breadth the engine cannot get on its own. Read `references/core-rules.md`
before doing anything else; its five rules are non-negotiable.

## Prerequisite

This Skill requires shell (Bash) access to a checkout of the `Amazon-products`
engine with its Python virtualenv set up (`.venv`, dependencies installed) and
`hunt` runnable (`hunt --help` or `python -m engine.cli --help` from the repo
root with `.venv` activated). If that's not available in the current
environment, say so explicitly and stop — do not attempt to answer research
questions from general knowledge instead. This Skill has no value without the
engine underneath it.

## Canonical flow

```
DISCOVER CONCEPT
    ↓
DEMAND INTELLIGENCE (skills/demand-intelligence) ── Google Trends human-in-the-loop
    ↓  (advisory gate only — never blocks; see demand-intelligence.md SVC-08)
AMAZON DISCOVERY (skills/amazon-discovery) ── hunt discover
    ↓  (relevance + cheap filters + staged budgets already applied by the CLI)
AMAZON VALIDATION (skills/amazon-validation) ── live snapshot interpretation
    ↓  (reaches ECONOMICS_CHECK state)
COMPETITION ANALYSIS (skills/competition-analysis) ── hunt deepen-start
    ↓  (reaches COMPETITOR_ANALYSIS state)
VOC (skills/reddit-voc + browser-research, or automated voc-prepare/submit)
    ↓  (reaches VOC_ANALYSIS state)
DIFFERENTIATION (skills/differentiation)
    ↓  (reaches DIFFERENTIATION_ANALYSIS state)
RED TEAM (skills/red-team)
    ↓  (reaches RED_TEAM → HUMAN_REVIEW state)
ECONOMICS (skills/economics) ── can run any time ECONOMICS_CHECK+ is reached
SUPPLIER RESEARCH (skills/supplier-research) ── can run any time, needed before QUALIFIED confidence
IP RISK (skills/ip-risk) ── can run any time, needed before QUALIFIED confidence
    ↓
FINAL DECISION (skills/final-decision) ── hunt rank, hunt show, then hand off to the human
    ↓
hunt decide <opportunity_id> approve|reject   ← HUMAN ONLY, never automated
```

Do not skip a stage's precondition. `references/cli-command-reference.md` has
the exact required-state table; every `-prepare`/`-submit`/`deepen-start` call
raises a clear error rather than silently coercing if the precondition isn't
met — if that happens, go back and complete the missing stage, don't route
around it.

## How to run a research cycle

1. **Establish the concept.** If the user gave a specific niche/query, use it.
   If they said something like "find me a product worth building a business
   around," do not immediately start searching — ask what domain/category
   interests them, or propose 2-3 concrete candidate niches grounded in
   whatever context you have, and confirm before spending any research budget.
   Use `skills/demand-intelligence/SKILL.md` to check whether a concept
   already has a recorded demand signal (`hunt demand-show`) before
   requesting new Google Trends data.

2. **Cheap gates first, always.** Run demand intelligence and
   `hunt discover` (which already applies relevance classification and cheap
   eligibility filters deterministically) before any expensive step. See
   `references/time-budget-controller.md`. Never run `browser-brief`,
   `deepen-start`'s competitor snapshots, or supplier/IP research on a
   candidate that hasn't survived the cheap stages.

3. **Advance survivors stage by stage**, using each specialized Skill in
   `skills/` in the order shown above. Check state via `hunt show
   <opportunity_id>` whenever you're unsure what stage a candidate is at.

4. **Track multiple candidates in parallel where it's cheap to do so** —
   discovery and relevance filtering naturally produce several candidates from
   one run; don't force single-candidate tunnel vision. But do not run
   expensive stages (browser research, supplier/IP, Google Trends requests)
   on more candidates than the budget discipline in
   `references/time-budget-controller.md` allows.

5. **Stop and reject early** when a candidate fails a hard gate or a red-team
   finding is decisive. Don't keep researching a candidate the engine has
   already told you is `REJECTED`.

6. **Never reach a final verdict yourself.** When a candidate reaches
   `HUMAN_REVIEW` (or you want an interim check via `hunt rank`), use
   `skills/final-decision/SKILL.md` to compile the full evidence report and
   present it — then stop and let the human run `hunt decide`. Do not draft
   the decision as if it were already made.

## What must never happen (see references/core-rules.md for the full contract)

- A hard gate never fires on `UNKNOWN`/`SUSPECTED_*`/`PENDING_*` — only
  literal `CONFIRMED_*` values, and only a human sets those (via
  `hunt supplier-set`) or the engine's own lineage heuristics (capped at
  `SUSPECTED_CONTAMINATION`, never `CONFIRMED`).
- `QUALIFIED` is reached only by the human running `hunt decide approve`.
  This Skill package never runs that command autonomously and never implies
  a recommendation is a final decision.
- `--mode real` failures are never silently retried with `--mode mock`.
- Economics numbers are never computed by Claude — only reported from
  `hunt economics-set`/`economics-show` output.
- Evidence from Claude Browser research is recorded via
  `hunt browser-evidence-add`, capped at `ESTIMATE`, never presented as FACT.
- Google Trends' 0-100 index is never described as absolute search volume or
  sales.

## Reference index

| File | Covers |
|---|---|
| `references/core-rules.md` | The 5 non-negotiable rules + anti-hallucination contract — read first |
| `references/cli-command-reference.md` | Every `hunt` command, flags, state preconditions |
| `references/evidence-model.md` | Evidence taxonomy, FACT ceiling, freshness/TTL, contradictions |
| `references/validation.md` | Provider abstraction, RUN_MODE=REAL guard, fallback hierarchies |
| `references/provider-capability.md` | What real providers can't give you — the gaps Browser research fills |
| `references/human-input-protocol.md` | When/how to ask a human for data vs. use Browser research |
| `references/demand-intelligence.md` | Demand qualification thresholds and formulas |
| `references/amazon-discovery.md` | Bulk discovery funnel stages and budgets |
| `references/relevance-and-filtering.md` | Relevance classification, cheap eligibility filters |
| `references/google-trends-protocol.md` | Human-in-the-loop Trends request/ingest workflow |
| `references/competition.md` | Competitor autopsy formulas, lineage/contamination rules |
| `references/voc.md` | VOC evidence rules, pain-point vocabulary |
| `references/differentiation.md` | Moat categories, evidence-grounding rule |
| `references/red-team.md` | Red-team scope checklist, EVIDENCED-vs-HYPOTHESIS rule |
| `references/browser-research-protocol.md` | Systematic web/Reddit research methodology |
| `references/economics.md` | Margin/cash-margin/breakeven formulas, stress scenarios |
| `references/supplier-ip.md` | Supplier/IP status vocabularies, human-only-origination rule |
| `references/decision-gates.md` | Hard gates, state machine, Pareto ranking |
| `references/decision-framework.md` | REJECTED/NEEDS_MORE_DATA/PROMISING/QUALIFIED semantics |
| `references/time-budget-controller.md` | Cheap-before-expensive research discipline |

## Skill index

`skills/demand-intelligence`, `skills/amazon-discovery`, `skills/amazon-validation`,
`skills/competition-analysis`, `skills/browser-research`, `skills/reddit-voc`,
`skills/differentiation`, `skills/red-team`, `skills/economics`,
`skills/supplier-research`, `skills/ip-risk`, `skills/final-decision` — each is
independently invocable; this Master Skill sequences them.

See `examples/example-research-workflow.md` for a full worked run.
