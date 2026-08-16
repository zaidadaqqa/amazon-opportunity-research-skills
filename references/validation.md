# Validation — Provider Abstraction & Acquisition Layer

What "live validation" of a candidate actually means in this engine, what can
go wrong when calling a real data provider, and how the engine already
defends against each failure mode. Read this before driving
`hunt discover --with-market-data` or interpreting its output, and before
reading a `hunt show <opportunity_id>` evidence section that came from a live
provider call.

The core idea: a validation attempt against a real provider has exactly three
possible honest outcomes — **it produced real evidence**, **it explicitly
failed** (and the failure is visible, not swallowed), or **it hard-stopped**
because a real provider genuinely can't be used right now. There is no fourth
outcome where a failure quietly becomes "zero results" or "mock data,
unlabeled." The rules below are what make that guarantee hold.

---

## 1. Provider abstraction hard fences (`src/engine/providers/base.py`, `registry.py`)

### D1. `CapabilityNotSupported` is a hard fence, never silently empty

`Provider.require(capability)` raises `CapabilityNotSupported` if a provider
doesn't declare a capability it's being asked for. This exception **must
never be caught and silently converted into an empty result** anywhere in
this system. Source: `base.py:36-39,6-11`. Enforced across every provider
(e.g. static_dataset's `get_market_snapshot`/`get_price_history`/`get_offers`,
Keepa's `discover_candidates`).

→ If a `hunt` command's output or error text says a capability isn't
supported, that is the engine telling you a genuine, structural gap — not a
transient failure to retry. See `provider-capability.md` for the specific
gaps that exist today (E1-E19) and, where relevant, whether Claude Browser
research can fill it instead.

### D2. `ProviderRequestError` must propagate, never become "zero results"

Source: `base.py:42-45`. Verified end-to-end in
`tests/integration/test_run_hunt_provider_failure.py`: one seeded ASIN
failure rejects only that one opportunity (`reason_code=PROVIDER_ERROR`) — it
never crashes the whole run, and it never gets reinterpreted as "this
product has no demand/no competition."

→ If you see `reason_code=PROVIDER_ERROR` on an opportunity, that opportunity
was **not evaluated** — it is not evidence of a weak market. Do not report it
as a rejected/failed candidate on the merits; report it as
"validation attempt failed, needs a retry or a different provider/mode."

---

## 2. RUN_MODE=REAL safety guard (D3) — the core hard gate

`select_market_data_provider` / `select_keyword_provider` /
`select_discovery_provider` / `select_review_provider(mode)` all follow the
same contract:

| `mode` value | Behavior |
|---|---|
| `"mock"` | Always returns `MockProvider`. |
| anything not in `{"mock", "real"}` | Raises `ValueError` immediately. |
| `"real"` | Constructs the real, credentialed, terms-acknowledged provider — or raises `RealDataProviderRequired`. **Never** falls back to `MockProvider`. |

Source: `registry.py` throughout (`select_market_data_provider` etc., e.g.
around `registry.py:270-307`). This is immutable/non-negotiable — no Skill
may treat a `RealDataProviderRequired` failure as permission to proceed on
mock data without the human explicitly choosing that.

Tests: `test_mock_mode_returns_mock_provider`,
`test_real_mode_without_api_key_raises...`,
`test_real_mode_never_returns_mock_provider_even_if_something_goes_wrong`,
`test_unknown_mode_raises_value_error`, mirrored for all four provider types.

### D4. Per-provider gating logic (exact)

A real provider is usable only when **both** are true:

1. The credential is present (`KEEPA_API_KEY` / `LOGIMU_API_KEY` /
   DataForSEO credentials, read from environment — see H4/H5 in
   `human-input-protocol.md`).
2. `terms_acknowledged: true` is set in `config/local.yaml` — **never** the
   tracked `config/default.yaml`, which ships `terms_acknowledged: false` by
   default (`test_default_config_does_not_acknowledge_logimu_terms` asserts
   this literally).

`keepa_status()`, `logimu_status()`, `dataforseo_status()` implement this
(`registry.py:43-146`). `static_dataset_status()` is the one exception — it
only requires `license_acknowledged` (no credential needed, since it's a
free public dataset).

→ Run `hunt providers` first, always, before attempting `--mode real`
anywhere. It shows exactly which of the two conditions is missing per
provider — never guess which one it is.

---

## 3. Provider fallback hierarchies

### D5. Market data provider fallback

Logimu preferred (validated 86-96% current-field coverage), Keepa automatic
secondary, else hard-stop `RealDataProviderRequired`. Source:
`registry.py:270-307`.

### D6. Discovery provider fallback

`select_discovery_provider(mode, prefer_current=True)`: Logimu `/v1/serp`
preferred when available and `prefer_current=True`, else
`StaticDatasetDiscoveryProvider`, else hard-stop.
`prefer_current=False` deliberately skips Logimu (used when the caller wants
the frozen historical dataset specifically).

### D7. `ReviewCapabilityUnavailable`

A subclass of `RealDataProviderRequired`. `select_review_provider("real")`
**always** raises this — distinct from a missing-credential failure, because
"acquiring an API key cannot fix it": no legitimate live review-text API
exists in this project as of 2026-08-14. This is a hard, permanent
capability-gap rule, not something a future credential resolves. Source:
`registry.py:255-268`.

→ This is exactly why VOC analysis has a manual path
(`hunt voc-manual-complete`, `hunt voc-add`) — see `cli-command-reference.md`
and `human-input-protocol.md`. Do not wait for or suggest a "real mode" fix
for review text; there isn't one.

### D8. `sync_providers_table`

Idempotent upsert by provider name, mirrors
`docs/DATA_SOURCE_CAPABILITY_REGISTRY.md`. Re-calling it does not duplicate
rows. Source: `registry.py:189+`.

### D9. Marketplace-code mapping is never guessed

Keepa/Logimu/DataForSEO each hold exactly one verified marketplace entry
(`ATVPDKIKX0DER` → US). An unmapped marketplace raises
`ProviderRequestError` rather than guessing a code. The phrase "never guess
one" appears verbatim in all three provider files.

→ If a run targets a marketplace other than US, expect and accept a hard
failure here — do not propose inferring a marketplace code from context.

---

## 4. Acquisition layer (`src/engine/acquisition/market.py`, `human_snapshot.py`)

### F1. Acquisition ownership boundary

Only `engine.acquisition.market` may call `MarketDataProvider` methods and
immediately persist results. This is an architectural/design boundary
(docstring), not mechanically enforced — but Skills must never bypass `hunt`
commands to call a provider "directly."

### F2. `discovery_price_hint` never becomes the persisted price

Only the value from `provider.get_market_snapshot()` itself is ever written
to `market_snapshots.price`. A discovery-stage hint (e.g. Logimu SERP price)
can be recorded as a **separate, explicitly labeled** claim (see B3 in
`evidence-model.md`) but is never substituted in as "the" price.

### F3. Price claim FACT special case

A price claim gets `FACT` confidence only when `claim_type == "price"` AND
the provider is `FIRST_PARTY` — a narrower special case layered on top of A3
(`evidence-model.md`). Note: this branch does not currently apply the
freshness-override to price when `FIRST_PARTY`, but since no `FIRST_PARTY`
provider exists yet, this has no observable effect today (flagged in source
as code redundancy, not a bug — do not treat it as a live behavior
difference).

### F4. `data_classification="REAL_CURRENT"` is hardcoded for live snapshots

`acquire_market_snapshot` always writes `data_classification="REAL_CURRENT"`
— this column reflects *provenance* (a live `MarketDataProvider` call), not
confidence. A `STALE`-status snapshot is still `REAL_CURRENT` in this column.
Historical/discovery data instead goes through
`enrichment.normalize.promote_normalized_fields`, which requires an explicit
classification (see G1 below) rather than defaulting.

→ **Never** read `data_classification` alone as a freshness/trust signal.
Always read the evidence `status` (`FACT`/`ESTIMATE`/`STALE`/...) from
`evidence-model.md` for that.

### F5. Price history acquisition

`acquire_price_history` records **one** evidence row for the whole payload,
not per data point. An empty history is not treated as an error — it's a
legitimate "no history available" result.

### F6. Human-attested snapshot — never empty

`HumanMarketObservation.has_any_observed_value()` must be true, or the call
raises `ValueError`. It also raises if the opportunity doesn't exist or has
no linked ASIN. Every unset field stays `None`, never defaulted to 0. Source:
`human_snapshot.py:50-72`. See `human-input-protocol.md` for the exact
command (`hunt market-snapshot-set`).

### F7. Human snapshot tier

Always `source_type=HUMAN_VERIFIED`, `status=FACT`,
`data_classification=REAL_CURRENT` — the one legitimate non-first-party path
to `FACT`, because a human directly observed the primary source. Source:
`human_snapshot.py:74-102`. Full explanation in `evidence-model.md` section 6.

### F8. Human pain points — same pattern

`HUMAN_VERIFIED`; validates category/severity against fixed vocabularies
(`ValueError` on an invalid value, never silently coerced); rejects a missing
opportunity or an opportunity with no linked ASIN; unset optional fields stay
`None`/`[]`, never fabricated.

---

## 4a. Enrichment / normalization (`src/engine/enrichment/normalize.py`) — G1-G5

This is the internal step between a raw discovery-stage provider record and a
structured `asins`/`market_snapshots` row. No Skill calls this directly — it
runs inside `hunt discover`/`hunt <query>` automatically — but its guarantees
are part of what makes discovery-stage evidence trustworthy, so they're
recorded here rather than left undocumented.

- **G1.** `promote_normalized_fields` requires an explicit, valid
  classification (`REAL_CURRENT | REAL_HISTORICAL | ESTIMATE | MOCK |
  UNKNOWN`) — no default; an invalid value raises rather than silently
  defaulting.
- **G2.** Never overwrites an existing structured field with `NULL` — only
  fields actually present in the normalized record are written; a field
  absent from this observation leaves the prior value untouched.
- **G3.** Never writes an all-empty `market_snapshots` row — if price,
  rating, and review_count are all `None`, no row is written at all rather
  than a row full of nulls that could be misread as "checked, found nothing."
- **G4.** Provider-specific normalizers never fabricate an absent field —
  defensive price parsing never defaults to `0`; image/description fallback
  chains resolve to `None` rather than a guessed value; a source format that
  structurally has no brand/category/features field (e.g. a search-results
  row) leaves those fields explicitly `None`, never inferred.
- **G5.** New provider formats are added via one normalizer function + one
  registry entry (`NORMALIZERS` dict) — no schema change required. Not a
  behavioral guarantee a Skill needs to act on, but relevant context if this
  package is ever extended to wrap a new discovery provider.

---

## 5. What this means when reading `hunt discover --with-market-data` output

1. Per-ASIN "live-enrichment call/failure/skip counts" in the printed summary
   are the honest tally — a "failure" is a `ProviderRequestError` (D2) that
   rejected that one opportunity, not a silent zero. A "skip" means the
   candidate never reached the live-enrichment stage (cheap filter already
   rejected it) — not that the provider was tried and came back empty.
2. If the whole `--with-market-data real` attempt hard-stops instead of
   producing any per-ASIN results, that's D3 firing — check `hunt providers`
   for the missing credential/terms-acknowledgment/capability gap before
   trying anything else.
3. Any surviving opportunity's market evidence is capped at `ESTIMATE` unless
   a human later confirms it via `hunt market-snapshot-set` (F6/F7). Don't
   describe automated-provider data as a confirmed fact in any report.

---

## Rule preservation table

| Rule ID | This file's section | Source (Amazon-products file:line) | Test |
|---|---|---|---|
| D1 | 1 | `base.py:36-39,6-11` | provider capability-fence tests (static_dataset, Keepa) |
| D2 | 1 | `base.py:42-45` | `tests/integration/test_run_hunt_provider_failure.py` |
| D3 | 2 | `registry.py:270-307` (and mirrored per provider type) | `test_mock_mode_returns_mock_provider`, `test_real_mode_without_api_key_raises...`, `test_real_mode_never_returns_mock_provider_even_if_something_goes_wrong`, `test_unknown_mode_raises_value_error` |
| D4 | 2 | `registry.py:43-146` | `test_default_config_does_not_acknowledge_logimu_terms` |
| D5 | 3 | `registry.py:270-307` | market-provider selection tests |
| D6 | 3 | `registry.py:335+` | discovery-provider selection tests |
| D7 | 3 | `registry.py:255-268` | review-provider real-mode tests |
| D8 | 3 | `registry.py:189+` | providers-table sync idempotency test |
| D9 | 3 | Keepa/Logimu/DataForSEO provider files (marketplace map) | marketplace-mapping tests |
| G1 | 4a | `enrichment/normalize.py:49,143-161` | `test_promote_normalized_fields_rejects_invalid_classification` |
| G2 | 4a | `enrichment/normalize.py:163-177` | `test_promote_normalized_fields_never_overwrites_existing_with_none` |
| G3 | 4a | `enrichment/normalize.py:179-191` | `test_promote_normalized_fields_no_market_data_writes_no_snapshot` |
| G4 | 4a | `enrichment/normalize.py:68-134` | `tests/unit/test_enrichment_normalize.py` (~10 tests) |
| G5 | 4a | `enrichment/normalize.py:137-140` | (design pattern, not independently tested) |
| F1 | 4 | `market.py` module docstring | (design boundary, advisory) |
| F2 | 4 | `market.py` | market acquisition tests |
| F3 | 4 | `market.py:107` | price-claim FACT tests |
| F4 | 4 | `market.py` (`acquire_market_snapshot`) | market snapshot classification tests |
| F5 | 4 | `market.py` (`acquire_price_history`) | price-history acquisition tests |
| F6 | 4 | `human_snapshot.py:50-72` | human-snapshot empty-observation ValueError test |
| F7 | 4 | `human_snapshot.py:74-102` | human-snapshot FACT/HUMAN_VERIFIED test |
| F8 | 4 | `human_snapshot.py` (pain-point equivalent) | human pain-point validation tests |
