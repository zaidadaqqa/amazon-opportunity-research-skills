# Adversarial Test Mapping

Because this package wraps the existing engine rather than reimplementing its
logic, the correct adversarial test for "does the UNKNOWN gate still refuse to
fire" is not a new test written for this package — it's the exact same test
that already pins that behavior in the source engine. Every row below was
verified to exist by collecting the real Amazon-products test suite
(`pytest tests/ --collect-only`, 568 tests total) and grep-matching the exact
node ID; nothing here is invented. Run `run_adversarial_suite.sh` to execute
all of them together.

Two scenarios from the standard adversarial checklist have **no dedicated
engine test** — they are called out explicitly rather than mapped to a
plausible-sounding but nonexistent test name (see "Not covered" below).

| # | Scenario | Test node ID | What it proves |
|---|---|---|---|
| 1 | UNKNOWN never triggers a gate | `tests/unit/test_ranking_gates.py::test_unknown_never_triggers_a_gate` | Core rule #1 |
| 2 | SUSPECTED_CONTAMINATION never triggers a gate | `tests/unit/test_ranking_gates.py::test_suspected_contamination_does_not_fail_gate` | Core rule #1 |
| 3 | PENDING_HUMAN_LEGAL_REVIEW never triggers a gate | `tests/unit/test_ranking_gates.py::test_pending_human_legal_review_does_not_fail_gate` | Core rule #1 |
| 4 | CONFIRMED_CONTAMINATION does trigger a gate | `tests/unit/test_ranking_gates.py::test_confirmed_contamination_fails_gate` | Gate is not a no-op |
| 5 | CONFIRMED_BLOCKER (IP) does trigger a gate | `tests/unit/test_ranking_gates.py::test_confirmed_ip_blocker_fails_gate` | Gate is not a no-op |
| 6 | CONFIRMED_IMPOSSIBLE (supplier) does trigger a gate | `tests/unit/test_ranking_gates.py::test_confirmed_supplier_impossible_fails_gate` | Gate is not a no-op |
| 7 | Human-only QUALIFIED — rank_run never sets it | `tests/unit/test_ranking_scoring.py::test_rank_run_qualified_candidate_reaches_promising_never_qualified` | Core rule #2 |
| 8 | REAL mode never falls back to mock | `tests/unit/test_provider_registry.py::test_real_mode_never_returns_mock_provider_even_if_something_goes_wrong` | Core rule #3 |
| 9 | Duplicate parent ASIN never double-counted | `tests/unit/test_competitor_autopsy.py::test_dedupe_by_parent_keeps_one_representative_per_parent` | Lineage/dedup discipline |
| 10 | Insufficient competition sample never reports a precise decimal | `tests/unit/test_competitor_autopsy.py::test_run_competitor_autopsy_small_sample_never_reports_precise_decimal` | No false precision |
| 11 | STALE evidence downgrades ranking confidence | `tests/unit/test_ranking_scoring.py::test_stale_current_market_evidence_downgrades_observable_confidence` | Core rule #5 |
| 12 | CONTRADICTED evidence downgrades further than STALE | `tests/unit/test_ranking_scoring.py::test_contradicted_current_market_evidence_downgrades_even_further` | Core rule #5 |
| 13 | Contradictory evidence is preserved, not hidden; authoritative value still wins | `tests/integration/test_market_acquisition.py::test_conflicting_discovery_hint_records_contradiction_but_authoritative_price_wins` | Contradiction handling |
| 14 | Report re-flags evidence as STALE at generation time even if the stored row wasn't updated | `tests/integration/test_reporting.py::test_report_flags_expired_evidence_as_stale_at_generation_time` | Freshness is read-time, not silently trusted |
| 15 | Temporary Trends spike is detected, not treated as sustained demand | `tests/unit/test_demand_qualification.py::test_temporary_spike_detected_inside_flat_series` | Demand-illusion defense |
| 16 | Insufficient Trends history (< 2 years) never claims seasonality | `tests/unit/test_demand_qualification.py::test_seasonality_insufficient_data_below_two_years` | No false seasonality claim |
| 17 | Missing Trends data entirely returns INSUFFICIENT_DATA, not a guess | `tests/unit/test_demand_qualification.py::test_no_interest_over_time_at_all_is_insufficient_data` | Core anti-hallucination contract |
| 18 | Missing supplier data stays UNKNOWN, never auto-rejects | `tests/unit/test_ranking_scoring.py::test_rank_run_no_supplier_validation_recorded_stays_unknown_never_rejects` | Core rule #1 applied to supplier gate |
| 19 | Missing/insufficient economics fields → INSUFFICIENT_DATA, never a guessed number | `tests/unit/test_economics.py::test_insufficient_data_when_required_fields_missing` | Core rule #4 |
| 20 | Fake/ungrounded VOC finding is dropped entirely, not partially trusted | `tests/unit/test_review_analysis.py::test_batch_citing_invalid_evidence_id_is_dropped_but_skill_execution_recorded` | VOC evidence-anchoring |
| 21 | Ungrounded red-team EVIDENCED claim is downgraded to HYPOTHESIS, not dropped | `tests/unit/test_red_team.py::test_evidenced_finding_with_invalid_evidence_id_downgraded_to_hypothesis` | Deliberate red-team asymmetry vs. VOC |
| 22 | Ungrounded differentiation moat claim collapses to LOW_COPYCAT_RESISTANCE | `tests/unit/test_differentiation.py::test_ungrounded_moat_claim_falls_back_to_low_resistance` | Deliberate differentiation asymmetry vs. VOC/red-team |
| 23 | Browser research accidentally treated as FACT — structurally prevented | `tests/unit/test_external_research.py::test_record_external_evidence_pack_uses_estimate_never_fact` | Core rule #5 applied to Browser Edition's own new evidence tier |
| 24 | Browser-brief generation refused for a raw discovery-stage candidate | `tests/unit/test_external_research.py::test_brief_generation_rejected_for_raw_discovered_candidate` | Deep research before cheap filtering, prevented |
| 25 | Rejected/STAGE_CAPPED candidates never get a competitor-snapshot deep-research call | `tests/integration/test_deepen_safety.py::test_deepen_start_never_calls_provider_for_stage_capped_candidates` | Deep research before cheap filtering, prevented |
| 26 | Wrong-state command is rejected, never silently advanced | `tests/integration/test_manual_voc_completion.py::test_wrong_state_is_rejected_not_silently_advanced` | State-machine precondition enforcement |
| 27 | VOC cannot be silently marked complete with zero findings and no explicit confirmation | `tests/integration/test_manual_voc_completion.py::test_without_this_fix_no_findings_and_no_confirmation_is_refused` | Anti-fabrication ("no complaints found" cannot be assumed) |

## Not covered by an existing engine test (disclosed, not hidden)

- **"Incompatible BSR category comparison"** — CLAUDE.md and
  `references/competition.md` both state this as a hard principle ("never
  compare BSR velocity across incompatible categories"), but no grep across
  the full test suite (`grep -rli "incompatible.*bsr\|bsr.*categor" tests/`)
  found a dedicated test enforcing it. This is a genuine gap in the source
  engine's test coverage, not something this package can paper over — flagged
  here rather than mapped to a plausible-sounding but nonexistent test.
- **"Weak Reddit evidence → INSUFFICIENT_DATA"** — Reddit research is new
  Browser Edition capability with no equivalent in the source engine's test
  suite (`grep -rli reddit tests/` finds only the general external-research
  tests, which are format/tier tests, not Reddit-specific). This scenario's
  correctness depends on `skills/reddit-voc/SKILL.md` and
  `references/browser-research-protocol.md` being followed correctly by
  Claude at runtime — it cannot be pinned by a pytest test the way the
  deterministic engine's rules can. Documented as a process/protocol
  requirement, not a code-enforced guarantee.
