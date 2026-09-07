# frozen_string_literal: true

require "test_helper"
require "rook/demo"

# DEMO / REFERENCE ONLY — asserts the hardcoded UDS demo measures compute the
# known denominator / numerator / rate over the committed synthetic population,
# and that the report renders.
class Rook::Demo::UDSReportTest < Minitest::Test
  def setup
    @report = Rook::Demo::Report.default
  end

  # ---------------------------------------------------------------------------
  # Population
  # ---------------------------------------------------------------------------

  def test_loads_the_synthetic_population
    assert_equal 35, @report.patient_count
  end

  def test_patients_carry_aian_tribal_affiliation
    population = Rook::Demo::SyntheticPopulation.default
    assert(population.patients.all? { |p| p.tribal_affiliation&.include?("Synthetic tribal affiliation") })
  end

  # ---------------------------------------------------------------------------
  # Measure 1 — Diabetes: HbA1c Poor Control (>9%)
  # ---------------------------------------------------------------------------

  def test_diabetes_hba1c_poor_control_counts
    result = result_for("uds-6b-diabetes-hba1c-poor-control")

    assert_equal 20, result.denominator, "18-75 diabetics; excludes 2 out-of-age diabetics"
    assert_equal 8, result.numerator, "5 latest >9% + 3 with no HbA1c in period"
    assert_in_delta 0.40, result.rate, 0.0001
    assert_equal 40.0, result.rate_percent
  end

  def test_diabetes_inverse_measure_declares_decrease_improvement_notation
    result = result_for("uds-6b-diabetes-hba1c-poor-control")

    assert_equal "decrease", result.measure_report.improvementNotation.coding.first.code
  end

  def test_blood_pressure_measure_declares_increase_improvement_notation
    result = result_for("uds-6b-controlling-high-blood-pressure")

    assert_equal "increase", result.measure_report.improvementNotation.coding.first.code
  end

  def test_results_carry_the_clinic_label_as_the_report_reporter
    @report.results.each do |result|
      assert_equal @report.clinic_label, result.measure_report.reporter.display
    end
  end

  def test_diabetes_care_gap_worklist_matches_numerator
    result = result_for("uds-6b-diabetes-hba1c-poor-control")

    assert_equal result.numerator, result.care_gaps.size
    assert(result.care_gaps.any? { |g| g.reason.include?("No HbA1c recorded") })
    assert(result.care_gaps.any? { |g| g.reason.include?("exceeds 9%") })
  end

  # ---------------------------------------------------------------------------
  # Measure 2 — Controlling High Blood Pressure (<140/90)
  # ---------------------------------------------------------------------------

  def test_controlling_high_blood_pressure_counts
    result = result_for("uds-6b-controlling-high-blood-pressure")

    assert_equal 15, result.denominator, "18-85 hypertensives"
    assert_equal 9, result.numerator, "most-recent BP <140/90"
    assert_in_delta 0.60, result.rate, 0.0001
    assert_equal 60.0, result.rate_percent
  end

  def test_blood_pressure_care_gaps_are_denominator_minus_numerator
    result = result_for("uds-6b-controlling-high-blood-pressure")

    assert_equal result.denominator - result.numerator, result.care_gaps.size
    assert(result.care_gaps.any? { |g| g.reason.include?("No blood pressure recorded") })
    assert(result.care_gaps.any? { |g| g.reason.include?("not controlled") })
  end

  # ---------------------------------------------------------------------------
  # Rendering
  # ---------------------------------------------------------------------------

  def test_text_renderer_includes_measures_and_gaps
    text = Rook::Demo::ReportRenderer.new(@report).to_text

    assert_includes text, "Diabetes: HbA1c Poor Control (>9%)"
    assert_includes text, "Controlling High Blood Pressure (<140/90)"
    assert_includes text, "Care-gap worklist"
    assert_includes text, "SYNTHETIC DATA"
  end

  def test_html_renderer_produces_a_full_page
    html = Rook::Demo::ReportRenderer.new(@report).to_html

    assert_includes html, "<!DOCTYPE html>"
    assert_includes html, "UDS Quality Report"
    assert_includes html, "Denominator"
    assert_includes html, "40.0%"
    assert_includes html, "60.0%"
    # No real PHI / partner / tribe names leak into the output.
    refute_match(/example demo org|example consortium|broken rock/i, html)
  end

  private

  def result_for(measure_id)
    @report.results.find { |r| r.measure.id == measure_id } ||
      flunk("no result for measure #{measure_id}")
  end
end
