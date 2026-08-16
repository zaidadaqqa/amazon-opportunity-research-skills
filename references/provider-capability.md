# Provider Capability Gaps

This file is the bridge between the deterministic engine and the
`browser-research` Skill. It documents, precisely, what the real-mode
providers already wired into `Amazon-products` **cannot give you** — not
because of a bug, but because of a genuine, verified, structural limitation
of that data source. These are the exact gaps Claude Browser research exists
to fill (`references/human-input-protocol.md` and
`skills/browser-research/SKILL.md` explain how).

Nothing here is a request to route around a provider's limitation by
guessing, scraping Amazon directly, or inventing a number that "seems close
enough." Every gap below has exactly one sanctioned way to fill it: either a
human-supplied command (`hunt market-snapshot-set` / `hunt supplier-set` /
`hunt voc-add`, see `human-input-protocol.md`) or Claude Browser research
recorded at its own tier (`hunt browser-evidence-add`, capped `ESTIMATE`,
see `evidence-model.md` section 2 and 6).

---

## 1. Keepa

| Rule | Gap | Implication |
|---|---|---|
| **E1** | Declares only `{PRICE_SNAPSHOT, BSR_SNAPSHOT, PRICE_HISTORY, BSR_HISTORY, OFFERS_SNAPSHOT}`. No `REVIEWS` capability. `discover_candidates` always raises `CapabilityNotSupported`. | Keepa can never be used for free-text discovery, and never returns review text at all — not truncated, not summarized, simply absent. |
| **E2** | Negative CSV values (`-1`, Keepa's own "no data" sentinel) are parsed to `None`, never coerced to `0`. | A `0` you see from Keepa data is a real zero, not a missing value in disguise. |
| **E3** | `monthlySold` is always tagged `THIRD_PARTY_ESTIMATE` — stricter than Keepa's own framing (Keepa itself doesn't call it an estimate; this project forces the tag anyway). | Never report Keepa's `monthlySold` as a verified sales figure. |
| **E4** | No interpolation between history points — a field is populated only when that exact series reported a value at that exact timestamp. | Gaps in a BSR/price history chart are real gaps, not smoothed over. |

**Capability gap for browser research:** Keepa gives no customer-voice signal
at all (no review text) and cannot discover new candidates by concept — both
are exactly what web/Reddit/forum research can add, at `ESTIMATE` tier.

## 2. Logimu

| Rule | Gap | Implication |
|---|---|---|
| **E5** | `/v1/product?mode=live` is authoritative; `/v1/serp` price is only a `discovery_price_hint`, classification always `ESTIMATE`, never `REAL_CURRENT`. Empirically, SERP vs PRODUCT price disagreed by 5-13x for ~36% of a real comparable sample. | Never treat a SERP-stage price as the current price — see `evidence-model.md` B2/B3 for how the engine records (not resolves) this disagreement. |
| **E6** | `sales_estimate` is never populated — validated absent in 100% of ~120 real ASIN attempts across 3 rounds; hardcoded `None`. | Logimu is not a sales-estimate source, full stop — do not expect this field to ever appear. |
| **E7** | Retry policy: `_RETRYABLE_STATUS_CODES={429,500,502,503,504}`, linear backoff + up to 25% jitter, bounded by `max_retries` (default 3); `404` is returned as-is (never retried); exhausted retries raise `ProviderRequestError` with no request internals in the message. | A `ProviderRequestError` from Logimu already represents real retry exhaustion — don't retry it again yourself; treat it as D2 in `validation.md`. |
| **E8** | API key is sent only as the `X-API-KEY` header; exceptions are built from static text + non-secret fields only. | Never expect or ask for the raw key to appear in any Logimu error text or log. |
| **E9** | A McAuley-Lab category string is never passed as Logimu's `category_id` param (different namespace) — folded into the free-text query instead. | If a discovery query looks odd/broad, this is why — it's intentional, not a bug to "fix" by passing the raw category id. |
| **E10** | Sponsored results are always excluded from Logimu discovery output. | Ranking/competition signal from Logimu discovery never includes paid placements. |
| **E11** | Discovery pagination bound: `discovery_max_pages` default 3 (lowered from 5 after an observed all-or-nothing multi-page failure). | Logimu discovery is intentionally shallow — don't expect exhaustive category coverage from it; that's what the static dataset (below) is for at bulk scale. |

**Capability gap for browser research:** Logimu never gives review text or a
trustworthy sales estimate; its SERP price is explicitly a hint, not a fact.
Browser research on the actual listing/competitor sites is the way to get
real customer language and cross-check price sanity beyond the 5% tolerance
band.

## 3. DataForSEO

| Rule | Gap | Implication |
|---|---|---|
| **E12** | `search_volume: null` is preserved as `None`, never coerced to `0`. | A `0` search volume from DataForSEO is a real reported zero, not "we don't know." |
| **E13** | Every non-2xx / non-`20000` envelope raises `ProviderRequestError` (HTTP 401, non-200, non-JSON body, top-level `status_code != 20000`, empty `tasks`, task `status_code` not in `(20000, 20100)`). | DataForSEO failures are never silently swallowed into an empty keyword list. |
| **E14** | The paid Amazon Labs endpoint is never called without explicit opt-in: `check_amazon_labs_reachable(confirm_spend)` returns `{"checked": False, "reachable": None}` unless `confirm_spend=True` is explicitly passed (CLI requires `--confirm-spend`). `run_connection_test` only attempts the paid check if the free auth check already succeeded. | No Skill may pass `--confirm-spend` on a human's behalf — spending real money (even ~$0.012) always requires a live human decision at that moment. |

**Capability gap for browser research:** DataForSEO gives keyword volume, not
qualitative demand context (why people search, what alternatives they
consider) — that's a genuine gap browser research can help characterize,
always at `ESTIMATE`, never presented as a volume number.

