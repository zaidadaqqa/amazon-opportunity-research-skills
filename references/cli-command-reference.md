# CLI Command Reference

Canonical reference for every `hunt` command exposed by the existing deterministic
engine (`Amazon-products/src/engine/cli.py`, verified against source 2026-08-16).
Every Skill in this system drives the pipeline **exclusively** through these
commands — never by writing to the SQLite database directly, never by
reimplementing the logic these commands wrap.

Run as `hunt <command> ...` (installed via `pyproject.toml [project.scripts]`)
or `python -m engine.cli <command> ...` from the `Amazon-products` repo root,
with its `.venv` activated.

All commands operate against the same SQLite DB (WAL mode) — state persists
across calls and process restarts. `run_id`/`opportunity_id` values printed by
one command are the inputs to the next.

---

## Discovery

### `hunt <query>` (bare command)
Runs discovery → acquisition → lineage → economics for a free-text `QUERY`.
- `--mode mock|real` (default `mock`). `real` requires `--asins` (no real
  provider supports free-text discovery) and never falls back to mock data —
  hard-stops with `REAL_DATA_PROVIDER_REQUIRED` instead.
- `--asins B000XXXXXX,B000YYYYYY` — seed ASINs directly, bypassing discovery.
- `--marketplace` — override `config.marketplace.id`.
- Prints a table of `opportunity_id | state | researchability`.

### `hunt discover <query>`
Zero-cost **bulk** discovery over the static dataset (`docs/FREE_DISCOVERY_RESEARCH.md`).
This is the primary discovery path for the Browser Edition — cheap, no API key.
- `--category` — one of `CATEGORY_NAMES` (33 verified categories). **Required**
  in `--mode real`, never guessed automatically; `guess_category()` may hint
  one but the caller must confirm it.
- `--mode mock|real` (default `mock`).
- `--with-market-data mock|real` — optionally attempt live snapshots for
  survivors after discovery. Omit to proceed on discovery-stage evidence only.
- `--max-candidates` — override `research_depth.static_discovery_max_candidates`.
- Prints: scanned/discovered/rejected counts, discovery stop reason, relevance
  breakdown (relevant/ambiguous/unresolved-title/rejected-irrelevant), and
  (if `--with-market-data` used) live-enrichment call/failure/skip counts.
- **Next:** `hunt deepen-start <run_id>`.

### `hunt providers`
Shows which real data providers are usable right now and exactly what's
missing (credential, terms acknowledgment, or genuine capability gap). Read-only,
launches no hunt. Always run this before attempting `--mode real` anywhere.

### `hunt dataforseo-check [--confirm-spend]`
Standalone DataForSEO connection test. Free auth check by default; `--confirm-spend`
also spends the real, trivial cost (~$0.012) of one live Amazon Labs call.
Never prints credential values. Writes nothing to the DB.

---

## Runs / Ranking

### `hunt runs [--limit 20]`
Lists past research runs.

### `hunt rank <run_id>`
Applies the existing hard gates (`engine.ranking.gates`) and Pareto ranking
(`engine.ranking.rank`) to every non-terminal opportunity in `run_id`, using
only evidence already collected — **fetches no new data**. Persists results.
**Never sets QUALIFIED** — a gate failure sets `REJECTED`; a pass sets
`final_status=PROMISING` (a hint for human review, not a verdict).
Run this after any stage that added new evidence (economics, supplier, VOC,
differentiation, red team) to see whether the candidate's standing changed.

---

## Deepen (competitor autopsy → VOC → differentiation → red team)

Two parallel paths exist. **Use the `-prepare`/`-submit` pattern** (this is the
"Claude Code + Claude Pro" default operator workflow with no `ANTHROPIC_API_KEY`
required) — it is what the Browser Edition's Skills are built around. The plain
`hunt deepen` command is a direct-API alternative that requires configuring an
LLM key inside the engine itself and is out of scope for Browser Edition Skills.

### `hunt deepen-start <run_id>`
Deterministic step 1, no LLM: competitor autopsy + advances every
`ECONOMICS_CHECK` candidate to `COMPETITOR_ANALYSIS`. Prints JSON.
**Next:** `hunt voc-prepare <opportunity_id>` for each printed opportunity_id.

### `hunt voc-prepare <opportunity_id> [--mode mock|real]`
Prints the system + per-batch user prompts for VOC/review analysis. Requires
state `COMPETITOR_ANALYSIS`. `--mode real` currently always fails — no real
review-text provider exists. **You (Claude) analyze each batch yourself**,
then call `voc-submit`.

### `hunt voc-submit <opportunity_id> --file <path>`
`file` = `{"results": [<ReviewBatchAnalysis>, ...]}`, one per batch from
`voc-prepare`, same order. Validates + persists, advances
`COMPETITOR_ANALYSIS → VOC_ANALYSIS`. **Next:** `differentiation-prepare`.

