# frozen_string_literal: true

require "test_helper"

class Rook::ReportingPeriodTest < Minitest::Test
  def setup
    @period = Rook::ReportingPeriod.new(Date.new(2025, 1, 1), Date.new(2025, 12, 31))
  end

  def test_wraps_an_inclusive_date_range
    wrapped = Rook::ReportingPeriod.wrap(Date.new(2025, 1, 1)..Date.new(2025, 12, 31))

    assert_equal @period, wrapped
    assert_same @period, Rook::ReportingPeriod.wrap(@period)
  end

  def test_covers_dates_inclusively
    assert @period.cover?(Date.new(2025, 1, 1))
    assert @period.cover?(Date.new(2025, 12, 31))
    refute @period.cover?(Date.new(2024, 12, 31))
    refute @period.cover?(Date.new(2026, 1, 1))
  end

  def test_range_compatible_accessors
    assert_equal Date.new(2025, 1, 1), @period.first
    assert_equal Date.new(2025, 12, 31), @period.last
    assert_equal Date.new(2025, 12, 31), @period.end
  end

  def test_rejects_an_inverted_period
    assert_raises(ArgumentError) do
      Rook::ReportingPeriod.new(Date.new(2025, 12, 31), Date.new(2025, 1, 1))
    end
  end

  def test_projects_a_fhir_period
    fhir_period = @period.to_fhir_period

    assert_instance_of FHIR::Period, fhir_period
    assert_equal "2025-01-01", fhir_period.start
    assert_equal "2025-12-31", fhir_period.end
  end
end
