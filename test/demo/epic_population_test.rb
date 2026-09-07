# frozen_string_literal: true

require "test_helper"
require "rook/demo"

# DEMO / REFERENCE ONLY — the Epic-shaped synthetic bulk export (rook#101)
# loads through the same ingest seam as the first population and the SAME
# measure implementations compute its (different, hand-authored) rates.
class Rook::Demo::EpicPopulationTest < Minitest::Test
  def setup
    @population = Rook::Demo::SyntheticPopulation.epic
  end

  def result_for(report, measure_id)
    report.results.find { |r| r.measure.id == measure_id } ||
      flunk("no result for #{measure_id}")
  end

  # ---------------------------------------------------------------------------
  # Ingest seam and provenance
  # ---------------------------------------------------------------------------

  def test_loads_the_epic_population_through_the_ingest_seam
    assert_equal 18, @population.patients.size
  end

  def test_epic_descriptors_carry_the_epic_platform
    assert_equal :epic, Rook::Demo::SyntheticPopulation::EPIC_PRIMARY_SOURCE.platform
    assert Rook::Demo::SyntheticPopulation::EPIC_PRIMARY_SOURCE.primary?
    assert_equal :epic, Rook::Demo::SyntheticPopulation::EPIC_SUPPLEMENTAL_SOURCE.platform
    assert Rook::Demo::SyntheticPopulation::EPIC_SUPPLEMENTAL_SOURCE.supplemental?
  end

  def test_resources_carry_per_channel_epic_provenance
    observations = @population.patients.flat_map(&:observations)
    supplemental, clinical = observations.partition(&:supplemental_attribute?)

    refute_empty clinical
    assert(clinical.all? { |o| o.source_id == "demo-epic-fhir" })
    refute_empty supplemental
    assert(supplemental.all? { |o| o.source_id == "demo-epic-supplemental" })

    coverages = @population.patients.flat_map(&:coverages)
    refute_empty coverages
    assert(coverages.all? { |c| c.source_id == "demo-epic-supplemental" })
  end

  # ---------------------------------------------------------------------------
  # Epic export idioms survive the flattener
  # ---------------------------------------------------------------------------

  def test_patient_ids_are_epic_shaped_opaque_tokens
    @population.patients.each do |patient|
      assert_match(/\Ae\S+\.\S+\z/, patient.id, "expected an Epic-style id, got #{patient.id}")
    end
  end

  def test_epic_patients_have_no_tribal_affiliation_extension
    # Stock Epic tenants don't populate us-core-tribal-affiliation; the demo
    # pipeline (and its worklists) must degrade gracefully, not require it.
    assert(@population.patients.all? { |p| p.tribal_affiliation.nil? })
  end

  def test_snomed_first_condition_codings_still_match_value_sets
    # Epic problem-list exports code SNOMED-first with ICD-10-CM second; the
    # demo value sets carry both, so condition matching is order-independent.
    diabetic = @population.patients.count { |p| p.condition?(%w[44054006]) }
    also_by_icd = @population.patients.count { |p| p.condition?(%w[E11.9]) }

    assert_equal 11, diabetic, "10 in-age diabetics + 1 age-excluded"
    assert_equal diabetic, also_by_icd
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

  def test_uds_measures_compute_the_epic_population_rates
    report = Rook::Demo::Report.uds(population: @population,
      clinic_label: Rook::Demo::Report::EPIC_CLINIC_LABEL)

    diabetes = result_for(report, "uds-6b-diabetes-hba1c-poor-control")
    assert_equal 10, diabetes.denominator, "18-75 diabetics; excludes the age-79 diabetic"
    assert_equal 3, diabetes.numerator, "2 latest >9% + 1 with no HbA1c in period"
    assert_in_delta 0.30, diabetes.rate, 0.0001

    bp = result_for(report, "uds-6b-controlling-high-blood-pressure")
    assert_equal 8, bp.denominator, "6 hypertension-only + 2 dual-diagnosis diabetics"
    assert_equal 5, bp.numerator
    assert_in_delta 0.625, bp.rate, 0.0001
  end

  def test_gpra_depression_screening_rate
    report = Rook::Demo::Report.gpra(population: @population,
      clinic_label: Rook::Demo::Report::EPIC_CLINIC_LABEL)

    screening = result_for(report, "gpra-depression-screening")
    assert_equal 18, screening.denominator, "all patients are age 12+"
    assert_equal 12, screening.numerator
  end

  def test_reports_render_over_the_epic_population
    uds = Rook::Demo::Report.uds(population: @population,
      clinic_label: Rook::Demo::Report::EPIC_CLINIC_LABEL)
    gpra = Rook::Demo::Report.gpra(population: @population,
      clinic_label: Rook::Demo::Report::EPIC_CLINIC_LABEL)

    uds_html = Rook::Demo::ReportRenderer.new(uds).to_html
    gpra_html = Rook::Demo::GPRAReportRenderer.new(gpra).to_html

    [ uds_html, gpra_html ].each do |html|
      assert_includes html, "a tribal clinic on Epic (synthetic demo data)"
    end
    assert_includes Rook::Demo::ReportRenderer.new(uds).to_text, "Controlling High Blood Pressure"
  end

  def test_epic_and_default_populations_are_disjoint_by_resource_identity
    # The two fixture sets must be mergeable through one Ingest.load without
    # tripping the (resourceType, id) disjointness guard — that's what makes
    # a future multi-platform roll-up demo possible.
    fixtures = Rook::Demo::SyntheticPopulation::FIXTURES_DIR
    feeds = [
      [ File.join(fixtures, "primary_fhir"), Rook::Demo::SyntheticPopulation::PRIMARY_SOURCE ],
      [ File.join(fixtures, "supplemental"), Rook::Demo::SyntheticPopulation::SUPPLEMENTAL_SOURCE ],
      [ File.join(fixtures, "epic", "primary_fhir"), Rook::Demo::SyntheticPopulation::EPIC_PRIMARY_SOURCE ],
      [ File.join(fixtures, "epic", "supplemental"), Rook::Demo::SyntheticPopulation::EPIC_SUPPLEMENTAL_SOURCE ]
    ].map { |dir, source| Rook::Ingest::NdjsonFeed.directory(dir, source: source) }

    resources = Rook::Ingest.load(*feeds)
    assert_equal 35 + 18, resources.count { |r| r["resourceType"] == "Patient" }
  end
end