### `hunt voc-add <opportunity_id> --category ... --description ...`
Manual fallback — record one human/browser-observed VOC finding directly, no
batch analysis required. `--category` one of `product|packaging|shipping|
expectation_mismatch|misuse|isolated`. `--severity LOW|MEDIUM|HIGH`,
`--frequency-signal ISOLATED|RECURRING|DOMINANT`, `--solvability
EASY|MODERATE|HARD|UNKNOWN` all optional. Extends the same `pain_points` table
as automated `voc-submit` — not a second VOC model. This is the command the
`reddit-voc` and `browser-research` Skills call to record findings.

### `hunt voc-manual-complete <opportunity_id> [--confirm-no-findings]`
Advances `COMPETITOR_ANALYSIS → VOC_ANALYSIS` **without** an automated
review-text provider (none exists for any real source). Requires at least one
prior `voc-add` finding, **or** `--confirm-no-findings` passed explicitly by a
human/Claude who actually reviewed the listing and found nothing. Refuses
(does not silently skip) if neither condition holds. This is the required path
for every real-mode opportunity and for browser-research-driven VOC.

### `hunt differentiation-prepare <opportunity_id>`
Prints system+user prompt for differentiation analysis. Requires `VOC_ANALYSIS`.

### `hunt differentiation-submit <opportunity_id> --file <path>`
`file` = one `DifferentiationAssessment`-shaped JSON object. Validates +
persists, advances `VOC_ANALYSIS → DIFFERENTIATION_ANALYSIS`.
**Next:** `redteam-prepare`.

### `hunt redteam-prepare <opportunity_id>`
Prints system+user prompt for Red Team analysis. Requires `DIFFERENTIATION_ANALYSIS`.

### `hunt redteam-submit <opportunity_id> --file <path>`
`file` = one `RedTeamAnalysis`-shaped JSON object. Validates + persists,
advances `DIFFERENTIATION_ANALYSIS → RED_TEAM → HUMAN_REVIEW`.
**Next:** `hunt show`, then `hunt decide` (human only).

---

## Human-supplied evidence (economics / market / supplier / demand)

### `hunt economics-set <opportunity_id> [flags...] [--file <path>]`
Supplies cost/price assumptions, persists as `HUMAN_VERIFIED` evidence, and
**immediately computes** economics + 5 stress scenarios via the unmodified
`engine.economics.calculator`/`stress_test` — the deterministic layer never
reimplemented in a Skill. Flags: `--selling-price --unit-cost
--inbound-shipping-per-unit --prep-per-unit --packaging-per-unit
--referral-fee-pct --fulfillment-fee-per-unit --storage-fee-per-unit-monthly
--return-rate-pct --ppc-cost-per-unit --misc-cost-per-unit --fixed-launch-cost`.
`--file` merges a JSON file under individual flags (flags win on conflict).
Any field left unset stays UNKNOWN, never zero (except the 5 explicitly-disclosed
optional cost fields, which are treated as 0 for the *margin total* but listed
in `fields_treated_as_unknown`).

### `hunt economics-show <opportunity_id>`
Re-runs the calculator against previously-persisted inputs. Prints a clear
"none supplied yet" message rather than a fabricated result if `economics-set`
was never called.

### `hunt market-snapshot-set <opportunity_id> [flags...] [--file <path>]`
Records a market snapshot a human/Claude Browser manually observed on a
legitimate source (e.g. the actual Amazon listing) — the zero-cost fallback
when no live `MarketDataProvider` is configured. Writes the same
`market_snapshots` table a live provider would, tagged
`data_classification=REAL_CURRENT`, `source_type=HUMAN_VERIFIED`. Flags:
`--price --price-currency --rating --review-count --bsr --bsr-category
--buybox-price --in-stock --observed-at --source-note`.

### `hunt supplier-set <opportunity_id> [flags...] [--file <path>]`
Records a human supplier/IP validation assessment. **The only thing that can
move the supplier/IP hard gates off permanent UNKNOWN** — no pipeline stage
infers these. `--supplier-status UNKNOWN|MANUAL_SOURCING_REQUIRED|VALIDATED|
CONFIRMED_IMPOSSIBLE`, `--ip-status UNKNOWN|PENDING_HUMAN_LEGAL_REVIEW|
CLEARED_BY_HUMAN|CONFIRMED_BLOCKER` (both default `UNKNOWN` if never set).
Other flags: `--supplier-name --unit-cost-quoted --moq --lead-time-days
--certifications --supplier-notes --ip-notes`. Invalid status values raise
immediately — never silently coerced.

### `hunt supplier-show <opportunity_id>`
Shows persisted supplier/IP validation, or `NOT_YET_VALIDATED`.

---

## Demand Intelligence (Google Trends human-in-the-loop)

### `hunt demand-request <concept> [--compare a,b] [--geo US] [--timeframe "today 5-y"] [--search-type WEB_SEARCH] [--category ...]`
**STEP 1.** Generates the exact `GOOGLE_TRENDS_DATA_REQUEST` text for a demand
concept — purely local text generation, calls no API, never guesses what to
search/compare/download. `--compare` should stay small (0-2 terms — soft
guidance only, not code-enforced). This is the text you (Claude) present to
the human to act on in their own browser.

