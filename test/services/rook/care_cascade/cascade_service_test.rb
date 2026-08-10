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
    cured = hcv_patient("h1", resources: [
                          hcv_ab(result: :pos),
                          hcv_rna(result: :pos, date: "2026-01-01"),
                          daa_med(date: "2026-01-05"),
                          hcv_rna(result: :neg, date: "2026-05-01") # SVR12 undetectable, >12wk later
                        ])
    report = hcv_report([ cured ])

    assert_equal 1, report.counts[:treatment_completed]
    assert_equal "h1", report.drop_off(:treatment_completed).first
  end

  # Fix 1: a negative RNA before treatment must not count as cure.
  def test_hcv_cure_not_credited_when_negative_rna_predates_treatment
    out_of_order = hcv_patient("h2", resources: [
                                 hcv_rna(result: :pos, date: "2026-02-01"),
                                 hcv_rna(result: :neg, date: "2026-01-01"), # before treatment
                                 daa_med(date: "2026-02-05")
                               ])
    report = hcv_report([ out_of_order ])

    assert_equal 0, report.counts[:treatment_completed]
    assert_equal 1, report.counts[:treatment_initiated]
  end

  # Fix 1: a negative RNA inside the ~12-week SVR12 window is too early.
  def test_hcv_cure_not_credited_when_negative_rna_is_too_early
    too_early = hcv_patient("h3", resources: [
                              hcv_rna(result: :pos, date: "2026-01-01"),
                              daa_med(date: "2026-01-05"),
                              hcv_rna(result: :neg, date: "2026-02-15") # ~6 weeks, < 12
                            ])
    report = hcv_report([ too_early ])

    assert_equal 0, report.counts[:treatment_completed]
  end

  # Fix 1: cure fails closed when treatment has no usable date.
  def test_hcv_cure_not_credited_when_treatment_has_no_date
    undated = hcv_patient("h4", resources: [
                            hcv_rna(result: :pos, date: "2026-01-01"),
                            daa_med, # no authoredOn
                            hcv_rna(result: :neg, date: "2026-06-01")
                          ])
    report = hcv_report([ undated ])

    assert_equal 0, report.counts[:treatment_completed]
    assert_equal 1, report.counts[:treatment_initiated]
  end

  # =============================================================================
  # FHIR STATUS FILTERING (fix 2)
  # =============================================================================

  def test_cancelled_or_draft_medication_does_not_count_as_treatment
    patient = active_syphilis_patient("s1", extra: [ medication("7982", status: "cancelled") ])
    report = build_report(patients: [ patient ])

    assert_equal 0, report.counts[:treatment_initiated]
    assert_equal 1, report.counts[:active_infection]
  end

  def test_entered_in_error_procedure_does_not_count_as_treatment
    proc_res = { resourceType: "Procedure", status: "entered-in-error",
                 code: { coding: [ { system: RXNORM, code: "7982" } ] } }
    patient = active_syphilis_patient("s2", extra: [ proc_res ])
    report = build_report(patients: [ patient ])

    assert_equal 0, report.counts[:treatment_initiated]
  end

  def test_preliminary_or_errored_observations_are_ignored
    patient = patient("s3", site: "mobile-1", ai_an: true, resources: [
                        syph_screen_status("20507-0", result: :pos, status: "preliminary"),
                        observation("8041-9", result: :pos, status: "entered-in-error")
                      ])
    report = build_report(patients: [ patient ])

    assert_equal 0, report.counts[:screened]
    assert_equal 0, report.counts[:reactive]
    assert_equal 0, report.counts[:active_infection]
  end

  # =============================================================================
  # TERMINOLOGY SYSTEM MATCHING (fix 3)
  # =============================================================================

  def test_matching_code_from_wrong_system_does_not_satisfy_a_code_set
    # 20507-0 is an RPR LOINC code; presenting it under a non-LOINC system must
    # not count as a syphilis screen.
    patient = patient("w1", site: "mobile-1", ai_an: true,
                      resources: [ observation("20507-0", result: :pos, system: "http://example.org/local") ])
    report = build_report(patients: [ patient ])

    assert_equal 0, report.counts[:screened]
  end

  def test_matching_code_from_correct_system_satisfies_a_code_set
    patient = patient("w2", site: "mobile-1", ai_an: true,
                      resources: [ observation("20507-0", result: :pos, system: LOINC) ])
    report = build_report(patients: [ patient ])

    assert_equal 1, report.counts[:screened]
    assert_equal 1, report.counts[:reactive]
  end

  # =============================================================================
  # AI/AN DISAGGREGATION — MISSING/UNKNOWN (fix 4)
  # =============================================================================

  def test_missing_ai_an_is_reported_as_unknown_not_non_ai_an
    cohort = [
      patient("a1", site: "mobile-1", ai_an: true,  resources: [ syph_screen(result: :neg) ]),
      patient("a2", site: "mobile-1", ai_an: false, resources: [ syph_screen(result: :neg) ]),
      { patient_id: "a3", site: "mobile-1", resources: [ syph_screen(result: :neg) ] } # ai_an absent
    ]
    by_ai_an = build_report(patients: cohort).by_ai_an

    assert by_ai_an.key?("unknown")
    assert_equal 1, by_ai_an["unknown"].total
    assert_equal 1, by_ai_an["non-AI/AN"].total
    assert_equal 3, by_ai_an.values.sum(&:total)
  end

  def test_malformed_ai_an_value_is_treated_as_unknown
    cohort = [ { patient_id: "a4", site: "mobile-1", ai_an: "maybe", resources: [ syph_screen(result: :neg) ] } ]
    by_ai_an = build_report(patients: cohort).by_ai_an

    assert_equal 1, by_ai_an["unknown"].total
    refute by_ai_an.key?("non-AI/AN")
  end

  # =============================================================================
  # CONDITION-DRIVEN ACTIVE INFECTION + IDENTITY/DEDUP (fix 5)
  # =============================================================================

  def test_active_infection_reached_via_fhir_condition
    # No positive confirmatory Observation — the alternate Condition-driven path.
    patient = patient("cond1", site: "mobile-1", ai_an: true, resources: [
                        syph_screen(result: :pos),
                        syph_confirm(result: :neg),
                        condition("A51.0", system: "http://hl7.org/fhir/sid/icd-10-cm")
                      ])
    report = build_report(patients: [ patient ])

    assert_equal 1, report.counts[:active_infection]
  end

  def test_resolved_condition_does_not_reach_active_infection
    patient = patient("cond2", site: "mobile-1", ai_an: true, resources: [
                        syph_screen(result: :pos),
                        condition("A51.0", system: "http://hl7.org/fhir/sid/icd-10-cm", clinical: "resolved")
                      ])
    report = build_report(patients: [ patient ])

    assert_equal 0, report.counts[:active_infection]
    assert_equal 1, report.counts[:reactive]
  end

  def test_condition_entered_in_error_does_not_reach_active_infection
    patient = patient("cond3", site: "mobile-1", ai_an: true, resources: [
                        syph_screen(result: :pos),
                        condition("A51.0", system: "http://hl7.org/fhir/sid/icd-10-cm",
                                           verification: "entered-in-error")
                      ])
    report = build_report(patients: [ patient ])

    assert_equal 0, report.counts[:active_infection]
  end

  def test_missing_patient_id_is_rejected_from_phi_worklists
    assert_raises(Rook::CareCascade::PatientRecord::MissingIdentifierError) do
      build_report(patients: [ { site: "mobile-1", ai_an: true, resources: [ syph_screen(result: :pos) ] } ])
    end
  end

  def test_duplicate_patient_records_are_deduplicated_and_merged
    # Same patient split across two partial pulls: screen in one, confirm in the
    # other. Deduplication counts one patient and merges resources.
    cohort = [
      patient("dup1", site: "mobile-1", ai_an: true, resources: [ syph_screen(result: :pos) ]),
      patient("dup1", site: "mobile-1", ai_an: true, resources: [ syph_confirm(result: :pos) ])
    ]
    report = build_report(patients: cohort)

    assert_equal 1, report.total
    assert_equal 1, report.counts[:active_infection] # merged screen + confirm
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

  # An active-infection syphilis patient (screened+, confirmed+), plus any
  # +extra+ resources under test.
  def active_syphilis_patient(id, extra: [])
    patient(id, site: "mobile-1", ai_an: true,
                resources: [ syph_screen(result: :pos), syph_confirm(result: :pos) ] + extra)
  end

  def hcv_patient(id, resources:)
    { patient_id: id, site: "mobile-1", ai_an: true, resources: resources }
  end

  def hcv_report(patients)
    Rook::CareCascade::CascadeService.new(definition: Def.builtin(:hcv), patients: patients).report
  end

  def syph_screen_status(code, result:, status:)
    observation(code, result: result, status: status)
  end

  # --- FHIR resource builders --------------------------------------------------

  LOINC  = "http://loinc.org"
  RXNORM = "http://www.nlm.nih.gov/research/umls/rxnorm"

  def observation(code, result:, status: "final", date: nil, system: LOINC)
    interp = { pos: "POS", neg: "NEG" }.fetch(result)
    obs = {
      resourceType: "Observation",
      status: status,
      code: { coding: [ { system: system, code: code } ] },
      interpretation: [ { coding: [ { code: interp } ] } ]
    }
    obs[:effectiveDateTime] = date if date
    obs
  end

  def syph_screen(result:)      = observation("20507-0", result: result)   # RPR
  def syph_confirm(result:)     = observation("8041-9", result: result)    # TP-PA
  def hcv_ab(result:)           = observation("13955-0", result: result)   # HCV Ab
  def hcv_rna(result:, status: "final", date: nil) = observation("11259-9", result: result, status: status, date: date)

  def pcn_med
    medication("7982") # penicillin G benzathine
  end

  def daa_med(status: "active", date: nil)
    medication("1734340", status: status, date: date) # DAA regimen
  end

  def medication(code, status: "active", date: nil, system: RXNORM)
    med = {
      resourceType: "MedicationRequest",
      status: status,
      medicationCodeableConcept: { coding: [ { system: system, code: code } ] }
    }
    med[:authoredOn] = date if date
    med
  end

  def condition(code, system:, clinical: "active", verification: nil)
    cond = {
      resourceType: "Condition",
      code: { coding: [ { system: system, code: code } ] },
      clinicalStatus: { coding: [ { code: clinical } ] }
    }
    cond[:verificationStatus] = { coding: [ { code: verification } ] } if verification
    cond
  end
end
