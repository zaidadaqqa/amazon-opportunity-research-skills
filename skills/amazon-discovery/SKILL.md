---
name: amazon-discovery
description: Use when running the actual Amazon product discovery funnel via `hunt discover`, after demand context is established, or directly if demand intelligence was skipped. Runs the zero-cost bulk discovery/filter/relevance pipeline and reports its output; hands qualifying candidates forward to deepen-start.
---

# Amazon Discovery

Runs the engine's existing zero-cost bulk discovery funnel
(`hunt discover`) and reports its output faithfully. This skill drives one
primary command — `hunt discover` — plus `hunt deepen-start` to hand off
survivors to the next stage. It never re-filters, re-classifies, or
re-scores a candidate itself: `hunt discover` already ran the deterministic
cheap-eligibility filter and relevance classifier before printing anything.

Full rule detail — funnel stage order, budgets, and exactly what
RELEVANT/AMBIGUOUS/UNRESOLVED_TITLE/rejection mean — lives in:

- `references/amazon-discovery.md` — funnel stages, config keys/defaults for
  every budget, stop-reason vocabulary, provenance/dedup rules.
- `references/relevance-and-filtering.md` — the relevance classification
  algorithm and the cheap eligibility filters (ASIN shape, prohibited
  keywords, price band).

Read both before interpreting `hunt discover` output for the first time.

---

## Operating procedure

### 1. Establish demand context (optional but preferred)

If a demand signal was already recorded for this concept
(`skills/demand-intelligence`), use `hunt demand-rank` / `hunt demand-show`
to decide whether and how much to prioritize it. This is advisory only —
proceeding straight to discovery without demand context is a valid choice,
never blocked.

### 2. Choose the category deliberately

`--category` must be one of the verified `CATEGORY_NAMES`. In `--mode real`
it is **required** and must never be guessed automatically — if
`guess_category()` (or your own read of the query) suggests one, confirm it
explicitly with the human before using it. Run `hunt providers` first if you
intend `--mode real`, to confirm what's actually usable.

### 3. Run discovery

```
hunt discover <query> --category <category> [--mode mock|real] \
    [--with-market-data mock|real] [--max-candidates N]
```

- Omit `--with-market-data` to proceed on discovery-stage evidence only
  (cheapest). Include it to attempt live snapshots for cheap-filter
  survivors, subject to the budgets in `amazon-discovery.md` §2
  (`max_candidates_advanced_to_market_data`,
  `live_enrichment_max_seconds`/`max_calls`,
  `max_unresolved_title_resolutions_per_run`).
- `--mode real` never silently falls back to mock data if a real provider
  isn't usable — it hard-stops instead (core-rules.md rule 3). Do not
  interpret that failure as permission to proceed with mock data without
  the human explicitly choosing to.

### 4. Read the funnel output

`hunt discover` prints:

- scanned / discovered / rejected counts,
- discovery **stop reason** (`amazon-discovery.md` §4 — one of
  `TARGET_REACHED | SOURCE_EXHAUSTED | BUDGET_EXHAUSTED | PROVIDER_FAILURE |
  NO_NEW_UNIQUE_RESULTS`; report it verbatim, never paraphrased),
- relevance breakdown (relevant / ambiguous / unresolved-title /
  rejected-irrelevant — see `relevance-and-filtering.md` §1 for what each
  category means and why),
- if `--with-market-data` was used: live-enrichment call/failure/skip
  counts, and whether any candidates were `STAGE_CAPPED` (budget exhausted
  before they could be validated — not rejected, just not yet observed
  live).

When explaining a rejection to the human, quote the actual reason code
(`REJECTED_INVALID_ASIN`, `REJECTED_PROHIBITED_CATEGORY`,
`REJECTED_PRICE_BAND:below_min/above_max`, `REJECTED_IRRELEVANT`,
`REJECTED_IRRELEVANT_AFTER_RESOLUTION`) and, for relevance rejections, the
`query_tokens`/`matched_tokens`/`overlap_ratio` evidence the classifier
recorded (REL-09) — never a vague "it didn't match."

### 5. Hand off survivors

```
hunt deepen-start <run_id>
```

Advances every `ECONOMICS_CHECK` candidate to `COMPETITOR_ANALYSIS` and
prints the opportunity IDs to continue with (competitor autopsy, then
`voc-prepare`/`voc-add`, etc. — outside this skill's scope).

### 6. Check overall status any time

```
hunt data-audit <run_id>
```

Read-only diagnostic — safe to re-run for a status check without spending
any new provider calls.

---

## Non-negotiable constraints for this skill

- **This skill never re-filters or re-classifies candidates.** The cheap
  eligibility filter (ASIN shape, prohibited keywords, price band) and the
  relevance classifier (RELEVANT/AMBIGUOUS/UNRESOLVED_TITLE/IRRELEVANT)
  already ran deterministically inside `hunt discover`. Do not apply your
  own judgment about whether a candidate "looks relevant" on top of what
  the CLI already decided — report what it decided.
- **`--category` is never guessed in real mode.** Confirm with the human.
- **`--mode real` never falls back to mock silently.** A hard-stop is a
  hard-stop — surface it, don't route around it.
- **STAGE_CAPPED is not a rejection.** A candidate that ran out of live-
  validation budget is `INSUFFICIENTLY_OBSERVABLE`, not disqualified —
  report it as "not yet observed," not "failed."
- **Provider/discovery-call failures are isolated by design**
  (`amazon-discovery.md` §4) — a single candidate or batch failure never
  means the whole run is invalid; read the actual counts and stop reason
  before concluding anything went wrong.
