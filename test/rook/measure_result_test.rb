# frozen_string_literal: true

require "test_helper"

# The engine-neutral result type is MeasureReport-backed (rook#92): population
# counts, period, and score live in a FHIR summary MeasureReport, and the
# scalar readers project from it. Care gaps ride alongside on the Ruby object
# only — the summary report carries no subject-level data (mrt-2).
class Rook::MeasureResultTest < Minitest::Test
  FakeMeasure = Struct.new(:id, :title)
  FakeInverseMeasure = Struct.new(:id, :title) do
    def improvement_notation
      :decrease
    end
  end
  FakePatient = Struct.new(:id, :name)

  def setup
    @measure = FakeMeasure.new("demo-measure", "Demo Measure")
    @period = Rook::ReportingPeriod.new(Date.new(2025, 1, 1), Date.new(2025, 12, 31))
    @gaps = [
      Rook::MeasureResult::CareGap.new(patient: FakePatient.new("pt-001", "Casey Alpha"),
        reason: "No screening in period")
    ]
    @result = Rook::MeasureResult.from_counts(
      measure: @measure, period: @period, denominator: 20, numerator: 8, care_gaps: @gaps
    )
  end

  def test_wraps_a_summary_measure_report
    report = @result.measure_report

    assert_instance_of FHIR::MeasureReport, report
    assert_equal "summary", report.type
    assert_equal "complete", report.status
    assert_equal "#{Rook::MeasureResult::MEASURE_CANONICAL_BASE}/demo-measure", report.measure
    assert_equal "2025-01-01", report.period.start
    assert_equal "2025-12-31", report.period.end
    assert_same report, @result.to_fhir
  end

  def test_scalar_readers_project_from_the_measure_report
    assert_equal 20, @result.denominator
    assert_equal 8, @result.numerator
    assert_in_delta 0.40, @result.rate, 0.0001
    assert_equal 40.0, @result.rate_percent
    assert_in_delta 0.40, @result.measure_report.group.first.measureScore.value, 0.0001
  end

  def test_zero_denominator_omits_measure_score_but_rate_reads_zero
    empty = Rook::MeasureResult.from_counts(measure: @measure, period: @period,
      denominator: 0, numerator: 0)

    assert_nil empty.measure_report.group.first.measureScore
    assert_equal 0.0, empty.rate
    assert_equal 0.0, empty.rate_percent
  end

  def test_care_gaps_ride_alongside_with_patient_references
    assert_equal @gaps, @result.care_gaps
    assert_equal "Patient/pt-001", @result.care_gaps.first.patient_reference
  end

  def test_summary_report_carries_no_contained_or_subject_level_data
    report = @result.measure_report

    assert_empty report.contained
    assert_empty report.evaluatedResource
    report.group.each do |group|
      group.population.each { |population| assert_nil population.subjectResults }
    end
  end

  # FakeMeasure declares no improvement notation, so the seam falls back to
  # :increase (the FHIR default direction).
  def test_improvement_notation_defaults_to_increase_when_the_measure_declares_none
    coding = @result.measure_report.improvementNotation.coding.first

    assert_equal "http://terminology.hl7.org/CodeSystem/measure-improvement-notation", coding.system
    assert_equal "increase", coding.code
  end

  def test_improvement_notation_defaults_from_the_measure_declaration
    inverse_measure = FakeInverseMeasure.new("demo-inverse-measure", "Demo Inverse Measure")
    result = Rook::MeasureResult.from_counts(
      measure: inverse_measure, period: @period, denominator: 20, numerator: 8
    )

    assert_equal "decrease", result.measure_report.improvementNotation.coding.first.code
  end

  def test_explicit_improvement_notation_overrides_the_measure_declaration
    inverse_measure = FakeInverseMeasure.new("demo-inverse-measure", "Demo Inverse Measure")
    result = Rook::MeasureResult.from_counts(
      measure: inverse_measure, period: @period, denominator: 20, numerator: 8,
      improvement_notation: :increase
    )

    assert_equal "increase", result.measure_report.improvementNotation.coding.first.code
  end

  def test_improvement_notation_decrease_for_inverse_measures
    inverse = Rook::MeasureResult.from_counts(measure: @measure, period: @period,
      denominator: 20, numerator: 8, improvement_notation: :decrease)
    coding = inverse.measure_report.improvementNotation.coding.first

    assert_equal "http://terminology.hl7.org/CodeSystem/measure-improvement-notation", coding.system
    assert_equal "decrease", coding.code
  end

  def test_rejects_an_unknown_improvement_notation
    assert_raises(ArgumentError) do
      Rook::MeasureResult.from_counts(measure: @measure, period: @period,
        denominator: 20, numerator: 8, improvement_notation: :sideways)
    end
  end

  def test_rejects_a_negative_denominator
    assert_raises(ArgumentError) do
      Rook::MeasureResult.from_counts(measure: @measure, period: @period,
        denominator: -1, numerator: 0)
    end
  end

  def test_rejects_a_negative_numerator
    assert_raises(ArgumentError) do
      Rook::MeasureResult.from_counts(measure: @measure, period: @period,
        denominator: 10, numerator: -1)
    end
  end

  def test_rejects_non_integer_counts
    assert_raises(ArgumentError) do
      Rook::MeasureResult.from_counts(measure: @measure, period: @period,
        denominator: 10.0, numerator: 4)
    end
    assert_raises(ArgumentError) do
      Rook::MeasureResult.from_counts(measure: @measure, period: @period,
        denominator: 10, numerator: "4")
    end
  end

  def test_rejects_a_numerator_exceeding_the_denominator
    assert_raises(ArgumentError) do
      Rook::MeasureResult.from_counts(measure: @measure, period: @period,
        denominator: 5, numerator: 6)
    end
  end

  def test_measure_report_is_valid_fhir
    assert_empty @result.measure_report.validate
  end

  def test_reporter_display_lands_as_the_report_reporter
    result = Rook::MeasureResult.from_counts(
      measure: @measure, period: @period, denominator: 20, numerator: 8,
      reporter_display: "Example Clinic (synthetic)"
    )

    assert_equal "Example Clinic (synthetic)", result.measure_report.reporter.display
    assert_empty result.measure_report.validate
  end

  def test_reporter_is_absent_when_no_reporter_display_given
    assert_nil @result.measure_report.reporter
  end

  def test_rejects_wrapping_a_report_without_population_counts
    bare = FHIR::MeasureReport.new(status: "complete", type: "summary")

    error = assert_raises(ArgumentError) do
      Rook::MeasureResult.new(measure: @measure, period: @period, measure_report: bare)
    end
    assert_match(/group/, error.message)
  end

  def test_rejects_wrapping_a_report_missing_a_numerator_population
    report = FHIR::MeasureReport.new(
      status: "complete", type: "summary",
      group: [ {
        population: [ { code: { coding: [ { code: "denominator" } ] }, count: 10 } ]
      } ]
    )

    error = assert_raises(ArgumentError) do
      Rook::MeasureResult.new(measure: @measure, period: @period, measure_report: report)
    end
    assert_match(/numerator/, error.message)
  end

  def test_rejects_a_nonzero_denominator_report_without_a_measure_score
    report = FHIR::MeasureReport.new(
      status: "complete", type: "summary",
      group: [ {
        population: [
          { code: { coding: [ { code: "denominator" } ] }, count: 10 },
          { code: { coding: [ { code: "numerator" } ] }, count: 4 }
        ]
      } ]
    )

    error = assert_raises(ArgumentError) do
      Rook::MeasureResult.new(measure: @measure, period: @period, measure_report: report)
    end
    assert_match(/measureScore/, error.message)
  end
end
