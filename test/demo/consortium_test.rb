# frozen_string_literal: true

require "test_helper"
require "rook/demo"

# DEMO / REFERENCE ONLY — asserts the 3-clinic consortium demo rolls up
# per-clinic GPRA results correctly (denominator/numerator sums, rates in
# range), that the clinics produce visibly different rates, and that the
# rendered HTML dashboard is self-contained and free of real partner names.
class Rook::Demo::ConsortiumTest < Minitest::Test
  def setup
    @consortium = Rook::Demo::Consortium.build
  end

  def test_rejects_construction_with_zero_clinics
    error = assert_raises(ArgumentError) { Rook::Demo::Consortium.new(profiles: []) }
    assert_match(/at least one clinic/, error.message)
  end

  def test_inverse_diabetes_rollup_declares_decrease_improvement_notation
    rollup = @consortium.rollup.find { |r| r.measure.id == "demo-gpra-diabetes-poor-glycemic-control" }
    coding = rollup.result.measure_report.improvementNotation.coding.first

    assert_equal "decrease", coding.code
  end

  def test_clinic_reports_and_rollup_are_distinguishable_by_reporter
    @consortium.clinic_reports.each do |cr|
      cr.report.results.each do |result|
        assert_equal cr.name, result.measure_report.reporter.display
      end
    end
    @consortium.rollup.each do |rollup|
      assert_equal Rook::Demo::Consortium::NAME, rollup.result.measure_report.reporter.display
    end
  end

  def test_consortium_has_three_clinics
    assert_equal 3, @consortium.clinic_count
    assert_equal 3, @consortium.clinic_reports.size
  end

  def test_total_patients_is_the_sum_of_clinic_patient_counts
    assert_equal 60, @consortium.clinic_reports[0].patient_count
    assert_equal 30, @consortium.clinic_reports[1].patient_count
    assert_equal 45, @consortium.clinic_reports[2].patient_count
    assert_equal 135, @consortium.total_patients
  end

  def test_rollup_denominator_and_numerator_are_sums_of_clinic_results
    @consortium.rollup.each do |rollup|
      clinic_results = @consortium.clinic_reports.map do |cr|
        cr.report.results.find { |r| r.measure.id == rollup.measure.id }
      end

      assert_equal clinic_results.sum(&:denominator), rollup.denominator
      assert_equal clinic_results.sum(&:numerator), rollup.numerator
    end
  end

  def test_rollup_rates_are_within_zero_to_one
    @consortium.rollup.each do |rollup|
      assert_operator rollup.rate, :>=, 0.0
      assert_operator rollup.rate, :<=, 1.0
    end
  end

  def test_clinics_produce_different_diabetes_control_rates
    rates = @consortium.clinic_reports.map do |cr|
      cr.report.results.find { |r| r.measure.id == "demo-gpra-diabetes-poor-glycemic-control" }.rate
    end

    refute_equal 1, rates.uniq.size, "expected the three clinics to have distinct diabetes-control rates"
  end

  def test_html_dashboard_contains_badge_clinic_names_and_a_table
    html = Rook::Demo::ConsortiumDashboardRenderer.new(@consortium).to_html

    assert_includes html, "SYNTHETIC DEMO"
    @consortium.clinic_reports.each do |cr|
      assert_includes html, cr.name
    end
    assert_includes html, "<table"
  end

  def test_dashboard_renders_only_the_defined_synthetic_clinic_names
    # Hygiene: the demo defines only synthetic clinic names; the dashboard must
    # render exactly those and introduce no other facility identities. (Kept as a
    # positive allowlist rather than a denylist so no real-world name is embedded
    # in this public repo.)
    html = Rook::Demo::ConsortiumDashboardRenderer.new(@consortium).to_html
    rendered = @consortium.clinic_reports.map(&:name)

    assert_equal 3, rendered.uniq.size
    rendered.each { |name| assert_includes html, name }
  end
end
