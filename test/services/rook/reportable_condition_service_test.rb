# frozen_string_literal: true

require "test_helper"

class Rook::ReportableConditionServiceTest < Minitest::Test
  ICD10 = "http://hl7.org/fhir/sid/icd-10-cm"
  SNOMED = "http://snomed.info/sct"

  # =============================================================================
  # DETECTION — REPORTABLE CONDITIONS
  # =============================================================================

  def test_detects_tuberculosis_as_reportable
    service = build_service(conditions: reportable_conditions)
    result = service.check(condition: fhir_condition("A15.0", "Pulmonary tuberculosis"))

    assert result.reportable?
    assert_equal "Tuberculosis", result.condition_name
  end

  def test_detects_measles_as_reportable
    service = build_service(conditions: reportable_conditions)
    result = service.check(condition: fhir_condition("B05.9", "Measles"))

    assert result.reportable?
    assert_equal "Measles", result.condition_name
  end

  def test_non_reportable_condition_returns_false
    service = build_service(conditions: reportable_conditions)
    result = service.check(condition: fhir_condition("E11.9", "Type 2 diabetes"))

    refute result.reportable?
    assert_nil result.condition_name
  end

  def test_detects_by_code_not_just_display
    service = build_service(conditions: reportable_conditions)
    result = service.check(condition: fhir_condition("A15.0", "Something else"))

    assert result.reportable?
  end

  # =============================================================================
  # FHIR-NATIVE INPUTS
  # =============================================================================

  def test_accepts_bare_fhir_coding
    service = build_service(conditions: reportable_conditions)
    coding = FHIR::Coding.new(system: ICD10, code: "A15.0", display: "Pulmonary TB")
    result = service.check(condition: coding)

    assert result.reportable?
    assert_equal "Tuberculosis", result.condition_name
  end

  def test_checks_every_coding_on_the_condition
    service = build_service(conditions: reportable_conditions)
    condition = FHIR::Condition.new(
      code: {
        coding: [
          { system: SNOMED, code: "154283005", display: "Pulmonary tuberculosis" },
          { system: ICD10, code: "A15.0", display: "Pulmonary tuberculosis" }
        ]
      }
    )
    result = service.check(condition: condition)

    assert result.reportable?
    assert_equal "Tuberculosis", result.condition_name
  end

  def test_accepts_fhir_codeable_concept
    service = build_service(conditions: reportable_conditions)
    concept = FHIR::CodeableConcept.new(
      coding: [
        { system: SNOMED, code: "154283005", display: "Pulmonary tuberculosis" },
        { system: ICD10, code: "A15.0", display: "Pulmonary tuberculosis" }
      ]
    )
    result = service.check(condition: concept)

    assert result.reportable?
    assert_equal "Tuberculosis", result.condition_name
  end

  def test_empty_codeable_concept_is_not_reportable
    service = build_service(conditions: reportable_conditions)
    result = service.check(condition: FHIR::CodeableConcept.new)

    refute result.reportable?
  end

  def test_matches_snomed_codes_when_configured
    conditions = [ { codes: [ "154283005" ], name: "Tuberculosis", urgency: "24h" } ]
    service = build_service(conditions: conditions)
    coding = FHIR::Coding.new(system: SNOMED, code: "154283005")
    result = service.check(condition: coding)

    assert result.reportable?
  end

  def test_rejects_non_fhir_input
    service = build_service(conditions: reportable_conditions)

    assert_raises(ArgumentError) { service.check(condition: { code: "A15.0" }) }
  end

  # =============================================================================
  # VERIFICATION STATUS
  # =============================================================================

  def test_entered_in_error_condition_is_not_reportable
    service = build_service(conditions: reportable_conditions)
    condition = fhir_condition("A15.0", "Pulmonary tuberculosis")
    condition.verificationStatus = verification_status("entered-in-error")
    result = service.check(condition: condition)

    refute result.reportable?
  end

  def test_refuted_condition_is_not_reportable
    service = build_service(conditions: reportable_conditions)
    condition = fhir_condition("B05.9", "Measles")
    condition.verificationStatus = verification_status("refuted")
    result = service.check(condition: condition)

    refute result.reportable?
  end

  def test_confirmed_condition_is_still_reportable
    service = build_service(conditions: reportable_conditions)
    condition = fhir_condition("A15.0", "Pulmonary tuberculosis")
    condition.verificationStatus = verification_status("confirmed")
    result = service.check(condition: condition)

    assert result.reportable?
  end

  # =============================================================================
  # SYSTEM-SCOPED CONFIGURED CODES
  # =============================================================================

  def test_system_scoped_code_matches_coding_in_that_system
    conditions = [ { codes: [ { system: SNOMED, code: "154283005" } ],
                     name: "Tuberculosis", urgency: "24h" } ]
    service = build_service(conditions: conditions)
    result = service.check(condition: FHIR::Coding.new(system: SNOMED, code: "154283005"))

    assert result.reportable?
    assert_equal "Tuberculosis", result.condition_name
  end

  def test_system_scoped_code_rejects_same_code_from_another_system
    conditions = [ { codes: [ { system: SNOMED, code: "154283005" } ],
                     name: "Tuberculosis", urgency: "24h" } ]
    service = build_service(conditions: conditions)
    result = service.check(condition: FHIR::Coding.new(system: ICD10, code: "154283005"))

    refute result.reportable?
  end

  def test_bare_string_code_keeps_code_only_matching_across_systems
    conditions = [ { codes: [ "154283005" ], name: "Tuberculosis", urgency: "24h" } ]
    service = build_service(conditions: conditions)
    result = service.check(condition: FHIR::Coding.new(system: ICD10, code: "154283005"))

    assert result.reportable?
  end

  # =============================================================================
  # RESULT SHAPE
  # =============================================================================

  def test_result_is_a_value_object
    service = build_service(conditions: reportable_conditions)
    result = service.check(condition: fhir_condition("A15.0", "TB"))

    assert_kind_of Rook::ReportableConditionService::Result, result
  end

  def test_result_includes_reporting_jurisdiction
    service = build_service(conditions: reportable_conditions, jurisdiction: "NY")
    result = service.check(condition: fhir_condition("A15.0", "TB"))

    assert_equal "NY", result.jurisdiction
  end

  def test_result_includes_urgency
    service = build_service(conditions: reportable_conditions)
    result = service.check(condition: fhir_condition("A15.0", "TB"))

    assert_equal "24h", result.urgency
  end

  # =============================================================================
  # EDGE CASES
  # =============================================================================

  def test_nil_condition_is_not_reportable
    service = build_service(conditions: reportable_conditions)
    result = service.check(condition: nil)

    refute result.reportable?
  end

  def test_condition_without_codings_is_not_reportable
    service = build_service(conditions: reportable_conditions)
    result = service.check(condition: FHIR::Condition.new)

    refute result.reportable?
  end

  def test_blank_coding_code_is_not_reportable
    service = build_service(conditions: reportable_conditions)
    result = service.check(condition: FHIR::Coding.new(system: ICD10, code: " "))

    refute result.reportable?
  end

  def test_empty_condition_list_returns_not_reportable
    service = build_service(conditions: [])
    result = service.check(condition: fhir_condition("A15.0", "TB"))

    refute result.reportable?
  end

  private

  def build_service(conditions:, jurisdiction: "US")
    Rook::ReportableConditionService.new(
      conditions: conditions,
      jurisdiction: jurisdiction
    )
  end

  def fhir_condition(code, display)
    FHIR::Condition.new(
      code: { coding: [ { system: ICD10, code: code, display: display } ] }
    )
  end

  def verification_status(code)
    FHIR::CodeableConcept.new(
      coding: [ {
        system: Rook::ReportableConditionService::VERIFICATION_STATUS_SYSTEM, code: code
      } ]
    )
  end

  def reportable_conditions
    [
      { codes: [ "A15.0", "A15.1", "A15.2", "A15.3" ], name: "Tuberculosis", urgency: "24h" },
      { codes: [ "B05.0", "B05.1", "B05.9" ], name: "Measles", urgency: "immediate" },
      { codes: [ "A01.0" ], name: "Typhoid fever", urgency: "24h" },
      { codes: [ "B20" ], name: "HIV", urgency: "7d" }
    ]
  end
end