## 4. Static dataset (McAuley-Lab, `static_dataset`)

| Rule | Gap | Implication |
|---|---|---|
| **E15** | Parent-level identifier only, never treated as a leaf ASIN — no `asin` field exists in McAuley-Lab metadata, only `parent_asin`; `is_parent_asin=True` always. Schema has a dedicated `asins.identity_level` column for this. | Every static-dataset candidate is a parent-level record; do not report it as a specific buyable child ASIN/variant. |
| **E16** | Bounded byte-capped scan (`scan_cap_bytes` default 50MiB); `scan_truncated=True` set whenever the cap is hit, on every candidate's raw record for that scan. | A static-dataset discovery run is never presented as exhaustive when truncated — check `scan_truncated` before claiming full category coverage. |
| **E17** | Cache correctness under differing cap sizes: a cache written under a smaller, non-complete cap does not satisfy a later larger-cap request (re-fetched). The dataset itself is immutable/frozen, so a genuinely complete cache hit never goes stale. | Re-running discovery with a larger `--max-candidates` after a truncated run correctly re-scans rather than silently reusing the truncated cache. |
| **E18** | Explicit category required, never guessed: raises `ValueError` if category is `None` or not one of the 33 verified `CATEGORY_NAMES`. `guess_category()` is explicitly best-effort and returns `None` rather than a wrong guess. | `hunt discover --category` is required in `--mode real` — never let a Skill silently pick a category on the human's behalf; surface `guess_category()`'s hint but require confirmation. |
| **E19** | Malformed JSONL lines are skipped, never fabricated — records missing `parent_asin`/`title` are dropped; deduped by `parent_asin` within a scan. | A lower-than-expected candidate count from the static dataset can legitimately be data quality, not a bug. |

**Capability gap for browser research:** the static dataset is historical and
frozen — it has no current price/BSR/review signal at all by design (that's
what `--with-market-data` or a human snapshot is for), and no per-ASIN
identity below the parent level. Browser research on the live listing is the
only way to get current, leaf-level facts from this starting point.

---

## Capability gap summary — what browser research exists to fill

| Gap | No real provider gives this because | Sanctioned fill |
|---|---|---|
| Customer review text / sentiment | Keepa has no REVIEWS capability (E1); no live review-text API exists anywhere in this project (D7 in `validation.md`) | `hunt browser-research` → `hunt voc-add` / `hunt browser-evidence-add` |
| Free-text discovery from Keepa | E1 — Keepa always raises `CapabilityNotSupported` for `discover_candidates` | Static dataset discovery (`hunt discover`) or Logimu SERP (bounded, E11) |
| Verified sales/units figures | E3 (Keepa `monthlySold` forced to `THIRD_PARTY_ESTIMATE`), E6 (Logimu `sales_estimate` never populated), J1 in the rule inventory (BSR is never a sales figure) | Never fully fillable — report as `UNKNOWN`/estimate range, never a hard number, regardless of research depth |
| Current leaf-level price/BSR when no live provider configured | Static dataset is frozen/historical (no live signal at all) | `hunt market-snapshot-set` (human/Claude Browser directly observed the real listing) |
| Non-Amazon market context, competitor DTC sites, alternatives | No provider here looks outside Amazon-adjacent data at all | `hunt browser-research` (external competition, alternatives sections of the Evidence Pack) |
| Regulatory/IP signals | No provider does IP/compliance research | `hunt supplier-set --ip-status` after human legal review, optionally informed by browser research findings (still `PENDING_HUMAN_LEGAL_REVIEW` until a human clears it) |

---

## Rule preservation table

| Rule ID | This file's section | Source (Amazon-products file:line) | Test |
|---|---|---|---|
| E1 | 1 | Keepa provider (capability declaration) | Keepa capability-fence tests |
| E2 | 1 | Keepa provider `_parse_series` | Keepa negative-value parsing test |
| E3 | 1 | Keepa provider (`monthlySold` tagging) | Keepa third-party-estimate tagging test |
| E4 | 1 | Keepa provider (history parsing) | Keepa no-interpolation test |
| E5 | 2 | Logimu provider (SERP vs PRODUCT) | Logimu price-hint classification tests |
| E6 | 2 | Logimu provider (`sales_estimate`) | Logimu sales-estimate-always-None test |
| E7 | 2 | Logimu provider retry logic | Logimu retry/backoff tests |
| E8 | 2 | Logimu provider (`X-API-KEY` header) | 3 dedicated key-leak tests |
| E9 | 2 | Logimu provider (category folding) | Logimu category-namespace test |
| E10 | 2 | Logimu provider (sponsored exclusion) | Logimu discovery sponsored-exclusion test |
| E11 | 2 | Logimu provider (`discovery_max_pages`) | Logimu pagination bound test |
| E12 | 3 | DataForSEO provider (`search_volume`) | DataForSEO null-preservation test |
| E13 | 3 | DataForSEO provider (error envelope checks) | DataForSEO error-propagation tests |
| E14 | 3 | `dataforseo_diagnostics.py` (`check_amazon_labs_reachable`) | `hunt dataforseo-check --confirm-spend` opt-in test |
| E15 | 4 | Static dataset provider (`identity_level`) | static-dataset parent-ASIN-only test |
| E16 | 4 | Static dataset provider (`scan_cap_bytes`) | static-dataset truncation-disclosure test |
| E17 | 4 | Static dataset provider (cache-cap correctness) | static-dataset cache-cap tests |
| E18 | 4 | Static dataset provider (`CATEGORY_NAMES`, `guess_category`) | static-dataset explicit-category ValueError test |
| E19 | 4 | Static dataset provider (JSONL parsing) | static-dataset malformed-line-skip test |
