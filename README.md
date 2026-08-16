# Amazon Opportunity Research Skills — Browser Edition

An evidence-driven Amazon product/business opportunity research system, built
as a Claude Agent Skills package. It orchestrates Claude Browser (web/Reddit
research), a Google Trends human-in-the-loop workflow, and a separate,
already-tested deterministic Python engine into one research cycle — from
"is there real demand for this niche?" through discovery, competition, voice
of customer, differentiation, red-team, economics, supplier, and IP, ending in
a decision only a human ever makes.

**This is not a scraper, not an auto-buyer, and not a profit guarantee
machine.** It is a structured way to gather and preserve evidence, apply the
same hard gates and thresholds every time, and tell you honestly when it
doesn't know something — rather than a "type a niche, get a business" tool.

## Why this exists

The [Amazon Opportunity Research Engine](../Amazon-products) (a separate,
private repository) already implements a tested, deterministic pipeline:
hard gates that only fire on confirmed risk, a state machine that can't skip
stages, an economics calculator that returns `INSUFFICIENT_DATA` instead of
guessing, and an evidence ledger that never lets browser research or an
LLM's confidence masquerade as fact. What it lacks is broad research reach —
its automated data providers can't read Reddit, can't browse a competitor's
site, and have no live review-text API at all.

This package doesn't rebuild that engine. It **wraps** it: Claude drives the
engine's `hunt` CLI at every stage, and fills the research gaps the engine's
providers structurally cannot with real Claude Browser research — while every
gate, threshold, and state transition still runs through the exact same
tested code.

## Architecture

```
 ┌─────────────────────────────┐        ┌──────────────────────────────────┐
 │   Claude (this Skill pkg)   │  hunt   │   Amazon-products engine          │
 │  orchestration + research   │ ──────▶ │  (deterministic source of truth)  │
 │  web / Reddit / Trends      │  CLI    │  state machine · evidence ledger  │
 │  evidence gathering         │ ◀────── │  hard gates · economics · ranking │
 └─────────────────────────────┘  JSON   └──────────────────────────────────┘
```

- **Deterministic engine role:** state machine, SQLite evidence ledger, hard
  gates, competitor-concentration math, economics calculator, Pareto ranking.
  Claude never reimplements any of this — it only calls the CLI and reports
  what came back.
- **Claude Browser role:** web/Reddit/competitor research for evidence no
  automated provider can supply — always recorded at the
  `EXTERNAL_BROWSER_RESEARCH` trust tier (capped at `ESTIMATE`, never `FACT`),
  never for candidates below `COMPETITOR_ANALYSIS` state.
- **Google Trends workflow:** the system decides exactly what Trends data it
  needs and generates the precise search/compare/timeframe request; a human
  runs the search on trends.google.com (no self-serve Trends API exists) and
  uploads the CSV exports; the engine parses and classifies them
  deterministically.
- **Evidence model:** `FACT | ESTIMATE | INFERENCE | UNKNOWN | CONTRADICTED |
  STALE | PENDING_HUMAN_REVIEW | INSUFFICIENTLY_OBSERVABLE`, unchanged from
  the source engine. See `references/evidence-model.md`.
- **Decision gates:** hard gates fire only on literal `CONFIRMED_*` values,
  never on `UNKNOWN`/`SUSPECTED_*`/`PENDING_*`. See `references/decision-gates.md`.
- **Anti-hallucination model:** see `references/core-rules.md` for the full
  contract — no conversion of `UNKNOWN`→fact, `PROMISING`→`QUALIFIED`,
  anecdote→market demand, or Trends index→sales volume is ever permitted.

## Installation

1. You need a working checkout of the `Amazon-products` engine with its
   Python environment set up (`.venv` with dependencies installed, `hunt`
   runnable). This package has no value without it — it is the orchestration
   layer, not a replacement.
2. Clone or copy this repository somewhere Claude can read it, e.g.
   `~/.claude/skills/amazon-business-research/` (exact install location
   depends on your Claude Skills environment's conventions).
3. Claude will discover `SKILL.md`'s frontmatter and offer to use this Skill
   when you ask about Amazon product research, business opportunity research,
   or continuing an existing research run.

No API keys are required for the mock-mode / Browser-research workflow this
package is built around. Real-provider credentials (Keepa, Logimu,
DataForSEO) are entirely the underlying engine's concern — see its own
`docs/DATA_SOURCE_CAPABILITY_REGISTRY.md` if you want to enable `--mode real`.

## Usage

Ask Claude something like:

> "Find me a product worth building a real business around in the pet
> supplies space."

or, to continue existing work:

> "Continue the research run from yesterday — where did opportunity
> abc123 leave off?"

Claude will follow `SKILL.md`'s canonical flow: establish a concept, check or
request demand evidence, run discovery, advance surviving candidates through
competition/VOC/differentiation/red-team, gather economics/supplier/IP inputs,
and then stop at a full evidence report — leaving the actual approve/reject
call to you via `hunt decide`.

### Example workflow

See `examples/example-research-workflow.md` for a full worked run, including
what the Google Trends request looks like and how Reddit VOC findings get
recorded.

## Decision vocabulary

| State | Meaning |
|---|---|
| `REJECTED` | A hard gate fired (confirmed contamination/IP blocker/supplier impossibility) or a human rejected it |
| `NEEDS_MORE_DATA` | Gates passed, but not enough evidence exists yet to rank |
| `PROMISING` | Passed gates and Pareto-ranked — a gate-pass technicality, **not** a business verdict |
| `QUALIFIED` | A human ran `hunt decide approve` — the only way to reach this state |

## Limitations

- Requires local shell access to the underlying engine; this is not a
  standalone hosted service.
- No automated review-text provider exists for any real data source — VOC on
  real (non-fixture) candidates depends on manual/browser-sourced findings.
- Google Trends has no self-serve API; every Trends data point requires a
  human to actually visit trends.google.com and download a CSV.
- Supplier and IP conclusions are never fully automated — `VALIDATED` and
  `CONFIRMED_BLOCKER` require explicit human confirmation, by design.
- This system does not, and cannot, guarantee that any candidate it rates
  `PROMISING` or even `QUALIFIED` will be commercially successful. It reduces
  guesswork and hallucination risk in the research process — it does not
  eliminate market risk.

## Safety boundaries

- No Amazon scraping, no CAPTCHA bypass, no anti-bot evasion, no session
  cookies, no automated purchases or listing changes, no autonomous ad spend.
- Real-provider data acquisition is entirely the underlying engine's
  responsibility, gated by explicit terms-acknowledgment — this package adds
  no scraping capability of its own.
- `RUN_MODE=REAL` never silently substitutes mock data.

## License

MIT — see `LICENSE`.

## Author

zaidadaqqa
