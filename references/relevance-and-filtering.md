# Relevance Classification and Cheap Eligibility Filters

Canonical reference for the deterministic candidate-filtering logic that
runs inside `hunt discover` before any candidate is counted RELEVANT,
AMBIGUOUS, UNRESOLVED_TITLE, or rejected
(`Amazon-products/src/engine/discovery/relevance.py` and
`hunt.py::_passes_cheap_eligibility_filters`), verified against source
2026-08-16. A Skill never re-runs, second-guesses, or overrides this
classification — `hunt discover`'s printed relevance breakdown and rejection
reasons are the ground truth. See `amazon-discovery.md` for where these
filters sit in the funnel's stage order.

---

## 1. Relevance classification algorithm

Applied per-candidate as `query` vs. candidate `title`.

### 1.1 Tokenization (REL-01)

- Lowercase the text.
- Extract tokens with regex `[a-z0-9]+`.
- Strip stopwords: `{a, an, the, for, with, of, and, or, to, in, on, by, at}`.

### 1.2 Plural stemming (REL-02)

Deterministic suffix stripping, not a general stemmer library:

- `-ies` → `y`, only if resulting word length > 4.
- `-es` → dropped, only if the remainder ends in a sibilant (`s, x, z, ch,
  sh`) and length > 4.
- Otherwise a trailing `-s` is stripped if length > 3 and the word doesn't
  end in `-ss`.

Examples confirmed by tests: `"perches"` → `"perch"`; `"fixtures"` →
`"fixture"` (not over-stemmed to `"fixtur"`); `"lids"` → `"lid"`.

### 1.3 Classification decision tree (REL-03 through REL-08)

1. **Empty query** (REL-03): if the query has zero meaningful tokens after
   normalization → `AMBIGUOUS`, reason "query has no meaningful tokens."
2. **No title** (REL-04): if `title` is `None`/empty → `AMBIGUOUS`, **never**
   `IRRELEVANT`. Missing data is not evidence of a bad match — "missing data
   != bad data" is an immutable principle here, not an implementation
   detail to be second-guessed.
3. **Overlap ratio** (REL-05): `ratio = |query_tokens ∩ title_tokens| /
   |query_tokens|`.
4. **Zero overlap** (REL-06): if `ratio == 0`:
   - If `len(title_tokens) < min_meaningful_title_tokens_for_relevance_judgment`
     (config, default **3**) → `UNRESOLVED_TITLE` (too little title text to
     confidently judge; queued for live title resolution instead of
     rejected).
   - Else → `IRRELEVANT`.
   - The boundary is exact: a 3-token title with zero overlap is
     `IRRELEVANT`; a 2-token title with zero overlap is `UNRESOLVED_TITLE`.
5. **Above threshold** (REL-07): if `ratio >= relevance_match_threshold`
   (config, default **0.6**) → `RELEVANT`. This is not an "every word must
   match" rule — e.g., 2 of 3 query tokens matching (ratio ≈ 0.67) already
   passes.
6. **Partial overlap** (REL-08): if `0 < ratio < 0.6` → `AMBIGUOUS`, never
   silently promoted to RELEVANT or demoted to IRRELEVANT. Example: query
   "cat trees" vs. title "cat window perch" has 1/3 (well, 1/2 depending on
   tokens) overlap — stays AMBIGUOUS, proceeds unfiltered rather than being
   guessed at.

### 1.4 Evidence traceability (REL-09)

Every classification result carries `query_tokens`, `matched_tokens`, and
`overlap_ratio` (or an explicit reason string for the AMBIGUOUS/empty-query
cases). When reporting a rejection, quote these fields — never assert "this
was rejected as irrelevant" without the specific tokens that drove it.

---

## 2. Cheap eligibility filters (`hunt.py::_passes_cheap_eligibility_filters`)

These run **before** relevance classification and before any live/paid call
— zero-cost, deterministic rejections only.

### 2.1 ASIN shape (ELIG-01)

Regex `^[A-Z0-9]{6,20}$`. Deliberately looser than Amazon's real 10-character
ASIN format, to accommodate synthetic test fixtures (e.g.
`B0SCALE00001`, 12 characters). Lowercase, punctuation, or empty strings are
rejected as `REJECTED_INVALID_ASIN`.

### 2.2 Prohibited keywords (ELIG-02)

Config: `research_depth.static_discovery_prohibited_title_keywords`, default
list: `firearm, ammunition, taser, prescription`. Case-insensitive substring
match against the title → `REJECTED_PROHIBITED_CATEGORY`. This list is
explicitly documented in code as an "illustrative starting list only, NOT an
authoritative Amazon restricted-category policy" — never present it to a
human as a comprehensive compliance filter, only as a cheap first-pass
guard.

### 2.3 Price band (ELIG-03)

Config: `static_discovery_min_price_usd` / `static_discovery_max_price_usd`
(both `null` = unconstrained, by default). Rejection reasons:
`REJECTED_PRICE_BAND:below_min` / `REJECTED_PRICE_BAND:above_max`.

**Immutable safety rule**: a candidate with no price data at all is *never*
rejected for that reason — absence of price is not evidence the price is
out of band. A malformed price string is treated the same as "no price,"
not as an automatic rejection.

### 2.4 Product-shape exclusion (ELIG-04)

Config: `research_depth.product_shape_excluded_keywords` — **disabled by
default** (empty list). This is a deliberate no-op mechanism awaiting an
explicit policy decision, not a bug and not a filter currently doing
anything. If a human asks whether shape-based exclusion is active, the
correct answer is "no, it exists in config but is off by default and has no
test coverage because it's intentionally inert."

---

## 3. Rule preservation

| Rule ID | This file's section | Source (Amazon-products file:line) | Test |
|---|---|---|---|
| REL-01 | 1.1 | relevance.py:34-37,65-66 | test_relevance.py |
| REL-02 | 1.2 | relevance.py:48-62 | test_sibilant_plural_stemming, test_plural_wording_variation_still_matches |
| REL-03 | 1.3 | relevance.py:96-103 | (implicit, no direct unit test found) |
| REL-04 | 1.3 | relevance.py:105-112 | test_missing_title_is_ambiguous_never_irrelevant |
| REL-05 | 1.3 | relevance.py:114-116 | multiple |
| REL-06 | 1.3 | relevance.py:118-121 | test_completely_unrelated_title_is_irrelevant, test_brand_only_title_is_unresolved_not_irrelevant, test_unresolved_title_boundary_at_exactly_min_tokens |
| REL-07 | 1.3 | relevance.py:122-123 | test_exact_wording_match_is_relevant, test_classification_is_conservative_not_naive_every_word_rule |
| REL-08 | 1.3 | relevance.py:124-125 | test_partial_overlap_is_ambiguous_not_relevant_or_irrelevant |
| REL-09 | 1.4 | relevance.py:69-132 | test_reason_is_traceable_to_specific_tokens |
| ELIG-01 | 2.1 | hunt.py:838-846,868,883-884 | test_invalid_asin_shape_is_rejected_with_explicit_reason_code |
| ELIG-02 | 2.2 | hunt.py:886-890; config/default.yaml:196-203 | test_cheap_filter_rejects_prohibited_keyword |
| ELIG-03 | 2.3 | hunt.py:892-905 | test_price_bound_filter_applies_when_configured, test_cheap_filter_missing_price_is_never_a_rejection_reason |
| ELIG-04 | 2.4 | hunt.py:907-916 | none found (documented as deliberate no-op) |
