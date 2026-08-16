---
name: demand-intelligence
description: Use when researching whether a product niche/concept has real demand signal before committing further research budget to it. Generates precise Google Trends data requests, ingests human-supplied CSV exports, and reads the deterministic demand qualification the engine computes. Use before Amazon discovery for a new concept, or when deciding which of several concepts to prioritize.
---

# Demand Intelligence

Establishes whether a concept has an observable Google Trends search-interest
signal, using the engine's existing human-in-the-loop demand-recording layer.
This skill drives four CLI commands only:
`hunt demand-request`, `hunt demand-set`, `hunt demand-show`, `hunt
demand-rank`. It never computes qualification itself and never fetches
Trends data itself — Trends has no API here, and the recording service is
structurally network-free (see `references/demand-intelligence.md` SVC-06).

Full rule detail lives in two reference files — read them before running
this skill for the first time, and re-check them whenever output looks
surprising:

- `references/google-trends-protocol.md` — the request/record workflow,
  file-identification rules, and the "never do this" list.
- `references/demand-intelligence.md` — exact qualification thresholds,
  recording rules, and CSV parsing behavior.

---

## Operating procedure

### 1. Check what's already recorded

```
hunt demand-show <concept_query>
```

If a recent, relevant signal already exists, do not re-request Trends data
for the same concept — reuse it. `NOT_RECORDED` means proceed to step 2.

### 2. Decide the minimum data actually needed

Per `google-trends-protocol.md` §1: decide which export(s) — interest over
time, related queries, rising queries — you actually need for the decision
at hand, and how many `--compare` terms (0-2, and only with a reason).
Do not request more than the decision requires.

### 3. Generate the request

```
hunt demand-request <concept> [--compare a,b] [--geo US] \
    [--timeframe "today 5-y"] [--search-type WEB_SEARCH] [--category ...]
```

Present the exact generated `GOOGLE_TRENDS_DATA_REQUEST` text to the human,
verbatim. This is their instruction for what to search and download from
trends.google.com in their own browser — you cannot do this step yourself.

### 4. Wait for real CSV files

Do not proceed until the human has actually supplied file paths. Never
substitute placeholder, remembered, or assumed numbers. When files arrive,
identify each one by its header content per `google-trends-protocol.md` §3
(interest-over-time vs. related/rising sectioned vs. flat query-list) — ask
the human to confirm if a file's shape is ambiguous, rather than guessing.

### 5. Record it

```
hunt demand-set <concept_query> [--is-topic] \
    --csv <path> [--related-csv <path>] [--rising-csv <path>] \
    [--need-frequency ...] [--need-frequency-evidence-note ...] [--notes ...]
```

Only set `--need-frequency` (non-`UNKNOWN`) if you have real evidence for
it, and always with a genuine `--need-frequency-evidence-note` — the command
raises an error without one, and for good reason (SVC-02). Leave it
`UNKNOWN` otherwise.

### 6. Read back and report the qualification — do not recompute it

```
hunt demand-show <concept_query>
```

Report the printed `qualification` (`PASS`/`CAUTION`/`FAIL`/
`INSUFFICIENT_DATA`), `search_interest`, `trend_direction`, and any
`temporary_spike`/`seasonality` flags exactly as the engine returned them.
Interpret them only by pointing at `demand-intelligence.md` §1 — never
recalculate STRONG/WEAK, GROWING/DECLINING, or the qualification band
yourself from the raw CSV numbers. If seasonality is `NONE_DETECTED` and the
concept looks plausibly December/January-seasonal, disclose the known
wraparound limitation (DEM-08) rather than accepting the label uncritically.

### 7. Prioritizing across multiple concepts

```
hunt demand-rank
```

Use this to decide which already-recorded concept to spend Amazon-discovery
effort on first (PASS before CAUTION before INSUFFICIENT_DATA before FAIL).
It never triggers discovery itself.

---

## Non-negotiable constraints for this skill

- **This skill never computes qualification.** All STRONG/WEAK,
  GROWING/DECLINING/STABLE, temporary-spike, seasonality, and PASS/CAUTION/
  FAIL logic is deterministic Python inside `demand_qualification.py`,
  exposed only through `hunt demand-set`/`demand-show`. Report exactly what
  those commands print.
- **The demand gate is advisory only, never a hard block.** A `FAIL`
  qualification does not stop `hunt discover` from running (SVC-08, SVC-11
  — the demand layer is structurally firewalled from ranking/gates). Tell
  the human the qualification honestly; let them decide whether to spend
  discovery budget on the concept anyway.
- **Never treat the 0-100 index as absolute search volume or as sales.**
  See `google-trends-protocol.md` §4 for the full list of prohibited
  conversions.
- **Always ask the human for real Trends data via the exact generated
  request text.** Never guess at numbers, never fabricate a CSV, never
  proceed to `demand-set` without an actual file the human supplied.
