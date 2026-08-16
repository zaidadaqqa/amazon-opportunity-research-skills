---
name: amazon-validation
description: Use when interpreting live-validation results for discovered candidates (RUN_MODE=REAL behavior, provider failures, evidence freshness/staleness) or when deciding whether to trust/re-verify a market snapshot before it feeds ranking. Use after amazon-discovery, before competition-analysis.
---

# Amazon Validation

This Skill does not fetch any new data itself. It teaches you how to
correctly read what `hunt discover --with-market-data` and
`hunt show <opportunity_id>` already produced, so evidence isn't
over-trusted, under-trusted, or silently reclassified in your report.

Full rule detail lives in `references/evidence-model.md` (what tier is what)
and `references/validation.md` (what can go wrong with a live provider call
and how the engine already handles it). This file is the operational
checklist for using those two together.

## 0. Before touching any real-mode command

Run `hunt providers`. It shows, per provider, exactly which of the two
gating conditions (credential present, `terms_acknowledged`/
`license_acknowledged` set) is missing — see `validation.md` section 2 (D3,
D4). Never guess whether a provider is usable; always check this first.

## 1. Reading `hunt discover --with-market-data <mode>` output

The printed summary includes live-enrichment call/failure/skip counts. Read
them literally:

- **call** = a live provider attempt was made and returned data.
- **failure** = `ProviderRequestError` fired (`validation.md` D2) — that
  specific opportunity was **not evaluated**, not "found to be weak." Report
  it as "validation attempt failed," never as a rejected candidate on the
  merits.
- **skip** = the candidate never reached live enrichment (cheap filter
  already eliminated it before spending a provider call) — not "provider
  tried and found nothing."

If the entire `--with-market-data real` attempt hard-stops instead of
producing per-ASIN results, that is `RealDataProviderRequired` firing
(`validation.md` D3) — the single most safety-critical rule in this domain:
**the engine never silently substitutes mock data for a failed real
request.** Go back to `hunt providers`, resolve the actual gap, or get
explicit human sign-off to proceed on `--mode mock` instead. Never interpret
the hard-stop as "proceed with mock data" on your own.

## 2. Reading `hunt show <opportunity_id>` evidence sections

For every evidence-bearing field, identify its state using
`evidence-model.md`:

| You see | It means | What to say in a report |
|---|---|---|
| `status=FACT`, `source_type=HUMAN_VERIFIED` | A human or Claude Browser directly observed the real listing right now | Trustworthy current fact |
| `status=ESTIMATE` (any automated provider) | Ceiling for every current automated provider (A3) — no `FIRST_PARTY` source exists yet | Real data, but not to be reported as a guaranteed-current fact |
| `status=STALE` | TTL expired (C1/C2) or the source's own self-reported freshness failed `classify_logimu_freshness` (B1) | Do not use as current evidence for ranking without re-verifying |
| `status=CONTRADICTED` | Two sources disagree (B3) — both preserved | Report both values, never silently pick the flattering one |
| `status=UNKNOWN` | Genuinely not fetched/known | Say `UNKNOWN`, never fill a plausible number |

Do not read `data_classification=REAL_CURRENT` as a trust signal by itself —
it reflects *provenance* (came from a live-snapshot code path), not
confidence; a `STALE`-status snapshot can still show `REAL_CURRENT` here
(`validation.md` F4). Always check `status`, not `data_classification`, when
deciding whether to trust a number.

## 3. When to fall back to `hunt market-snapshot-set`

Use it (see `references/human-input-protocol.md` section 1) when either:

1. No live `MarketDataProvider` is configured/usable for this run (confirmed
   via `hunt providers`), so the candidate has no current market evidence at
   all, or
2. A provider capability gap from `provider-capability.md` applies — e.g. you
   need a leaf-level current fact but the static dataset only has
   parent-level historical data (E15), or the only live snapshot available is
   a Logimu SERP price hint that never became authoritative (E5).

Only record values a human stated or that Claude Browser directly observed
on the real page right now — never a value Claude itself estimated. This
produces `HUMAN_VERIFIED`/`FACT` evidence (F6/F7) — the highest tier in the
system, so it must never be filled with an invented number.

## 4. The RUN_MODE=REAL hard-stop, explicitly

If a human requested a real-mode run and it failed (`RealDataProviderRequired`,
`ReviewCapabilityUnavailable`, or any other real-mode hard-stop):

- **Never** silently continue the workflow on mock data and present the
  result as if it came from real validation.
- **Never** reinterpret the failure as "no market for this product."
- Surface the exact failure and the specific missing precondition (from
  `hunt providers`), and let the human decide whether to fix the
  credential/terms gap, accept a provider capability gap (`provider-capability.md`),
  or explicitly choose to proceed on mock/human-supplied data instead.

## 5. Next step

Once evidence has been correctly classified (and any needed
`market-snapshot-set` calls made), proceed to competitor autopsy
(`hunt deepen-start`) — see `cli-command-reference.md`. Only candidates that
reach `COMPETITOR_ANALYSIS` become eligible for `browser-research`
(`skills/browser-research/SKILL.md`).

## Cross-references

- `references/evidence-model.md` — evidence status/source-type taxonomy, TTLs.
- `references/validation.md` — provider abstraction, RUN_MODE=REAL guard, fallback hierarchies, acquisition-layer rules.
- `references/provider-capability.md` — exact capability gaps per provider.
- `references/human-input-protocol.md` — when/how to record human-supplied evidence.
