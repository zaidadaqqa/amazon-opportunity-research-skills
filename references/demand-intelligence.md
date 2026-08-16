# Demand Intelligence — Qualification, Recording, and CSV Rules

Canonical reference for the deterministic demand-signal layer
(`Amazon-products/src/engine/analysis/demand_qualification.py`,
`src/engine/demand/service.py`, `models.py`, `request.py`), verified against
source 2026-08-16. This is what actually happens *after* `hunt demand-set`
records human-supplied Google Trends data — a Skill never recomputes any of
this itself, it only reads and reports what the engine already decided.

For the human-in-the-loop request/record workflow itself, see
`google-trends-protocol.md`. This file only covers what the numbers mean once
data exists.

---

## 1. Demand qualification thresholds (verbatim)

All thresholds below live in `config/default.yaml`'s `demand:` section unless
noted otherwise. None of these numbers may be changed by a Skill or asserted
differently in prose — quote them exactly.

### 1.1 Minimum data requirement (DEM-01, DEM-02)

- Fewer than `demand.min_points_for_classification` (**4**) usable data
  points → everything is `INSUFFICIENT_DATA`. The engine never guesses from
  fewer than 4 points.
- Only numeric points count. Google Trends' below-threshold marker `"<1"` is
  pre-parsed to a real `0` by the CSV layer (see CSV-02 below) and *is*
  counted as a usable point, distinct from a blank/missing value (`None`),
  which is dropped as a gap, not treated as zero.

### 1.2 `search_interest` level (DEM-03, DEM-04, DEM-05)

Computed from the average of usable points and the fraction of points that
are non-zero (`nonzero_fraction`):

| Level | Condition |
|---|---|
| STRONG | `avg >= 50` (`strong_interest_avg_threshold`) **and** `nonzero_fraction >= 0.8` (`min_nonzero_coverage_fraction`) |
| MODERATE | `avg >= 20` (`moderate_interest_avg_threshold`) and STRONG conditions not met |
| WEAK | everything else — including `avg >= 50` but coverage `< 0.8` (a high-average series that is mostly zero with rare spikes is WEAK, not STRONG) |

### 1.3 `trend_direction` (DEM-06)

- `quarter = max(1, len(values) // 4)`
- `early_avg` = mean of the first quarter of points; `recent_avg` = mean of
  the last quarter.
- If `early_avg <= 0`: `GROWING` if `recent_avg > 0`, else `STABLE`.
- Else if `recent_avg >= early_avg * 1.15` (`growth_ratio_threshold`): `GROWING`.
- Else if `recent_avg <= early_avg * 0.85` (`decline_ratio_threshold`): `DECLINING`.
- Else: `STABLE`.
- The band between 0.85x and 1.15x (±15%) is deliberately treated as noise,
  not a trend — do not describe a series inside that band as "slightly up"
  or "slightly down"; it is STABLE.

### 1.4 `temporary_spike` flag (DEM-07)

- `peak >= median(rest) * 3.0` (`spike_ratio_threshold`) **and** the number
  of points sitting at the peak value is `<= 2`.
- A sustained plateau at a high value does not trigger this flag (too many
  points at "peak"); only a narrow, short-lived spike does.

### 1.5 `seasonality` (DEM-08)

- Requires **>= 24 dated points spanning >= 2 distinct calendar years**
  (years parsed from a `"YYYY-MM..."` date prefix). Below this, seasonality
  is `INSUFFICIENT_DATA` (or `TEMPORARY_SPIKE` if that flag is already set).
- Per-year peak month is computed for each year present.
- `SEASONAL` if any two years' peak months differ by `<= 1` (literal
  `abs(diff) <= 1` on month numbers 1-12).
- Else `NONE_DETECTED` (not `NOT_SEASONAL` — some older internal docs use the
  wrong label; the actual enum value is `NONE_DETECTED`).
- **Known limitation, not caught by the code**: the ±1-month comparison is a
  plain numeric difference, not circular. A December (12) vs. January (1)
  peak — genuinely adjacent months across a year boundary — has `abs(12-1)
  = 11`, so it is **not** detected as seasonal. Disclose this limitation
  whenever reporting a `NONE_DETECTED` result for a concept with a
  suspected December/January peak; do not silently trust the label in that
  specific case.
- These 24-point / 2-year / ±1-month constants are hardcoded in
  `demand_qualification.py`, **not** exposed in `config/default.yaml` — a
  known code/config inconsistency versus 1.1-1.4 above, disclosed here so a
  Skill never claims they are configurable.

