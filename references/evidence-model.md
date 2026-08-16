# Evidence Model

The single source of truth for "what evidence tier does this belong in."
Every other reference and every Skill in this system points here whenever a
claim, a snapshot, a finding, or a piece of research output needs to be
classified. This file describes behavior that already exists and is already
tested in `Amazon-products` — it does not define new rules, it documents the
ones the engine enforces in code.

Nothing in this system may invent a ninth evidence status, a seventh source
type, a new TTL default, or a looser tier "just for this Skill." If a
situation doesn't fit cleanly into what's below, the correct answer is
`UNKNOWN` / `PENDING_HUMAN_REVIEW` / `INSUFFICIENTLY_OBSERVABLE` — never a new
category invented on the spot.

---

## 1. Evidence status taxonomy (A1)

Every piece of evidence and every derived claim carries exactly one
`EvidenceStatus`, from a fixed enum that must never be redefined elsewhere:

| Status | Meaning |
|---|---|
| `FACT` | Directly observed by a first-party source, or by a human/Claude Browser who personally looked at the primary source right now. |
| `ESTIMATE` | Everything else with real data behind it — the ceiling for all automated third-party/licensed providers. |
| `INFERENCE` | Derived by reasoning over other evidence already in this project, not a new observation. |
| `UNKNOWN` | Genuinely not known. Never filled with a plausible-sounding value. |
| `CONTRADICTED` | Two evidence rows disagree; both are preserved, neither is silently discarded. |
| `STALE` | Was current once; TTL has expired, or the source's own self-reported timestamp shows it is not current. |
| `PENDING_HUMAN_REVIEW` | Needs a human look before it can be treated as settled. |
| `INSUFFICIENTLY_OBSERVABLE` | The underlying signal cannot be measured reliably at all (distinct from `UNKNOWN`, which just means "not fetched yet"). |

Source: `taxonomy.py:10-18`.

## 2. Source type taxonomy (A2)

| Source type | Meaning |
|---|---|
| `FIRST_PARTY` | Amazon itself. No provider in this project currently declares this. |
| `LICENSED_THIRD_PARTY` | A paid/credentialed data vendor (Keepa, Logimu, DataForSEO). |
| `EXTERNAL_SOURCE` | Public/free data not licensed specifically to this project (static McAuley-Lab dataset, MockProvider). |
| `LLM_INFERENCE` | Reasoning over evidence already in this project. |
| `HUMAN_VERIFIED` | A human directly observed the primary source themselves (`market-snapshot-set`, `supplier-set`, `voc-add` when a human is relaying their own observation). |
| `EXTERNAL_BROWSER_RESEARCH` | Content an LLM agent with live browser access (Claude Browser) collected from the open web and a human relayed back in. Explicitly distinct from both `HUMAN_VERIFIED` and `LLM_INFERENCE` — never conflated with either, never silently upgraded to `FACT`. |

Source: `taxonomy.py:21-36`.

## 3. The FACT ceiling (A3)

`_default_status(provider)`: a claim is tagged `FACT` **only if**
`provider.source_type == FIRST_PARTY`; every other provider caps at
`ESTIMATE`. Source: `market.py:32-33`.

No automated provider in this project is `FIRST_PARTY` today (Keepa/Logimu =
`LICENSED_THIRD_PARTY`, static_dataset/Mock = `EXTERNAL_SOURCE`) — so
**every automated market snapshot caps at `ESTIMATE`**, no exceptions, until
that changes. The only paths that legitimately reach `FACT` today are the
human-attested ones (section 6 below): a human or Claude Browser looked at
the actual primary source and is reporting what they personally saw.

Test: `test_freshness_status_override_never_upgrades_to_fact_for_non_first_party`.

## 4. Freshness override is downgrade-only (A4)

The freshness-override hook may only move a status *toward* lower confidence,
never toward higher confidence:

```
_ALLOWED_FRESHNESS_OVERRIDES = {ESTIMATE, STALE, UNKNOWN}   # excludes FACT
```

Source: `market.py:27-29,36-40`. This is a hard, immutable rule — nothing in
this Skills package may propose overriding a status up to `FACT`.

Tests: `test_freshness_status_override_downgrades_claim_confidence`,
`test_freshness_status_override_never_upgrades_to_fact_for_non_first_party`,
`test_provider_not_setting_freshness_status_unaffected`.

---

## 5. Truth layer (`src/engine/evidence/truth_layer.py`)

The truth layer is deliberately small and additive to the TTL system in
section 7 below. It answers a different question: not "how old is this since
we fetched it" but "does the source's own self-reported freshness, or a
disagreement between two endpoints of the same source, mean we shouldn't
trust this claim at face value even though our TTL clock hasn't expired yet."

### 5.1 `classify_logimu_freshness` (B1)

