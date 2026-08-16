# Human Input Protocol

This file explains **when** and **how** a Skill should ask a human for data,
and which `hunt` command to use for which kind of input. It is a protocol
document, not a rule table — but every rule it invokes is defined precisely
in `evidence-model.md` (F6-F8) and traced back to source here.

## The single most important rule in this file

Every command listed below persists its input at `HUMAN_VERIFIED`/`FACT`
tier (or, for `voc-add`/`browser-evidence-add`, at a tier that downstream
gates treat as trustworthy human/observed input). **Never invoke any of these
commands with a value Claude itself invented, estimated, or inferred.** Only
use them with:

- a value a human explicitly typed/stated to Claude, or
- a value Claude Browser directly observed on a real, currently-open page
  (a live look at the actual Amazon listing, the actual supplier email
  thread, the actual Google Trends export) — **not** a value recalled,
  paraphrased from memory, or inferred from a general sense of "typical"
  numbers for this kind of product.

If neither condition holds, the correct action is to say so and leave the
field `UNKNOWN` — never to fill it in "to be helpful." This is the same
anti-hallucination contract as `core-rules.md`, applied specifically to the
commands that write `FACT`-tier evidence.

---

## Decision tree: which command do I need?

```
Do I need to record...

 → a market fact about the actual current listing (price, rating,
   review_count, BSR, buybox price, in-stock)?
      no live provider is configured, OR I need to confirm/correct
      a live snapshot the engine already recorded
      ──► hunt market-snapshot-set   (section 1)

 → cost/price assumptions to run the economics calculator
   (selling price, unit cost, fees, shipping, PPC, etc.)?
      ──► hunt economics-set         (section 2)

 → a supplier/IP validation finding — the ONLY way to move those
   two hard gates off UNKNOWN?
      ──► hunt supplier-set          (section 3)

 → one specific customer complaint or praise point I (a human) or
   Claude Browser found, tied to a real source?
      ──► hunt voc-add               (section 4, and see
          browser-research SKILL.md for the browser-sourced case)

 → a whole Claude Browser research pack (multi-section findings,
   not a human's own direct observation)?
      ──► hunt browser-evidence-add  — NOT covered by this file's
          HUMAN_VERIFIED tier; see provider-capability.md and
          skills/browser-research/SKILL.md. This is a DIFFERENT,
          lower tier (EXTERNAL_BROWSER_RESEARCH, capped ESTIMATE).
```

---

## 1. `hunt market-snapshot-set` — market facts

**When to use it:**
- No live `MarketDataProvider` is configured/credentialed for this run
  (check `hunt providers` first — see `validation.md` section 2), so the
  candidate has no current price/BSR/rating/review evidence at all, or
- A live snapshot the engine already recorded needs to be **confirmed or
  corrected** by a human/Claude Browser who looked at the real listing right
  now (e.g. the automated snapshot is `STALE`, or looks suspicious).

**What it requires:** at least one of `price | rating | review_count | bsr |
buybox_price | in_stock` — F6 in `evidence-model.md`/`validation.md`:
`HumanMarketObservation.has_any_observed_value()` must be true or the command
raises `ValueError`. There is no bulk entry point on purpose — one
opportunity at a time, for the small surviving cohort after cheap filtering,
not the full discovery funnel.

**What it produces:** a `market_snapshots` row identical in shape to a live
provider's, tagged `source_type=HUMAN_VERIFIED`, `status=FACT`,
`data_classification=REAL_CURRENT` — F7. Every field left unset stays `None`,
never defaulted or inferred from other rows already on the ASIN.

**Never:** invent a price/rating/BSR number because "it's probably around
that" — if you (Claude, without live browser access) don't have a verified
figure, leave it unset and let the field stay `UNKNOWN` per the engine's own
handling. Only Claude Browser genuinely looking at the live listing, or the
human directly, may supply these values.

## 2. `hunt economics-set` — cost/price assumptions

**When to use it:** a human has supplied real cost/price assumptions
(selling price, unit cost, freight, fees, etc.) for the economics calculator
to run against. This command **immediately computes** economics + 5 stress
scenarios via the unmodified deterministic calculator — never something a
Skill reasons about in natural language (rule 4 in `core-rules.md`).

**Never:** propose plausible-sounding cost figures yourself and pass them
through as if the human said them. If the human hasn't supplied real numbers
yet, say so and wait — do not estimate "typical Amazon FBA costs" and treat
that as input.

## 3. `hunt supplier-set` — supplier/IP validation

**When to use it:** a human has performed real supplier/IP validation work
(contacted a supplier, got a quote, had legal/IP review done) and is ready to
record the result.

**Why this one matters most:** per `core-rules.md` rule 1 and the project's
hard-gate design, `supplier-set` is **the only thing that can move the
supplier/IP hard gates off permanent `UNKNOWN`.** No pipeline stage infers
`supplier_status` or `ip_status` from anything else. Valid values:
`--supplier-status UNKNOWN|MANUAL_SOURCING_REQUIRED|VALIDATED|CONFIRMED_IMPOSSIBLE`,
`--ip-status UNKNOWN|PENDING_HUMAN_LEGAL_REVIEW|CLEARED_BY_HUMAN|CONFIRMED_BLOCKER`
(both default `UNKNOWN` if never set). Invalid values raise immediately —
never silently coerced.

