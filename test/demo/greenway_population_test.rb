# frozen_string_literal: true

require "test_helper"
require "rook/demo"

# DEMO / REFERENCE ONLY — the Greenway-shaped synthetic bulk export loads
# through the same ingest seam as the RPMS and Epic populations and the SAME
# measure implementations compute its (different, hand-authored) rates.
class Rook::Demo::GreenwayPopulationTest < Minitest::Test
  def setup
    @population = Rook::Demo::SyntheticPopulation.greenway
  end

  def result_for(report, measure_id)
    report.results.find { |r| r.measure.id == measure_id } ||
      flunk("no result for #{measure_id}")
  end

  # ---------------------------------------------------------------------------
  # Ingest seam and provenance
  # ---------------------------------------------------------------------------

  def test_loads_the_greenway_population_through_the_ingest_seam
    assert_equal 24, @population.patients.size
  end

  def test_greenway_descriptors_carry_the_greenway_platform
    assert_equal :greenway, Rook::Demo::SyntheticPopulation::GREENWAY_PRIMARY_SOURCE.platform
    assert Rook::Demo::SyntheticPopulation::GREENWAY_PRIMARY_SOURCE.primary?
    assert_equal :greenway, Rook::Demo::SyntheticPopulation::GREENWAY_SUPPLEMENTAL_SOURCE.platform
    assert Rook::Demo::SyntheticPopulation::GREENWAY_SUPPLEMENTAL_SOURCE.supplemental?
  end

  def test_resources_carry_per_channel_greenway_provenance
    observations = @population.patients.flat_map(&:observations)
    supplemental, clinical = observations.partition(&:supplemental_attribute?)

    refute_empty clinical
    assert(clinical.all? { |o| o.source_id == "demo-greenway-fhir" })
    refute_empty supplemental
    assert(supplemental.all? { |o| o.source_id == "demo-greenway-supplemental" })

    coverages = @population.patients.flat_map(&:coverages)
    refute_empty coverages
    assert(coverages.all? { |c| c.source_id == "demo-greenway-supplemental" })
  end

  # ---------------------------------------------------------------------------
  # Greenway export idioms survive the flattener
  # ---------------------------------------------------------------------------

  def test_patient_ids_are_guid_shaped
    guid = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
    @population.patients.each do |patient|
      assert_match guid, patient.id, "expected a GUID-shaped id, got #{patient.id}"
    end
  end

  def test_greenway_patients_have_no_tribal_affiliation_extension
    assert(@population.patients.all? { |p| p.tribal_affiliation.nil? })
  end

  def test_icd_first_condition_codings_still_match_value_sets
    diabetic = @population.patients.count { |p| p.condition?(%w[E11.9]) }
    also_by_snomed = @population.patients.count { |p| p.condition?(%w[44054006]) }

    assert_equal 13, diabetic, "12 in-age diabetics + 1 age-17 diabetic"
    assert_equal diabetic, also_by_snomed
  end

  def test_offset_timestamps_resolve_to_the_local_calendar_date
    # "2025-04-22T08:45:00-06:00" is the practice's local date 2025-04-22.
    dates = @population.patients.flat_map(&:observations)
      .reject(&:supplemental_attribute?).map(&:effective_date)
    assert_includes dates, Date.new(2025, 4, 22)
    assert(dates.all? { |d| d.is_a?(Date) })
  end

  def test_dual_eligible_patient_carries_both_coverages
    dual = @population.patients.filter_map { |p|
      categories = p.current_coverages(Date.new(2025, 12, 31)).map(&:payer_category).sort
      categories if categories.length > 1
    }

    assert_includes dual, %w[medicaid medicare]
  end

  # ---------------------------------------------------------------------------
  # Same measures, known (different) rates
  # ---------------------------------------------------------------------------

  def test_uds_measures_compute_the_greenway_population_rates
    report = Rook::Demo::Report.uds(population: @population,
      clinic_label: Rook::Demo::Report::GREENWAY_CLINIC_LABEL)

    diabetes = result_for(report, "uds-6b-diabetes-hba1c-poor-control")
    assert_equal 12, diabetes.denominator, "18-75 diabetics inclusive; excludes the age-17 diabetic"
    assert_equal 5, diabetes.numerator, "3 latest >9% + 1 with no HbA1c + 1 pre-period only"
    assert_in_delta 5.0 / 12, diabetes.rate, 0.0001

    bp = result_for(report, "uds-6b-controlling-high-blood-pressure")
    assert_equal 10, bp.denominator, "8 in-age hypertension-only + 2 dual-diagnosis; excludes age 86"
    assert_equal 7, bp.numerator
    assert_in_delta 0.70, bp.rate, 0.0001
  end

  def test_gpra_depression_screening_excludes_the_under_12_patient
    report = Rook::Demo::Report.gpra(population: @population,
      clinic_label: Rook::Demo::Report::GREENWAY_CLINIC_LABEL)

    screening = result_for(report, "demo-gpra-depression-screening")
    assert_equal 23, screening.denominator, "24 patients less the age-9 child"
    assert_equal 15, screening.numerator
  end

  def test_reports_render_over_the_greenway_population
    uds = Rook::Demo::Report.uds(population: @population,
      clinic_label: Rook::Demo::Report::GREENWAY_CLINIC_LABEL)
    gpra = Rook::Demo::Report.gpra(population: @population,
      clinic_label: Rook::Demo::Report::GREENWAY_CLINIC_LABEL)

    [ Rook::Demo::ReportRenderer.new(uds).to_html,
      Rook::Demo::GPRAReportRenderer.new(gpra).to_html ].each do |html|
      assert_includes html, "a community health center on Greenway (synthetic demo data)"
    end
  end

  def test_all_three_populations_are_disjoint_by_resource_identity
    fixtures = Rook::Demo::SyntheticPopulation::FIXTURES_DIR
    sp = Rook::Demo::SyntheticPopulation
    feeds = [
      [ File.join(fixtures, "primary_fhir"), sp::PRIMARY_SOURCE ],
      [ File.join(fixtures, "supplemental"), sp::SUPPLEMENTAL_SOURCE ],
      [ File.join(fixtures, "epic", "primary_fhir"), sp::EPIC_PRIMARY_SOURCE ],
      [ File.join(fixtures, "epic", "supplemental"), sp::EPIC_SUPPLEMENTAL_SOURCE ],
      [ File.join(fixtures, "greenway", "primary_fhir"), sp::GREENWAY_PRIMARY_SOURCE ],
      [ File.join(fixtures, "greenway", "supplemental"), sp::GREENWAY_SUPPLEMENTAL_SOURCE ]
    ].map { |dir, source| Rook::Ingest::NdjsonFeed.directory(dir, source: source) }

    resources = Rook::Ingest.load(*feeds)
    assert_equal 35 + 18 + 24, resources.count { |r| r["resourceType"] == "Patient" }
  end
end