### 1.6 Overall `qualification` gate (DEM-09)

Never a single dominant metric — combination logic only:

| Qualification | Condition |
|---|---|
| `INSUFFICIENT_DATA` | `search_interest` is `INSUFFICIENT_DATA` (i.e., <4 points) |
| `FAIL` | `search_interest == WEAK` **and** `trend_direction == DECLINING` (both together) |
| `CAUTION` | `search_interest == WEAK` **or** `trend_direction == DECLINING` **or** `temporary_spike` (any single one of these alone) |
| `PASS` | none of the above |

A declining trend alone, a weak interest level alone, or a spike alone never
produces `FAIL` on its own — only WEAK+DECLINING together does. Never
paraphrase this as "weak demand fails" without the declining-trend
co-condition.

### 1.7 Breadth (DEM-10)

Plain counts of related/rising query list lengths from the recorded JSON.
Malformed JSON is treated as `0`, never a crash. This is a count of distinct
queries observed, not a demand-strength signal by itself.

### 1.8 No fabricated search volume (DEM-11)

`classify_demand_signal`'s output structurally never contains a
`search_volume` or `absolute_volume` key. A Skill must never add one when
reporting results — the 0-100 Trends index is never converted to a unit
count.

### 1.9 Market depth (DEM-12)

`assess_market_depth` reuses the existing `competition.min_sample_size`
(**3**) rather than a separate demand-specific threshold:

- Counts distinct `REAL_CURRENT`-classified market snapshots for the run,
  deduplicated by `parent_asin or asin` (so parent/child variants of the same
  product count once).
- `ESTIMATE`-only rows are explicitly excluded from the count.
- Fewer than 3 distinct products observed → `INSUFFICIENT_SAMPLE`.
- 3 or more → `MULTIPLE_INDEPENDENT_PRODUCTS_OBSERVED`.
- This is never expressed as a market-share percentage.

---

## 2. Demand recording rules (`hunt demand-set` / `demand-show` / `demand-rank`)

### 2.1 `need_frequency` (SVC-01, SVC-02)

- Must be one of `DAILY | WEEKLY | MONTHLY | SEASONAL | OCCASIONAL | UNKNOWN`
  — any other value raises `ValueError`.
- Any non-`UNKNOWN` value **requires** `--need-frequency-evidence-note`. The
  engine raises `ValueError` rather than accept a bare frequency claim —
  frequency is never inferred from category reasoning like "this is a home
  product, probably WEEKLY." If you (Claude) do not have a genuine evidence
  basis for the frequency, leave it `UNKNOWN` (which needs no note) rather
  than invent a plausible one.

### 2.2 `search_type` (SVC-03)

Must be one of `WEB_SEARCH | IMAGE_SEARCH | NEWS_SEARCH | GOOGLE_SHOPPING |
YOUTUBE_SEARCH` on `hunt demand-request`, else `ValueError`.

### 2.3 Evidence tier (SVC-04)

Every recorded demand signal is written at `source_type=HUMAN_VERIFIED`,
`status=FACT`, `entity_type=niche` — the same evidence tier as
`market-snapshot-set`/`voc-add`. No new, looser evidence vocabulary is
invented for demand data.

### 2.4 Append-only (SVC-05)

Re-recording the same concept with `hunt demand-set` always creates a **new**
row; it never overwrites a prior observation. `hunt demand-show` / the
qualification logic reads the most recent row. Historical Trends
observations for a concept remain queryable, not silently lost.

### 2.5 No network access (SVC-06)

The demand recording service imports no HTTP client. It cannot fetch Trends
data itself — this is structurally why the human-in-the-loop CSV workflow in
`google-trends-protocol.md` exists at all.

### 2.6 Unrecorded concept default (SVC-07)

`hunt demand-show`/`get_demand_context` for any concept with no signal
returns `{"status": "NOT_RECORDED"}` — never a fabricated qualification.

### 2.7 Gate is advisory only, never enforced (SVC-08)

`gate_recommendation` derived from the qualification:

| Qualification | `proceed_to_amazon_research` |
|---|---|
| PASS or CAUTION | `True` |
| INSUFFICIENT_DATA | `None` (guidance: gather more data, not "disqualified") |
| FAIL | `False`, but explicitly documented as advisory — **`hunt discover` still runs even after a FAIL.** Nothing in the engine blocks discovery on a demand FAIL. |

