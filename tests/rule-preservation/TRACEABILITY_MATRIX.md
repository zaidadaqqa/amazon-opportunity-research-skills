# Rule-Preservation Traceability Matrix

Every rule extracted from the source engine (`Amazon-products`, 2026-08-16
extraction pass, ~215 rules across 4 domain inventories) is listed here with
its destination in this package. "Destination" means: which `references/*.md`
file documents the rule for a Skill to read, and/or which `skills/*/SKILL.md`
operationalizes it. Detailed per-rule tables (source file:line, exact test
name) live in each destination reference file's own "Rule preservation"
section — this matrix is the top-level index proving *no rule was dropped*,
not a re-statement of every detail.

Full per-rule detail (source file:line, test name, hard/advisory,
immutability) for each domain's raw extraction remains available at:
`/tmp/claude-1000/-home-zaid-Desktop-Amazon-products/679ada2e-a54b-4569-aab0-825a95452845/scratchpad/rule_inventory_*.md`
(session-local scratch; the per-file "Rule preservation" tables in this
package are the durable copy).

## Domain 1: Discovery, Relevance, Demand Intelligence (~75 rules)

| Rule ID range | Count | Destination |
|---|---|---|
| REL-01 .. REL-09 | 9 | `references/relevance-and-filtering.md` |
| ELIG-01 .. ELIG-04 | 4 | `references/relevance-and-filtering.md` |
| PROV-01 .. PROV-04 | 4 | `references/amazon-discovery.md` |
| STAGE-01 .. STAGE-18 | 18 | `references/amazon-discovery.md` |
| DEM-01 .. DEM-12 | 12 | `references/demand-intelligence.md` |
| SVC-01 .. SVC-13 | 13 | `references/demand-intelligence.md` |
| CSV-01 .. CSV-06 | 6 | `references/demand-intelligence.md`, workflow context in `references/google-trends-protocol.md` |

Skills operationalizing this domain: `skills/amazon-discovery/SKILL.md`,
`skills/demand-intelligence/SKILL.md`.

## Domain 2: Evidence Model, Providers, Validation (~65 rules + 5 patched)

| Rule ID range | Count | Destination |
|---|---|---|
| A1 .. A4 (evidence taxonomy, FACT ceiling) | 4 | `references/evidence-model.md`, restated in `references/core-rules.md` rule #5 |
| B1 .. B3 (truth layer) | 3 | `references/evidence-model.md` |
| C1 .. C6 (freshness/TTL, raw immutability) | 6 | `references/evidence-model.md` |
| D1 .. D9 (provider abstraction, RUN_MODE=REAL) | 9 | `references/validation.md`, restated in `references/core-rules.md` rule #3 |
| E1 .. E19 (provider-specific capability limits) | 19 | `references/provider-capability.md` |
| F1 .. F8 (acquisition layer, human-attested evidence) | 8 | `references/validation.md`, `references/human-input-protocol.md` |
| G1 .. G5 (enrichment/normalization) | 5 | `references/validation.md` §4a (patched post-review — see note below) |
| H1 .. H6 (config/secrets) | 6 | `references/human-input-protocol.md` |
| I1 .. I5 (external browser research) | 5 | `references/browser-research-protocol.md`, `skills/browser-research/SKILL.md`, ESTIMATE-cap restated in `references/core-rules.md` rule #5 |
| J1 .. J2 (cross-cutting: BSR≠sales, PENDING_HUMAN_LEGAL_REVIEW) | 2 | `references/provider-capability.md`, `references/supplier-ip.md` |

Skills operationalizing this domain: `skills/amazon-validation/SKILL.md`,
`skills/browser-research/SKILL.md`.

**QA note:** the initial build pass by the domain-2 writing agent covered
A-F, H, I but omitted G1-G5 (enrichment/normalization). This was caught during
post-build review (`grep` for enrichment coverage returned only passing
mentions, no dedicated section) and patched directly into
`references/validation.md` §4a with its own rule-preservation table rows. This
is disclosed rather than silently fixed, per the mission's own instruction not
to claim 100% preservation without the evidence supporting it — the gap
existed for one review cycle and is now closed.

## Domain 3: Competition, Lineage, VOC, Differentiation, Red Team (~35 rules)