**Never:** set `VALIDATED` or `CLEARED_BY_HUMAN` because research "didn't
find any obvious problems" — absence of a found problem is not clearance.
Browser research findings about IP/compliance risk are informative input
*to* a human's legal review, never a substitute for it (see
`skills/amazon-validation/SKILL.md` and the project's IP/Compliance
governing principle: use `PENDING_HUMAN_LEGAL_REVIEW` whenever meaningful
verification is incomplete).

## 4. `hunt voc-add` — one specific finding

**When to use it:** recording one human/browser-observed VOC finding
directly, without a full batch review-analysis run. `--category` one of
`product|packaging|shipping|expectation_mismatch|misuse|isolated`;
`--severity LOW|MEDIUM|HIGH`; `--frequency-signal
ISOLATED|RECURRING|DOMINANT`; `--solvability EASY|MODERATE|HARD|UNKNOWN`, all
optional. This extends the **same** `pain_points` table automated
`voc-submit` uses — not a second, competing VOC model.

**Who can call it, at what tier:**
- A human directly relaying their own observation (e.g. they personally read
  a review) → this is the `HUMAN_VERIFIED` path this file is about.
- Claude Browser research findings, packaged and ingested via
  `hunt browser-evidence-add`, also populate `pain_points` automatically for
  every **traceable** finding (real `source_urls`) — see F8/I2 and
  `skills/browser-research/SKILL.md`. Do not manually re-type Claude
  Browser's findings into `voc-add` as if they were a human's own
  observation; that would mislabel the evidence tier. Use
  `browser-evidence-add` for the whole pack instead.

**Never:** record a frequency-signal of `RECURRING` or `DOMINANT` from a
single observation — that's the exact distinction the `--frequency-signal`
vocabulary exists to prevent collapsing (see I2 and the browser brief's own
`PATTERN_STRENGTHS` distinction in `provider-capability.md`/`brief.py`).

---

## Underlying config/secrets rules that govern all of the above (H1-H6)

- **H1.** No hardcoded business thresholds in Python — every threshold used
  by these commands (TTLs, tolerance percentages, gate values) comes from
  `config/default.yaml` or `config/local.yaml`. Enforced by convention.
- **H2.** `null` in YAML config stays `None` in Python — meaning `UNKNOWN` —
  never silently defaulted to zero.
- **H3.** `config/local.yaml` deep-merges over `default.yaml` and is
  gitignored — the **only** place `terms_acknowledged`/`license_acknowledged`
  may be flipped to `true`. Test: `test_gitignore_excludes_local_config`.
- **H4.** The `.env` loader (`env.py`) never overwrites a variable already
  present in the real shell environment (`os.environ.setdefault`) — an
  explicit shell `export` always wins. A malformed line (no `=`) raises
  `ValueError` rather than being silently skipped, since silently skipping
  could hide a credential that then never actually loads. A missing `.env`
  file is a no-op. Idempotent for the default path.
- **H5.** Secret values (API keys) are never logged, printed, or returned by
  any command in this system. Cross-checked by
  `test_no_leaked_secrets.py::test_no_live_api_key_literal_in_tracked_files`,
  which greps every git-tracked file for `sk_live_`-style literals;
  `.env.example` ships its key line literally blank.
- **H6.** `load_config()` is `@lru_cache(maxsize=1)` — loaded once per
  process. A Skill that just guided a human through editing `local.yaml`
  (e.g. to acknowledge terms) must account for this: changes won't be picked
  up mid-process without restarting the `hunt` process/CLI invocation.

None of H1-H6 are commands you call directly — they are constraints on how
the config/secrets a human supplies (including for the commands above) are
handled safely. Surface them to a human when relevant (e.g. "you'll need to
restart for that local.yaml change to take effect" — H6), never route around
them.

---

## Rule preservation table

| Rule ID | This file's section | Source (Amazon-products file:line) | Test |
|---|---|---|---|
| F6 | 1 | `human_snapshot.py:50-72` | human-snapshot empty-observation ValueError test |
| F7 | 1 | `human_snapshot.py:74-102` | human-snapshot FACT/HUMAN_VERIFIED test |
| F8 | 4 | `human_snapshot.py` (pain-point equivalent) / `reviews.py` (`insert_pain_point`) | human pain-point validation tests |
| I2 | 4 | `ingest.py:21-25,45-64` | `_PATTERN_TO_FREQUENCY` traceable-only-VOC tests |
| H1 | Config/secrets | `config/loader.py` module docstring | (convention, not mechanically enforced) |
| H2 | Config/secrets | `config/loader.py` (YAML `null` handling) | config-loading unit tests |
| H3 | Config/secrets | `config/loader.py:19,28-49` | `test_gitignore_excludes_local_config` |
| H4 | Config/secrets | `env.py:27-64` | `.env` loader tests (setdefault precedence, malformed-line ValueError) |
| H5 | Config/secrets | (cross-cutting — no single file) | `test_no_leaked_secrets.py::test_no_live_api_key_literal_in_tracked_files` |
| H6 | Config/secrets | `config/loader.py:38-39` (`@lru_cache(maxsize=1)`) | config caching behavior (documented gotcha) |
