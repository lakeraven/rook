# frozen_string_literal: true

require "test_helper"

class Rook::CareCascade::CascadeServiceTest < Minitest::Test
  Def = Rook::CareCascade::ConditionDefinition

  # =============================================================================
  # SYPHILIS CASCADE — FUNNEL COUNTS
  #
  # Mirrors the Cherokee Nation HELP failure mode: people test reactive then
  # vanish before confirmation/treatment. Scaled cohort of 10.
  # =============================================================================

  def test_cumulative_funnel_counts
    report = build_report(patients: syphilis_cohort)
    counts = report.counts

    assert_equal 10, counts[:screened]
    assert_equal 6, counts[:reactive]
    assert_equal 3, counts[:confirmation_completed]
    assert_equal 2, counts[:active_infection]
    assert_equal 2, counts[:treatment_initiated]
    assert_equal 0, counts[:treatment_completed]
  end

  def test_reached_exactly_counts_locate_the_stall_points
    report = build_report(patients: syphilis_cohort)
    exact = report.reached_exactly_counts

    assert_equal 4, exact[:screened]                # screened negative
    assert_equal 3, exact[:reactive]                # reactive, never confirmed
    assert_equal 1, exact[:confirmation_completed]  # confirmed negative (resolved)
    assert_equal 0, exact[:active_infection]
    assert_equal 2, exact[:treatment_initiated]     # treated, not yet cured
    assert_equal 0, exact[:treatment_completed]
  end

  def test_conversion_rates_between_consecutive_stages
    report = build_report(patients: syphilis_cohort)
    conv = report.conversions

    assert_in_delta 0.6, conv["screened_to_reactive"], 0.0001
    assert_in_delta 0.5, conv["reactive_to_confirmation_completed"], 0.0001
    assert_in_delta 0.6667, conv["confirmation_completed_to_active_infection"], 0.0001
    assert_in_delta 1.0, conv["active_infection_to_treatment_initiated"], 0.0001
    assert_in_delta 0.0, conv["treatment_initiated_to_treatment_completed"], 0.0001
  end

  def test_conversion_rate_is_nil_when_upstream_stage_is_empty
    report = build_report(patients: [])
    assert_nil report.conversions["screened_to_reactive"]
  end

  # =============================================================================
  # DROP-OFF WORKLISTS
  # =============================================================================

  def test_reactive_not_confirmed_worklist_feeds_outreach
    report = build_report(patients: syphilis_cohort)
    worklist = report.worklists[:reactive]

    assert_equal 3, worklist[:count]
    assert_equal %w[r1 r2 r3].sort, worklist[:patient_ids].sort
  end

  def test_treatment_initiated_not_completed_worklist
    report = build_report(patients: syphilis_cohort)
    assert_equal %w[t1 t2].sort, report.worklists[:treatment_initiated][:patient_ids].sort
  end

  def test_worklists_only_cover_actionable_stages
    report = build_report(patients: syphilis_cohort)

    assert_equal %i[reactive active_infection treatment_initiated], report.worklists.keys
    refute report.worklists.key?(:screened)               # negative screen — no follow-up
    refute report.worklists.key?(:confirmation_completed)  # negative confirm — resolved
  end

  def test_drop_off_returns_patient_ids_for_any_stage
    report = build_report(patients: syphilis_cohort)
    assert_equal 4, report.drop_off(:screened).size
    assert_equal %w[c_neg], report.drop_off(:confirmation_completed)
  end

  # =============================================================================
  # DISAGGREGATION — SITE + AI/AN STATUS
  # =============================================================================

  def test_disaggregation_by_site_partitions_the_cohort
    report = build_report(patients: syphilis_cohort)
    by_site = report.by_site

    assert_equal %w[mobile-1 mobile-2].sort, by_site.keys.sort
    total = by_site.values.sum(&:total)
    assert_equal 10, total
  end

  def test_disaggregation_by_ai_an_status
    report = build_report(patients: syphilis_cohort)
    by_ai_an = report.by_ai_an

    assert by_ai_an.key?("AI/AN")
    assert by_ai_an.key?("non-AI/AN")
    assert_equal 10, by_ai_an.values.sum(&:total)
    # AI/AN subgroup keeps its own funnel
    assert by_ai_an["AI/AN"].counts[:screened].positive?
  end

  def test_cross_disaggregation_by_site_and_ai_an
    report = build_report(patients: syphilis_cohort)
    assert_equal 10, report.by_site_and_ai_an.values.sum(&:total)
  end

  # =============================================================================
  # GRANT REPORTING OUTPUT
  # =============================================================================

  def test_grant_report_is_aggregate_only_no_patient_ids
    report = build_report(patients: syphilis_cohort)
    grant = report.to_grant_report(period: "2026-Q1", program: "RHTP")

    assert_equal "RHTP", grant[:program]
    assert_equal "2026-Q1", grant[:reporting_period]
    assert_equal :syphilis, grant[:condition][:key]
    assert_equal 10, grant[:cohort_size]
    assert_equal 6, grant[:cascade][:reactive]
    assert grant[:conversion_rates].key?("screened_to_reactive")
    assert grant[:disaggregation][:by_site].values.first.key?(:cascade)

    refute_includes grant.to_s, "patient_id"
    refute_includes grant.to_s, "r1"
  end

  # =============================================================================
  # HCV CASCADE — CURE (SVR12) COMPLETION
  # =============================================================================

  def test_hcv_cure_credited_on_negative_rna_after_treatment
    cured = {
      patient_id: "h1", site: "mobile-1", ai_an: true,
      resources: [
        hcv_ab(result: :pos),
        hcv_rna(result: :pos),
        daa_med,
        hcv_rna(result: :neg) # SVR12 undetectable
      ]
    }
    service = Rook::CareCascade::CascadeService.new(definition: Def.builtin(:hcv), patients: [ cured ])
    report = service.report

    assert_equal 1, report.counts[:treatment_completed]
    assert_equal "h1", report.drop_off(:treatment_completed).first
  end

  # =============================================================================
  # INPUT HANDLING
  # =============================================================================

  def test_patients_may_be_supplied_via_adapter_callable
    adapter = -> { syphilis_cohort }
    service = Rook::CareCascade::CascadeService.new(definition: Def.builtin(:syphilis), patients: adapter)
    assert_equal 10, service.report.total
  end

  # =============================================================================
  # CQL ENGINE SEAM (rook#1) — no silent fallback
  # =============================================================================

  def test_cql_sourced_definition_raises_rather_than_faking_results
    stages = Def.builtin(:syphilis).stages
    cql_def = Rook::CareCascade::ConditionDefinition.new(
      key: :syphilis_cql, name: "Syphilis (CQL)", stages: stages, source: :cql
    )
    service = Rook::CareCascade::CascadeService.new(definition: cql_def, patients: [])

    err = assert_raises(Rook::CareCascade::CascadeService::CqlEngineNotAvailableError) do
      service.report
    end
    assert_match(/CQL execution engine is not yet selected/, err.message)
  end

  def test_unknown_builtin_condition_raises
    assert_raises(Rook::CareCascade::ConditionDefinition::UnknownConditionError) do
      Def.builtin(:not_a_condition)
    end
  end

  private

  def build_report(patients:)
    Rook::CareCascade::CascadeService.new(
      definition: Def.builtin(:syphilis),
      patients: patients
    ).report
  end

  # --- Syphilis cohort of 10 ---------------------------------------------------
  # 4 screened-negative, 3 reactive-not-confirmed, 1 confirmed-negative,
  # 2 active + treated. Sites and AI/AN status assigned for disaggregation.
  def syphilis_cohort
    negatives = (1..4).map do |i|
      patient("n#{i}", site: site_for(i), ai_an: i.even?, resources: [ syph_screen(result: :neg) ])
    end
    reactives = (1..3).map do |i|
      patient("r#{i}", site: site_for(i), ai_an: i.even?, resources: [ syph_screen(result: :pos) ])
    end
    confirmed_negative = [
      patient("c_neg", site: "mobile-1", ai_an: true,
              resources: [ syph_screen(result: :pos), syph_confirm(result: :neg) ])
    ]
    treated = (1..2).map do |i|
      patient("t#{i}", site: site_for(i), ai_an: i.even?,
              resources: [ syph_screen(result: :pos), syph_confirm(result: :pos), pcn_med ])
    end
    negatives + reactives + confirmed_negative + treated
  end

  def site_for(i)
    i.odd? ? "mobile-1" : "mobile-2"
  end

  def patient(id, site:, ai_an:, resources:)
    { patient_id: id, site: site, ai_an: ai_an, resources: resources }
  end

  # --- FHIR resource builders --------------------------------------------------

  def observation(code, result:)
    interp = { pos: "POS", neg: "NEG" }.fetch(result)
    {
      resourceType: "Observation",
      status: "final",
      code: { coding: [ { system: "http://loinc.org", code: code } ] },
      interpretation: [ { coding: [ { code: interp } ] } ]
    }
  end

  def syph_screen(result:)      = observation("20507-0", result: result)   # RPR
  def syph_confirm(result:)     = observation("8041-9", result: result)    # TP-PA
  def hcv_ab(result:)           = observation("13955-0", result: result)   # HCV Ab
  def hcv_rna(result:)          = observation("11259-9", result: result)   # HCV RNA

  def pcn_med
    medication("7982") # penicillin G benzathine
  end

  def daa_med
    medication("1734340") # DAA regimen
  end

  def medication(code)
    {
      resourceType: "MedicationRequest",
      status: "active",
      medicationCodeableConcept: { coding: [ { system: "http://www.nlm.nih.gov/research/umls/rxnorm", code: code } ] }
    }
  end
end