| Rule ID range | Count | Destination |
|---|---|---|
| Competitor autopsy (parent-dedup, concentration formulas, sample gate) | 7 | `references/competition.md` |
| Lineage/contamination (never-auto-confirm, 2 heuristics, UNKNOWN-when-thin) | 4 | `references/competition.md` |
| Hard gates (CONFIRMED-only, config-driven, AND-of-enabled) — cross-extracted independently by both domain-3 and domain-4 agents | 3 | Canonical: `references/decision-gates.md`; contextual restatement in `references/competition.md` for lineage interpretation |
| VOC (evidence-anchoring, pain-point vocabulary, manual-completion) | 6 | `references/voc.md` |
| Differentiation (default-low-resistance, evidence-downgrade, LLM-failure) | 3 | `references/differentiation.md` |
| Red team (EVIDENCED-vs-HYPOTHESIS, scope checklist) | 2 | `references/red-team.md` |
| Ranking/Pareto — cross-extracted independently by both domain-3 and domain-4 agents | 6 | Canonical: `references/decision-gates.md` |
| State-machine gating (stage preconditions, terminate-at-human-review) | 2 | `references/cli-command-reference.md` (precondition table), `references/decision-framework.md` |

Skills operationalizing this domain: `skills/competition-analysis/SKILL.md`,
`skills/reddit-voc/SKILL.md`, `skills/differentiation/SKILL.md`,
`skills/red-team/SKILL.md`. Methodology: `references/browser-research-protocol.md`.

## Domain 4: Economics, Supplier/IP, Decision, State Machine, Storage, CLI, Reporting (~40+ rules)

| Rule ID range | Count | Destination |
|---|---|---|
| ECON-01 .. ECON-11 | 11 | `references/economics.md`, restated in `references/core-rules.md` rule #4 |
| SUP-01 .. SUP-05 | 5 | `references/supplier-ip.md` |
| IP-01 | 1 | `references/supplier-ip.md` |
| GATE-01 .. GATE-03 | 3 | `references/decision-gates.md`, restated in `references/core-rules.md` rule #1 |
| RANK-01 .. RANK-06 | 6 | `references/decision-gates.md` |
| SM-01 .. SM-11 | 11 | `references/decision-gates.md`, precondition table in `references/cli-command-reference.md` |
| STORE-01 .. STORE-09 | 9 | **No dedicated Skill-level destination — see note below.** |
| CLI-01 .. CLI-09 | 9 | `references/cli-command-reference.md` (this file *is* the CLI-01..09 rule set, since it was written directly from `cli.py`), restated in `references/core-rules.md` rule #2 |
| REP-01 .. REP-07 | 7 | `references/cli-command-reference.md` (`hunt show`/`report`/`data-audit` sections), `references/decision-framework.md` |

Skills operationalizing this domain: `skills/economics/SKILL.md`,
`skills/supplier-research/SKILL.md`, `skills/ip-risk/SKILL.md`,
`skills/final-decision/SKILL.md`.

**STORE-01..09 disposition:** these rules describe internal SQLite schema
behavior (append-only vs. upsert table design, the `_ADDED_COLUMNS` migration
mechanism, WAL mode, `final_status`/`state` not being SQL-CHECK-constrained,
natural-key ASIN reconciliation). No Skill in this package writes to the
database directly or needs to reason about schema internals — every write
goes through a `hunt` CLI command, which already enforces these guarantees
internally. Per the mission's own instruction ("if an advisory rule cannot be
mapped, document why"): these 9 rules are **preserved automatically by the
wrap-the-engine architecture** (the schema code is untouched, still runs, still
tested by the source engine's own 568 tests) but have **no corresponding
Skill-level instruction**, because a Skill has no legitimate reason to ever
bypass the CLI and touch the schema directly. This is a deliberate, documented
non-mapping, not an oversight.

## Summary

- **Total rules extracted:** ~215 (75 + 65 + 35 + 40, some domain overlap on
  shared gate/ranking logic independently cross-verified by two agents).
- **Rules with an explicit Skill-package destination:** ~206.
- **Rules with no Skill-level mapping, by design:** 9 (STORE-01..09 — internal
  schema mechanics inherited automatically, not applicable to a CLI-only
  consumer).
- **Rules patched after initial gap found in review:** 5 (G1..G5, enrichment).
- **No hard rule was found unmapped.** The only unmapped rules (STORE-*) are
  advisory/structural and explicitly do not apply to a package that never
  touches the database directly.

This satisfies the traceability requirement: every extracted rule has either
an explicit reference-file destination, or an explicit, reasoned statement of
why no Skill-level destination is needed.