A Skill must never tell a human "discovery is blocked because demand
FAILed" — that is false. It may recommend not spending discovery budget on a
FAILed concept, but the human/Claude can proceed anyway and the CLI will
comply.

### 2.8 Ranking concepts (SVC-09)

`hunt demand-rank` orders recorded concepts: `PASS` (0) before `CAUTION` (1)
before `INSUFFICIENT_DATA` (2) before `FAIL` (3), tie-broken alphabetically
by concept query. Advisory only — never triggers discovery itself.

### 2.9 Topic vs. search term (SVC-10)

`is_topic` is a distinct boolean, never conflated between a Google Trends
"Topic" entity and a literal search term — carry this distinction through
when recording (`--is-topic` flag) and when describing results.

### 2.10 Demand/ranking firewall (SVC-11) — critical

The demand-intelligence layer is **structurally firewalled** from
`engine.ranking.gates` / `engine.ranking.rank` / scoring: those modules never
import demand code, and `hunt rank`'s output is byte-identical whether or
not a demand signal was ever recorded for the same niche. This means:

- A demand `FAIL` cannot reject a candidate via `hunt rank`.
- A demand `PASS` cannot promote a candidate via `hunt rank`.
- Demand intelligence exists purely to inform **human/Claude prioritization
  of research effort** before spending discovery/validation budget — it is
  never a scoring input to the actual opportunity ranking. Never imply
  otherwise in a report.

### 2.11 Request generator bounds (SVC-12, SVC-13)

- `hunt demand-request --compare` has no hard cap in code; the "stay to 0-2
  terms" guidance in `google-trends-protocol.md` is a soft convention only,
  not enforced by the CLI. A Skill should still follow the convention
  deliberately (do not exploit the absence of enforcement to request many
  compare terms).
- The generated request text (`render_trends_request`) never contains the
  string "search volume" — it does not imply Trends provides absolute
  volume, by construction. Do not add that phrase yourself when relaying the
  request to a human.

---

## 3. Google Trends CSV parsing rules

Three separate parsers exist in `models.py`; the correct one is auto-detected
by header shape — a Skill never needs to specify which parser to use, only
which flag (`--csv`, `--related-csv`, `--rising-csv`) the file goes under.

### 3.1 Interest-over-time format (CSV-01, CSV-02, CSV-03)

- Detected by scanning for a header row whose first cell is one of `week |
  day | month | date | time` (case-insensitive). If none of these is found,
  the parser raises `ValueError` — an unrecognized file is never silently
  guessed at.
