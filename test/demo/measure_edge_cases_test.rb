# frozen_string_literal: true

require "test_helper"
require "rook/demo"

# DEMO / REFERENCE ONLY — edge cases the committed fixture doesn't exercise:
# incomplete observations must degrade to care gaps with readable reasons, not
# abort the whole report, and the injected ValueSetResolver must actually
# drive evaluation (no hardcoded code lists hiding behind it).
class Rook::Demo::MeasureEdgeCasesTest < Minitest::Test
  PERIOD = Rook::ReportingPeriod.new(Date.new(2025, 1, 1), Date.new(2025, 12, 31))

  def build_patient(id:, condition_codes:, observations:)
    Rook::Demo::SyntheticPopulation::Patient.new(
      id: id, family_name: "Synthetic", given_name: "Casey", gender: "female",
      birth_date: Date.new(1970, 6, 15), tribal_affiliation: nil,
      condition_codes: condition_codes, observations: observations
    )
  end

  # ---------------------------------------------------------------------------
  # Partial BP panel (85354-9 with only one component)
  # ---------------------------------------------------------------------------

  def partial_bp_patient
    partial_panel = Rook::Demo::SyntheticPopulation::Observation.new(
      loinc: "85354-9", value: nil, effective_date: Date.new(2025, 6, 1),
      components: { "8480-6" => 132 } # systolic only; no diastolic
    )
    build_patient(id: "edge-bp-1", condition_codes: [ "I10" ], observations: [ partial_panel ])
  end

  def test_partial_bp_panel_is_a_care_gap_not_a_crash
    measure = Rook::Demo::Measures::ControllingHighBloodPressure.new
    patient = partial_bp_patient

    refute measure.in_numerator?(patient, PERIOD)
    assert measure.care_gap?(patient, PERIOD)
    assert_match(/incomplete blood pressure/i, measure.gap_reason(patient, PERIOD))
  end

  def test_partial_bp_panel_does_not_abort_evaluation
    result = Rook::Demo::Measures::ControllingHighBloodPressure.new.evaluate([ partial_bp_patient ], PERIOD)

    assert_equal 1, result.denominator
    assert_equal 0, result.numerator
    assert_equal 1, result.care_gaps.size
  end

  # ---------------------------------------------------------------------------
  # HbA1c Observation without a numeric result (e.g. dataAbsentReason)
  # ---------------------------------------------------------------------------

  def valueless_hba1c_patient
    valueless = Rook::Demo::SyntheticPopulation::Observation.new(
      loinc: "4548-4", value: nil, effective_date: Date.new(2025, 3, 10), components: {}
    )
    build_patient(id: "edge-a1c-1", condition_codes: [ "E11.9" ], observations: [ valueless ])
  end

  def test_valueless_hba1c_counts_as_no_usable_result
    measure = Rook::Demo::Measures::DiabetesHbA1cPoorControl.new
    patient = valueless_hba1c_patient

    # Missing-result rule: no usable HbA1c -> poor control (numerator/gap).
    assert measure.in_numerator?(patient, PERIOD)
    assert measure.care_gap?(patient, PERIOD)
    assert_match(/no usable result/i, measure.gap_reason(patient, PERIOD))
  end

  def test_valueless_hba1c_does_not_abort_evaluation
    result = Rook::Demo::Measures::DiabetesHbA1cPoorControl.new.evaluate([ valueless_hba1c_patient ], PERIOD)

    assert_equal 1, result.denominator
    assert_equal 1, result.numerator
    assert_equal 1, result.care_gaps.size
  end

  # ---------------------------------------------------------------------------
  # ValueSetResolver injection actually drives evaluation
  # ---------------------------------------------------------------------------

  def test_a_custom_value_set_resolver_changes_evaluation
    population = Rook::Demo::SyntheticPopulation.default
    default_result = Rook::Demo::Measures::DiabetesHbA1cPoorControl.new
      .evaluate(population.patients, PERIOD)

    # Same measure, but the HbA1c value set expands to a code no fixture
    # Observation carries: every diabetic now reads as "no HbA1c recorded".
    codes = Rook::Demo::ValueSets::CODES.merge(
      Rook::Demo::ValueSets::HBA1C_LABORATORY_TEST => %w[0000-0]
    )
    rewired = Rook::Demo::Measures::DiabetesHbA1cPoorControl.new(
      value_set_resolver: Rook::InMemoryValueSetResolver.new(codes)
    )
    rewired_result = rewired.evaluate(population.patients, PERIOD)

    assert_equal default_result.denominator, rewired_result.denominator
    refute_equal default_result.numerator, rewired_result.numerator,
      "expected the injected resolver to change the numerator (no hardcoded codes)"
    assert_equal rewired_result.denominator, rewired_result.numerator,
      "with no resolvable HbA1c code, every diabetic is in the poor-control numerator"
  end
end