### `hunt demand-set <concept_query> [--is-topic] [--csv path] [--related-csv path] [--rising-csv path] [--related a,b] [--rising a,b] [--need-frequency ...] [--need-frequency-evidence-note ...] [--notes ...]`
**STEP 2.** Records the human-supplied Trends observation after they've
downloaded CSVs from trends.google.com per the Step-1 request. `--csv` = the
"Interest over time" export. `--related-csv`/`--rising-csv` accept either the
combined TOP+RISING sectioned format or the flat single-widget format
(auto-detected); comma-separate multiple paths if Trends exported one file per
compare term. `--need-frequency` is human-asserted only — non-UNKNOWN values
**require** `--need-frequency-evidence-note` or the command raises. Never
fabricates search volume. Prints the derived qualification and an advisory
(non-enforced) next-step recommendation.

### `hunt demand-show <concept_query>`
Shows recorded demand evidence + derived qualification, or `NOT_RECORDED`.

### `hunt demand-rank`
Advisory ranking (PASS first, FAIL last) over every concept with a recorded
demand signal. Consult **before** choosing which query to run `hunt discover`
on. Never triggers discovery itself, never overrides any hard gate.

---

## Browser Research

### `hunt browser-brief <opportunity_id> [--save/--no-save]`
Generates the External Browser Research Brief. **Refuses below
`COMPETITOR_ANALYSIS` state** — never generate this for a raw discovery-stage
candidate (cost control). Copy the printed prompt into browser-research work;
bring results back via `browser-evidence-add`. Saves to
`reports/runs/<run_id>/<opportunity_id>_browser_brief.txt` by default.

### `hunt browser-evidence-add <opportunity_id> --file <path>`
Ingests an `ExternalEvidencePack`-shaped JSON file. Recorded at the
`EXTERNAL_BROWSER_RESEARCH` trust tier — **capped at ESTIMATE, never FACT**,
distinguishable from `HUMAN_VERIFIED`/provider evidence everywhere downstream.
Traceable findings (real `source_urls`) feed the same VOC `pain_points`
mechanism as `voc-add`; untraceable findings are preserved in the raw pack but
never become a pain point.

### `hunt browser-evidence-show <opportunity_id>`
Shows whether external browser research has been recorded, or
`EXTERNAL_RESEARCH_PENDING`.

---

## Decision (human-only)

### `hunt decide <opportunity_id> <approve|reject> [--reason ...]`
**The only way an opportunity can reach `QUALIFIED`.** No automated stage —
not `rank`, not `deepen`, not any `-submit` command — can ever set it.
`approve` → state machine advances to `QUALIFIED`, records a `decisions` row
(`decided_by="human"`), sets `final_status=QUALIFIED`.
`reject` → advances to `REJECTED`, records decision + optional rejection reason.

This command must always be presented to the actual human operator, never
invoked autonomously by a Skill on the human's behalf.

---

## Reporting / Audit

### `hunt show <opportunity_id>`
Full evidence-first report as JSON. Every section without data says so
explicitly (`NOT_YET_ANALYZED`, `NO_DATA`, `NOT_PROVIDED`, etc.) — never a
silent omission.

### `hunt report <opportunity_id>`
Generates and saves Markdown + JSON report files.

### `hunt data-audit <run_id>`
Read-only diagnostic: discovery totals, cheap-filter rejection breakdown,
validation-attempt evidence-status breakdown, freshness, field coverage,
provenance, economics readiness, final-status breakdown. No new provider
calls — safe to re-run anytime for a status check.

---

## Command → required precondition state (for orchestration)

| Command | Requires state | Produces state |
|---|---|---|
| `discover` / bare `hunt` | — (creates new) | `DISCOVERED`→...→`ECONOMICS_CHECK` (or terminal `REJECTED`/paused) |
| `deepen-start` | `ECONOMICS_CHECK` | `COMPETITOR_ANALYSIS` |
| `voc-prepare` / `voc-submit` / `voc-add` / `voc-manual-complete` | `COMPETITOR_ANALYSIS` | `VOC_ANALYSIS` (submit/manual-complete only) |
| `differentiation-prepare` / `differentiation-submit` | `VOC_ANALYSIS` | `DIFFERENTIATION_ANALYSIS` |
| `redteam-prepare` / `redteam-submit` | `DIFFERENTIATION_ANALYSIS` | `RED_TEAM` → `HUMAN_REVIEW` |
| `decide` | `HUMAN_REVIEW` (or any active state, for reject) | `QUALIFIED` or `REJECTED` (terminal) |
| `economics-set` / `market-snapshot-set` / `supplier-set` / `voc-add` / `browser-evidence-add` | any (opportunity must exist) | no state change by itself — adds evidence only |
| `rank` | any non-terminal | may set `REJECTED` (gate fail) or `final_status=PROMISING`/`NEEDS_MORE_DATA` — never changes `state`, only `final_status` |

Calling a `-prepare`/`-submit`/`deepen-start` command against the wrong state
raises `ValueError` and prints a clear message — it never silently coerces or
skips. Skills must check state via `hunt show <opportunity_id>` (or the
result of the previous command) before calling the next stage.