- `"<1"` (Trends' below-measurement-threshold marker) is parsed as a real
  `0`, distinct from a blank cell (parsed as `None`, a gap).
- **Known limitation**: for a multi-term COMPARE export, the header row is
  literally `"Time"` and only the **second** column (the first
  query/compare term) is read. Additional comparison columns in the same
  file are not ingested. This is a documented gap, not a silent drop — when
  a human supplies a multi-term compare CSV, only the first term's series
  gets recorded; if the other terms matter, they should be exported/parsed
  separately.

### 3.2 Related/rising sectioned format (CSV-04)

- Detected by `TOP` / `RISING` section headers (case-insensitive, exact
  match after stripping whitespace).
- `"Breakout"` (Trends' marker for a query with disproportionate rise) is
  preserved as the literal string `"Breakout"`, never coerced to a number.
- `<1` / `&lt;1` values are parsed to `0`.
- Raises `ValueError` only if **neither** `TOP` nor `RISING` header is found
  anywhere in the file.

### 3.3 Flat query-list format (CSV-05)

- A distinct parser (`parse_trends_query_list_csv`) for the "one widget per
  file" export style, header `"query","search interest","increase
  percent"`.
- Strips Unicode bidi marks (common in Trends CSV exports) before parsing.
- `"Breakout"` preserved as a literal string here too.

### 3.4 Missing file (CSV-06)

Any of the three parsers raises `ValueError("No such file: ...")` for a path
that doesn't exist — never treated as "no data" / zero silently.

---

## 4. Rule preservation

| Rule ID | This file's section | Source (Amazon-products file:line) | Test |
|---|---|---|---|
| DEM-01 | 1.1 | demand_qualification.py:50,61-74 | test_insufficient_points_returns_insufficient_data_not_a_guess, test_no_interest_over_time_at_all_is_insufficient_data |
| DEM-02 | 1.1 | demand_qualification.py:27-43 | test_no_search_volume_field_is_ever_fabricated |
| DEM-03 | 1.2 | demand_qualification.py:82-90 | test_strong_sustained_demand |
| DEM-04 | 1.2 | demand_qualification.py:84-86 | (implicit) |
| DEM-05 | 1.2 | demand_qualification.py:87 | test_weak_declining_demand_fails |
| DEM-06 | 1.3 | demand_qualification.py:78-100 | test_stable_direction, test_growing_direction, test_declining_direction_flags_caution_even_with_moderate_interest |
| DEM-07 | 1.4 | demand_qualification.py:102-111 | test_temporary_spike_detected_inside_flat_series |
| DEM-08 | 1.5 | demand_qualification.py:140-187 | test_seasonal_pattern_detected_with_multiyear_monthly_data, test_seasonality_insufficient_data_below_two_years |
| DEM-09 | 1.6 | demand_qualification.py:116-127 | test_weak_declining_demand_fails, test_temporary_spike_detected_inside_flat_series, test_declining_direction_flags_caution_even_with_moderate_interest |
| DEM-10 | 1.7 | demand_qualification.py:190-203 | test_breadth_counts_related_and_rising_queries |
| DEM-11 | 1.8 | demand_qualification.py (whole function) | test_no_search_volume_field_is_ever_fabricated |
| DEM-12 | 1.9 | demand_qualification.py:206-254 | test_market_depth_insufficient_sample_below_min_sample_size, test_market_depth_dedupes_parent_child_variants, test_market_depth_ignores_estimate_only_rows |
| SVC-01 | 2.1 | models.py:14; service.py:45-46 | test_need_frequency_invalid_value_rejected |
| SVC-02 | 2.1 | service.py:47-51 | test_need_frequency_requires_evidence_note, test_need_frequency_unknown_by_default_needs_no_note |
| SVC-03 | 2.2 | models.py:15; service.py:43-44 | test_generate_trends_request_rejects_invalid_search_type |
| SVC-04 | 2.3 | service.py:56-65 | test_record_demand_signal_writes_human_verified_evidence |
| SVC-05 | 2.4 | service.py:35-93 | test_re_recording_same_concept_appends_not_overwrites |
| SVC-06 | 2.5 | service.py, models.py | test_record_demand_signal_never_calls_a_provider |
| SVC-07 | 2.6 | service.py:97-107 | test_get_demand_context_not_recorded_for_unknown_concept |
| SVC-08 | 2.7 | service.py:120-147 | (structural, DEMAND_INTELLIGENCE.md) |
| SVC-09 | 2.8 | service.py:150-174 | test_rank_concepts_by_demand_orders_pass_before_fail, test_rank_concepts_by_demand_empty_when_nothing_recorded |
| SVC-10 | 2.9 | models.py:27 | test_topic_vs_search_term_preserved_distinctly |
| SVC-11 | 2.10 | (cross-file guarantee) | test_ranking_gates_module_never_imports_demand_code, test_rank_run_identical_with_and_without_demand_signal |
| SVC-12 | 2.11 | request.py:13,16-27 | test_generate_trends_request_defaults, test_generate_trends_request_with_compare_and_category |
| SVC-13 | 2.11 | request.py | test_render_trends_request_never_claims_search_volume |
| CSV-01 | 3.1 | models.py:39-71 | test_parse_trends_csv_rejects_unrecognized_format |
| CSV-02 | 3.1 | models.py:80-88 | test_parse_trends_csv_real_format |
| CSV-03 | 3.1 | models.py:44-52 | test_parse_trends_csv_real_multiterm_time_header_format, test_parse_trends_csv_still_accepts_week_format_after_time_fix |
| CSV-04 | 3.2 | models.py:95-143 | test_parse_trends_related_rising_csv_real_format, test_parse_trends_related_rising_csv_rejects_unrecognized_format, test_parse_trends_related_rising_csv_handles_missing_rising_section |
| CSV-05 | 3.3 | models.py:146-210 | test_parse_trends_query_list_csv_real_format_with_bidi_marks, test_parse_trends_query_list_csv_preserves_breakout_literal, test_parse_trends_query_list_csv_rejects_unrecognized_format |
| CSV-06 | 3.4 | models.py (all 3 parsers) | test_parse_trends_csv_missing_file_raises_clear_error |
