# frozen_string_literal: true

require "test_helper"

class Rook::ReportableConditionServiceTest < Minitest::Test
  # =============================================================================
  # DETECTION — REPORTABLE CONDITIONS
  # =============================================================================

  def test_detects_tuberculosis_as_reportable
    service = build_service(conditions: reportable_conditions)
    result = service.check(diagnosis_code: "A15.0", diagnosis_display: "Pulmonary tuberculosis")

    assert result[:reportable]
    assert_equal "Tuberculosis", result[:condition_name]
  end

  def test_detects_measles_as_reportable
    service = build_service(conditions: reportable_conditions)
    result = service.check(diagnosis_code: "B05.9", diagnosis_display: "Measles")

    assert result[:reportable]
    assert_equal "Measles", result[:condition_name]
  end

  def test_non_reportable_condition_returns_false
    service = build_service(conditions: reportable_conditions)
    result = service.check(diagnosis_code: "E11.9", diagnosis_display: "Type 2 diabetes")

    refute result[:reportable]
    assert_nil result[:condition_name]
  end

  def test_detects_by_code_not_just_display
    service = build_service(conditions: reportable_conditions)
    result = service.check(diagnosis_code: "A15.0", diagnosis_display: "Something else")

    assert result[:reportable]
  end

  # =============================================================================
  # RESULT SHAPE
  # =============================================================================

  def test_result_includes_reporting_jurisdiction
    service = build_service(conditions: reportable_conditions, jurisdiction: "NY")
    result = service.check(diagnosis_code: "A15.0", diagnosis_display: "TB")

    assert_equal "NY", result[:jurisdiction]
  end

  def test_result_includes_urgency
    service = build_service(conditions: reportable_conditions)
    result = service.check(diagnosis_code: "A15.0", diagnosis_display: "TB")

    assert result.key?(:urgency)
  end

  # =============================================================================
  # EDGE CASES
  # =============================================================================

  def test_nil_diagnosis_code_is_not_reportable
    service = build_service(conditions: reportable_conditions)
    result = service.check(diagnosis_code: nil, diagnosis_display: "Unknown")

    refute result[:reportable]
  end

  def test_empty_condition_list_returns_not_reportable
    service = build_service(conditions: [])
    result = service.check(diagnosis_code: "A15.0", diagnosis_display: "TB")

    refute result[:reportable]
  end

  private

  def build_service(conditions:, jurisdiction: "US")
    Rook::ReportableConditionService.new(
      conditions: conditions,
      jurisdiction: jurisdiction
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
