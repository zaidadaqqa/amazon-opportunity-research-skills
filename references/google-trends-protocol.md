# Google Trends Human-in-the-Loop Protocol

Google Trends has no API this engine can call, and the demand-recording
service structurally imports no HTTP client (SVC-06 in
`demand-intelligence.md`). Every Google Trends observation the engine ever
sees was manually downloaded by a human from trends.google.com and handed
back as CSV files. This document is the operating procedure for that
exchange. It does not restate the qualification math — see
`demand-intelligence.md` for that.

---

## 1. Decide what data is actually needed before asking

A human's time and a Trends export are not free — do not request data you
don't have a concrete use for. Before generating a request:

- Confirm there isn't already a recorded signal for this exact concept
  (`hunt demand-show <concept_query>` — check for `NOT_RECORDED` first).
- Decide the **minimum** exports actually needed to compute a qualification
  per `demand-intelligence.md` §1: an "Interest over time" export is always
  required (DEM-01 needs >= 4 points; DEM-08 needs >= 24 points across >= 2
  years if seasonality matters for this concept). "Related queries" and
  "Rising queries" exports are only needed if breadth (DEM-10) or emerging-
  query discovery is actually part of what you're trying to learn — don't
  request them reflexively for every concept.
- Keep `--compare` terms to 0-2 (SVC-12: soft guidance, not code-enforced —
  follow it anyway). Every additional compare term is an additional export
  the human has to produce, and CSV-03 means only the *first* compare term's
  series is actually ingested from a multi-term "Time" header export — so
  requesting 3+ compare terms in one file produces data you cannot use for
  the others without a separate export. If you need multiple terms compared
  cheaply, prefer sequential single-term requests over one crowded compare
  request.
- If you only need a directional yes/no on whether a concept has visible
  search interest at all, a single-term, no-compare, default-timeframe
  request is enough — do not also request related/rising queries "just in
  case."

State explicitly, in your own reasoning before generating a request, which
export(s) you're asking for and why (e.g., "requesting interest-over-time
only, 5-year US window, to check DEM-06 trend direction; not requesting
related/rising because breadth isn't relevant to this decision").

---

## 2. The two-step CLI workflow

### Step 1 — generate the request

```
hunt demand-request <concept> [--compare a,b] [--geo US] \
    [--timeframe "today 5-y"] [--search-type WEB_SEARCH] [--category ...]
```

- This is pure local text generation — it calls no API and never guesses
  what to search or download on your behalf (SVC-13: the output text never
  claims to provide "search volume").
- `--search-type` must be one of `WEB_SEARCH | IMAGE_SEARCH | NEWS_SEARCH |
  GOOGLE_SHOPPING | YOUTUBE_SEARCH` (SVC-03) — pick the one that actually
  matches what you need (e.g. `GOOGLE_SHOPPING` for a purchase-intent signal
  vs. `WEB_SEARCH` for general interest); do not default to `WEB_SEARCH`
  without thinking about it.
- Present the exact generated `GOOGLE_TRENDS_DATA_REQUEST` text to the human
  verbatim — do not paraphrase, shorten, or "clean up" the request. The
  human acts on that literal text in their own browser session.
- Wait for the human to return actual CSV file(s). Never proceed to Step 2
  with placeholder, remembered, or assumed numbers if the human hasn't
  actually supplied files yet.

### Step 2 — record what came back

```
hunt demand-set <concept_query> [--is-topic] \
    --csv <path> [--related-csv <path>] [--rising-csv <path>] \
    [--related a,b] [--rising a,b] \
    [--need-frequency ...] [--need-frequency-evidence-note ...] \
    [--notes ...]
```

- `--csv` = the "Interest over time" export.
- `--related-csv` / `--rising-csv` each accept either the combined TOP+RISING
  sectioned format or the flat single-widget format — auto-detected, you
  don't choose the parser. Comma-separate multiple file paths if Trends
  exported one file per compare term.
- `--is-topic` must reflect whether the human searched a Trends "Topic"
  entity or a literal search string (SVC-10) — ask the human which one they
  selected if it's ambiguous from the request you generated; do not assume.
