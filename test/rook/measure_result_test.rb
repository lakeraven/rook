# frozen_string_literal: true

require "test_helper"

# The engine-neutral result type is MeasureReport-backed (rook#92): population
# counts, period, and score live in a FHIR summary MeasureReport, and the
# scalar readers project from it. Care gaps ride alongside and are embedded as
# a contained, subject-list-shaped FHIR List of patient references.
class Rook::MeasureResultTest < Minitest::Test
  FakeMeasure = Struct.new(:id, :title)
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

  def test_zero_denominator_scores_zero
    empty = Rook::MeasureResult.from_counts(measure: @measure, period: @period,
      denominator: 0, numerator: 0)

    assert_equal 0.0, empty.rate
    assert_equal 0.0, empty.rate_percent
  end

  def test_care_gaps_ride_alongside_with_patient_references
    assert_equal @gaps, @result.care_gaps
    assert_equal "Patient/pt-001", @result.care_gaps.first.patient_reference
  end

  def test_care_gap_worklist_is_contained_as_a_subject_list
    list = @result.measure_report.contained.find { |r| r.is_a?(FHIR::List) }

    refute_nil list
    assert_equal "current", list.status
    assert_equal [ "Patient/pt-001" ], list.entry.map { |e| e.item.reference }
    assert_equal [ "Casey Alpha" ], list.entry.map { |e| e.item.display }
  end

  def test_measure_report_is_valid_fhir
    assert_empty @result.measure_report.validate
  end
end
