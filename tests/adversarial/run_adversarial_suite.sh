#!/usr/bin/env bash
# Runs exactly the 27 verified engine tests listed in ADVERSARIAL_MAPPING.md
# against the real Amazon-products engine. Every node ID here was confirmed
# to exist via `pytest --collect-only` before being added to the mapping --
# this script will fail loudly (pytest's own "not found" error) if the
# engine ever renames/removes one of them, rather than silently skip it.
set -euo pipefail

ENGINE_DIR="${ENGINE_DIR:-/home/zaid/Desktop/Amazon-products}"
cd "$ENGINE_DIR"
source .venv/bin/activate

python -m pytest -v \
  "tests/unit/test_ranking_gates.py::test_unknown_never_triggers_a_gate" \
  "tests/unit/test_ranking_gates.py::test_suspected_contamination_does_not_fail_gate" \
  "tests/unit/test_ranking_gates.py::test_pending_human_legal_review_does_not_fail_gate" \
  "tests/unit/test_ranking_gates.py::test_confirmed_contamination_fails_gate" \
  "tests/unit/test_ranking_gates.py::test_confirmed_ip_blocker_fails_gate" \
  "tests/unit/test_ranking_gates.py::test_confirmed_supplier_impossible_fails_gate" \
  "tests/unit/test_ranking_scoring.py::test_rank_run_qualified_candidate_reaches_promising_never_qualified" \
  "tests/unit/test_provider_registry.py::test_real_mode_never_returns_mock_provider_even_if_something_goes_wrong" \
  "tests/unit/test_competitor_autopsy.py::test_dedupe_by_parent_keeps_one_representative_per_parent" \
  "tests/unit/test_competitor_autopsy.py::test_run_competitor_autopsy_small_sample_never_reports_precise_decimal" \
  "tests/unit/test_ranking_scoring.py::test_stale_current_market_evidence_downgrades_observable_confidence" \
  "tests/unit/test_ranking_scoring.py::test_contradicted_current_market_evidence_downgrades_even_further" \
  "tests/integration/test_market_acquisition.py::test_conflicting_discovery_hint_records_contradiction_but_authoritative_price_wins" \
  "tests/integration/test_reporting.py::test_report_flags_expired_evidence_as_stale_at_generation_time" \
  "tests/unit/test_demand_qualification.py::test_temporary_spike_detected_inside_flat_series" \
  "tests/unit/test_demand_qualification.py::test_seasonality_insufficient_data_below_two_years" \
  "tests/unit/test_demand_qualification.py::test_no_interest_over_time_at_all_is_insufficient_data" \
  "tests/unit/test_ranking_scoring.py::test_rank_run_no_supplier_validation_recorded_stays_unknown_never_rejects" \
  "tests/unit/test_economics.py::test_insufficient_data_when_required_fields_missing" \
  "tests/unit/test_review_analysis.py::test_batch_citing_invalid_evidence_id_is_dropped_but_skill_execution_recorded" \
  "tests/unit/test_red_team.py::test_evidenced_finding_with_invalid_evidence_id_downgraded_to_hypothesis" \
  "tests/unit/test_differentiation.py::test_ungrounded_moat_claim_falls_back_to_low_resistance" \
  "tests/unit/test_external_research.py::test_record_external_evidence_pack_uses_estimate_never_fact" \
  "tests/unit/test_external_research.py::test_brief_generation_rejected_for_raw_discovered_candidate" \
  "tests/integration/test_deepen_safety.py::test_deepen_start_never_calls_provider_for_stage_capped_candidates" \
  "tests/integration/test_manual_voc_completion.py::test_wrong_state_is_rejected_not_silently_advanced" \
  "tests/integration/test_manual_voc_completion.py::test_without_this_fix_no_findings_and_no_confirmation_is_refused"

echo
echo "=== All 27 adversarial scenarios PASSED against the real engine. ==="
echo "2 additional scenarios (incompatible BSR comparison, weak Reddit evidence)"
echo "have no dedicated engine test -- see ADVERSARIAL_MAPPING.md 'Not covered'."