- `--need-frequency` is human-asserted only. Only set a non-`UNKNOWN` value
  if you have an actual evidence basis for it (e.g. the human told you this
  is a known daily-consumable product), and always pair it with
  `--need-frequency-evidence-note` describing that basis — the command
  raises `ValueError` if you omit the note (SVC-02). If you don't have real
  evidence for frequency, leave it `UNKNOWN` and add no note. Never write a
  note that just restates a guess as if it were evidence.
- The command prints the derived qualification and an advisory next-step
  recommendation — read `demand-intelligence.md` §1 to interpret that
  output; do not re-derive it yourself.

### Checking status any time

```
hunt demand-show <concept_query>
hunt demand-rank
```

`demand-show` returns `NOT_RECORDED` if nothing has been recorded yet — that
is the correct, honest answer, not an error to work around.
`demand-rank` orders every recorded concept PASS-first, FAIL-last
(SVC-09) — use it to decide which of several already-researched concepts to
prioritize; it triggers no new discovery and overrides no hard gate.

---

## 3. Identifying which downloaded file is which

Trends exports don't self-label clearly by filename alone; identify by
content:

- **Interest over time**: header row's first cell is one of `week | day |
  month | date | time` (case-insensitive) (CSV-01). If the export covers a
  multi-term compare, the header literally reads `"Time"` and only the
  second column (first term) will actually be ingested (CSV-03) — flag this
  to the human if they need the other compare columns.
- **Related / rising queries (sectioned)**: contains `TOP` and/or `RISING`
  section headers in the file (CSV-04). Values may include the literal
  string `"Breakout"` for a query with disproportionate rise — this is
  preserved as text, not converted to a number.
- **Related / rising queries (flat, single widget per file)**: header row is
  `"query","search interest","increase percent"` (CSV-05) — this is the
  shape Trends produces when you download one widget at a time instead of
  the combined export.
- If a file matches none of the above header shapes, the parser will raise a
  clear `ValueError` rather than silently mis-parse it (CSV-01, CSV-04) — if
  that happens, ask the human to confirm what they actually downloaded
  rather than guessing which flag to put it under.
- A missing/nonexistent path raises `ValueError("No such file: ...")`
  (CSV-06) — if you see this, the path was wrong or the file wasn't saved
  where expected; don't assume "no data" without checking.

---

## 4. What NEVER to do

- **Never treat the 0-100 Trends index as absolute search volume.** It is a
  relative, normalized index against the highest point in the selected
  timeframe/region — not a unit count, not comparable in magnitude across
  unrelated timeframes or geos. `demand_qualification` structurally never
  emits a `search_volume`/`absolute_volume` field (DEM-11); do not invent
  one when summarizing results for a human.
- **Never claim actual sales from Trends data.** Trends measures search
  interest, not purchases. A `PASS` qualification means "search interest
  signal looks healthy by the engine's deterministic rules," never "this
  will sell."
- **Never fabricate `need_frequency` without a genuine evidence note.** See
  §2 above — the CLI enforces this with a hard error (SVC-02), but the
  underlying principle matters even where enforcement exists: don't write a
  note that isn't real evidence just to satisfy the flag requirement.
- **Never request more than 0-2 compare terms without a stated reason.**
  Not code-enforced (SVC-12), so the discipline is on you — over-requesting
  wastes the human's time and, per CSV-03, most of the extra terms won't
  even get ingested correctly from a combined export.
- **Never treat a demand `FAIL` as a hard block.** Per SVC-08 and SVC-11 in
  `demand-intelligence.md`, this is advisory only — `hunt discover` still
  runs regardless. State the qualification honestly and let the human
  decide whether to proceed.

---

## 5. What happens after recording

Once `hunt demand-set` succeeds, all qualification logic (DEM-01 through
DEM-09, plus DEM-10 breadth and DEM-12 market depth where applicable) runs
automatically inside the engine — see `demand-intelligence.md` §1 for the
exact thresholds and combination logic. You never compute STRONG/MODERATE/
WEAK, GROWING/DECLINING/STABLE, seasonality, or the PASS/CAUTION/FAIL
qualification yourself from the raw numbers. Read it back with
`hunt demand-show`/`hunt demand-rank` and report exactly what the engine
returned, including its documented limitations (e.g. the December/January
seasonality wraparound gap in DEM-08).
