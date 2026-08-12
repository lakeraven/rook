# frozen_string_literal: true

require "test_helper"
require "rook/demo"

# DEMO / REFERENCE ONLY — asserts the GPRA view packages the same measure
# computations as the UDS view over the committed synthetic population, adds the
# GPRA depression-screening measure, and renders in the IHS CRS / GPRA style.
class Rook::Demo::GPRAReportTest < Minitest::Test
  def setup
    @report = Rook::Demo::Report.gpra
  end

  def test_gpra_report_uses_gpra_framework_and_three_measures
    assert_equal "IHS CRS / GPRA National Clinical Measures", @report.framework
    assert_equal 3, @report.results.size
  end

  # ---------------------------------------------------------------------------
  # Shared measures reuse the UDS computations (same denom/num/rate)
  # ---------------------------------------------------------------------------

  def test_gpra_diabetes_matches_uds_computation
    gpra = result_for("gpra-diabetes-poor-glycemic-control")
    uds = uds_result_for("uds-6b-diabetes-hba1c-poor-control")

    assert_equal "Diabetes: Poor Glycemic Control (A1c > 9.0%)", gpra.measure.title
    assert_equal [uds.denominator, uds.numerator, uds.rate], [gpra.denominator, gpra.numerator, gpra.rate]
    assert_equal 20, gpra.denominator
    assert_equal 8, gpra.numerator
    assert_in_delta 0.40, gpra.rate, 0.0001
  end

  def test_gpra_blood_pressure_matches_uds_computation
    gpra = result_for("gpra-controlling-high-blood-pressure")
    uds = uds_result_for("uds-6b-controlling-high-blood-pressure")

    assert_equal [uds.denominator, uds.numerator, uds.rate], [gpra.denominator, gpra.numerator, gpra.rate]
    assert_equal 15, gpra.denominator
    assert_equal 9, gpra.numerator
    assert_in_delta 0.60, gpra.rate, 0.0001
  end

  # ---------------------------------------------------------------------------
  # GPRA-only measure — Depression Screening
  # ---------------------------------------------------------------------------

  def test_depression_screening_counts
    result = result_for("gpra-depression-screening")

    assert_equal 35, result.denominator, "all synthetic patients are age 12+"
    assert_equal 28, result.numerator, "patients screened with a PHQ-9 in the period"
    assert_in_delta 0.80, result.rate, 0.0001
    assert_equal 80.0, result.rate_percent
  end

  def test_depression_screening_care_gaps_are_unscreened_patients
    result = result_for("gpra-depression-screening")

    assert_equal result.denominator - result.numerator, result.care_gaps.size
    assert(result.care_gaps.all? { |g| g.reason.include?("No depression screening recorded") })
  end

  # ---------------------------------------------------------------------------
  # Rendering — IHS CRS / GPRA style
  # ---------------------------------------------------------------------------

  def test_text_renderer_shows_crs_gpra_summary
    text = Rook::Demo::GPRAReportRenderer.new(@report).to_text

    assert_includes text, "IHS CRS / GPRA National Clinical Measures"
    assert_includes text, "Measure summary"
    assert_includes text, "Depression Screening (PHQ, age 12+)"
    assert_includes text, "Care-gap worklist"
    assert_includes text, "SYNTHETIC DATA"
  end

  def test_html_renderer_produces_a_full_page
    html = Rook::Demo::GPRAReportRenderer.new(@report).to_html

    assert_includes html, "<!DOCTYPE html>"
    assert_includes html, "IHS CRS / GPRA National Clinical Measures"
    assert_includes html, "80.0%"
    refute_match(/good medicine|mcuih|yakama/i, html)
  end

  private

  def result_for(measure_id)
    @report.results.find { |r| r.measure.id == measure_id } ||
      flunk("no GPRA result for measure #{measure_id}")
  end

  def uds_result_for(measure_id)
    Rook::Demo::Report.uds.results.find { |r| r.measure.id == measure_id } ||
      flunk("no UDS result for measure #{measure_id}")
  end
end