Reads a Logimu payload's self-reported timestamp field
(`as_of`/`content_observed_at`/`observed_at`) and returns
`(EvidenceStatus | None, reason)`:

| Condition | Result |
|---|---|
| No timestamp field present | `(None, "no_self_reported_timestamp_present")` — caller must **not** downgrade; absence of freshness evidence is not evidence of staleness |
| Timestamp present but unparseable | `(STALE, "unparseable — treated as low-confidence, not discarded")` |
| Future-dated (`age_hours < 0`) | `(STALE, "...in future...")` |
| `age_hours > max_self_reported_age_hours` (default 72.0h) | `(STALE, "...exceeds threshold...")` |
| Within threshold, `source == "cache"` | `(ESTIMATE, "cache_response_within_threshold...")` |
| Within threshold, live | `(ESTIMATE, "live_response_within_threshold...")` |

`max_self_reported_age_hours` default (72h) deliberately matches
`evidence_ttl_days.price` (3 days) — not a separate number invented for
Logimu, the same conservative window applied project-wide. Config-tunable
via `providers.logimu.max_self_reported_observation_age_hours`.

This rule exists because real validation found Logimu's own `mode=live`
responses ranged from 6 minutes to 38 days of self-reported age, and 13.6% of
`mode=live` calls actually returned `source: "cache"`. Source:
`truth_layer.py:40-98`. Tests: 7 in `test_truth_layer.py`.

### 5.2 `evaluate_price_discrepancy` (B2)

Compares `discovery_price_hint` (e.g. Logimu SERP price) against
`authoritative_price` (e.g. Logimu PRODUCT price). `tolerance_pct` default
**0.05 (5%)**, config `providers.logimu.price_discrepancy_tolerance_pct`.

- Returns a dict, **never raises**:
  `{"conflict": bool, "pct_diff": float | None, "authoritative_price": ..., "discovery_price_hint": ...}`.
- Either input `None`, or `authoritative_price == 0` → `conflict=False, pct_diff=None` (nothing to compare).
- This function only decides whether a disagreement is **worth recording** —
  it never decides which value wins. The authoritative value always wins.

The 5% threshold is empirically grounded: SERP price vs PRODUCT price
disagreed by 5-13x for ~36% of a real comparable sample in validation.
Source: `truth_layer.py:101-132`.

### 5.3 Discrepancy → contradiction recording pipeline (B3)

`acquire_market_snapshot` (`market.py:113-147`): when `evaluate_price_discrepancy`
reports `conflict=true`, the pipeline:

1. Writes a **second** evidence row (`source={provider}_discovery_hint`, `status=CONTRADICTED`).
2. Writes a `price_discovery_hint` claim, also `CONTRADICTED`.
3. Writes a row into `contradictions`.

`market_snapshots.price` is **always** the authoritative value — the hint is
never persisted as price (see also F2). Both sides of the disagreement are
preserved; nothing is silently picked because it "looks better."

---

## 6. Human-attested evidence reaches FACT (F7)

The one legitimate way a non-`FIRST_PARTY` observation reaches `FACT`:
a human (or Claude Browser, when a human is relaying their own direct
observation of a real page) looked at the actual primary source right now.

`record_human_market_snapshot` (`human_snapshot.py`) always writes
`source_type=HUMAN_VERIFIED`, `status=FACT`, `data_classification=REAL_CURRENT`.
Every field the human didn't supply stays `None` — never defaulted, never
inferred from other rows already on the ASIN. An observation with **no**
field set at all raises `ValueError` rather than recording an empty snapshot
(F6). See `references/human-input-protocol.md` for exactly which `hunt`
command to use and when.

`EXTERNAL_BROWSER_RESEARCH` (Claude Browser research a human did **not**
personally verify against the primary source, just relayed) is a **different,
lower tier**, capped at `ESTIMATE` (see section 8 and I1 in
`provider-capability.md`). Do not confuse the two: "a human told Claude what
they personally saw" is `HUMAN_VERIFIED`/`FACT`; "Claude Browser read pages
on the open web and reported back" is `EXTERNAL_BROWSER_RESEARCH`/`ESTIMATE`,
even if a human copy-pasted the result in.

---

## 7. Freshness / TTL (`src/engine/evidence/freshness.py`)

### 7.1 `is_stale` (C1)

```
ttl_days is None  →  never stale (immutable point-in-time record)
else stale when  now >= retrieved_at + timedelta(days=ttl_days)
```

`retrieved_at` is always **our own fetch time** (set at insert), never a
provider's self-reported timestamp — that's what section 5's truth layer
exists to additionally check. Source: `freshness.py:12-24`.

### 7.2 `effective_status` (C2)

Read-time-only override to `STALE` when `is_stale` is true — does **not**
mutate the stored row. Persisting a staleness transition is a separate,
explicit write (`mark_evidence_status`), so staleness detection stays a pure
read-time check. Source: `freshness.py:27-36`.

### 7.3 TTL defaults (C3)

From `config/default.yaml` `evidence_ttl_days` — documented starting
defaults, not guesswork, adjustable per observed provider update cadence.
**No TTL is ever hardcoded in Python.**

| Data type | TTL (days) |
|---|---|
| `price` | 3 |
| `bsr` | 3 |
| `offers` | 3 |
| `reviews` | 30 |
| `review_text_corpus` | 30 |
| `keyword_volume` | 60 |
| `supplier_quote` | 90 |
| `ip_compliance_review` | 180 |
| `external_research_note` | 180 |
| `historical_snapshot` | `null` — never expires (point-in-time record, not a current claim) |

### 7.4 Raw evidence immutability + content addressing (C4)

`store_raw_evidence` writes `data/raw/<source>/<sha256>.json`. A file with the
same hash is **left untouched** (idempotent, never overwritten). A genuinely
new observation produces a new file + new hash; history is chained via
`supersedes_evidence_id` in the database, never by mutating a file in place.
`verify_raw_evidence` recomputes the SHA-256 to detect tampering. Source:
`raw_store.py:45-68`.

### 7.5 Source-identifier validation (C5)

`store_raw_evidence` rejects any `source` string containing `/`, `\`, `.`, or
`..` — a path-traversal defense. Source: `raw_store.py:52-53`.

### 7.6 Deterministic canonical serialization (C6)

`_canonical_bytes`: `json.dumps(payload, sort_keys=True, ensure_ascii=False, default=str)`
— identical payloads hash identically regardless of key order. Source:
`raw_store.py:39-42`.

---

## 8. Quick decision guide

When you (as a Skill) need to classify a piece of evidence, ask in order:

1. Did I (Claude) or the human directly look at the actual primary source
   (the real Amazon listing, the real supplier email, the real Google Trends
   export) right now? → `HUMAN_VERIFIED` / `FACT` (record via the matching
   `hunt ...-set` command — see `human-input-protocol.md`).
2. Did an automated `hunt` provider fetch this? → whatever status the engine
   itself assigned (never re-classify it yourself) — capped at `ESTIMATE`
   unless a future `FIRST_PARTY` provider exists.
3. Did Claude Browser read open-web pages and a human relayed the results
   in? → `EXTERNAL_BROWSER_RESEARCH` / `ESTIMATE`, via `hunt browser-evidence-add`.
4. Is the field simply not known? → `UNKNOWN`. Never fill it with a guess.
5. Do two sources disagree? → preserve both, let the engine's contradiction
   mechanism (section 5.3) record it. Never quietly pick the flattering one.

---

## Rule preservation table

| Rule ID | This file's section | Source (Amazon-products file:line) | Test |
|---|---|---|---|
| A1 | 1 | `taxonomy.py:10-18` | (vocabulary — cross-checked by every status-touching test) |
| A2 | 2 | `taxonomy.py:21-36` | `test_record_external_evidence_pack_uses_estimate_never_fact` |
| A3 | 3 | `market.py:32-33` | `test_freshness_status_override_never_upgrades_to_fact_for_non_first_party` |
| A4 | 4 | `market.py:27-29,36-40` | `test_freshness_status_override_downgrades_claim_confidence`, `test_freshness_status_override_never_upgrades_to_fact_for_non_first_party`, `test_provider_not_setting_freshness_status_unaffected` |
| B1 | 5.1 | `truth_layer.py:40-98` | 7 tests in `test_truth_layer.py` |
| B2 | 5.2 | `truth_layer.py:101-132` | `test_truth_layer.py` |
| B3 | 5.3 | `market.py:113-147` | market acquisition contradiction tests (authoritative-wins assertions) |
| F6 | 6 | `human_snapshot.py:50-52,68-72` | human-snapshot ValueError-on-empty test |
| F7 | 6 | `human_snapshot.py:74-86` | human-snapshot FACT/HUMAN_VERIFIED assertion test |
| I1 | 6, 8 | `ingest.py:34-43` | `test_record_external_evidence_pack_uses_estimate_never_fact` |
| C1 | 7.1 | `freshness.py:12-24` | freshness unit tests |
| C2 | 7.2 | `freshness.py:27-36` | freshness unit tests |
| C3 | 7.3 | `config/default.yaml:32-45` | (config value — read directly, not hardcoded) |
| C4 | 7.4 | `raw_store.py:45-68` | raw-evidence immutability/idempotency tests |
| C5 | 7.5 | `raw_store.py:52-53` | path-traversal defense test |
| C6 | 7.6 | `raw_store.py:39-42` | canonical-serialization hash-stability test |
