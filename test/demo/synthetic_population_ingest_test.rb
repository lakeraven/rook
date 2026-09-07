# frozen_string_literal: true

require "test_helper"
require "rook/demo"

# DEMO / REFERENCE ONLY — asserts the demo population loads through the
# Rook::Ingest seam (Bulk-Data NDJSON feeds) with per-resource source
# provenance retained: the primary FHIR channel merged with the supplemental
# channel of extra-FHIR UDS attributes (sliding-fee class, housing status,
# MSAW/veteran status, payer category) normalized into FHIR shapes.
class Rook::Demo::SyntheticPopulationIngestTest < Minitest::Test
  ATTRIBUTE_CS = "https://terminology.lakeraven.com/CodeSystem/uds-supplemental-attribute"

  def setup
    @population = Rook::Demo::SyntheticPopulation.default
  end

  # ---------------------------------------------------------------------------
  # Loading through the ingest seam
  # ---------------------------------------------------------------------------

  def test_default_population_loads_from_ndjson_feeds
    assert_equal 35, @population.patients.size
  end

  def test_ndjson_fixtures_are_the_only_fixture_source
    fixtures = Rook::Demo::SyntheticPopulation::FIXTURES_DIR

    refute_path_exists File.join(fixtures, "synthetic_population.json")
    assert_path_exists File.join(fixtures, "primary_fhir", "Patient.ndjson")
    assert_path_exists File.join(fixtures, "supplemental", "Observation.ndjson")
    assert_path_exists File.join(fixtures, "supplemental", "Coverage.ndjson")
  end

  def test_the_two_feeds_are_the_two_adapter_channels
    primary = Rook::Demo::SyntheticPopulation::PRIMARY_SOURCE
    supplemental = Rook::Demo::SyntheticPopulation::SUPPLEMENTAL_SOURCE

    assert_predicate primary, :primary?
    assert_predicate supplemental, :supplemental?
    assert_equal :rpms, primary.platform
    assert_equal primary.platform, supplemental.platform, "both channels come from the same EHR"
  end

  # ---------------------------------------------------------------------------
  # Per-element provenance (supplemental-data audit substantiation)
  # ---------------------------------------------------------------------------

  def test_clinical_observations_carry_primary_channel_provenance
    hba1cs = @population.patients.flat_map(&:observations).select { |o| o.loinc == "4548-4" }

    refute_empty hba1cs
    assert(hba1cs.all? { |o| o.source_id == "demo-rpms-fhir" })
  end

  def test_supplemental_attributes_merge_in_with_supplemental_provenance
    sliding_fee = @population.patients.flat_map(&:observations)
      .select { |o| o.loinc == "sliding-fee-class" }

    assert_equal 5, sliding_fee.size
    assert(sliding_fee.all? { |o| o.source_id == "demo-rpms-supplemental" })
    assert(sliding_fee.all? { |o| o.value.start_with?("class-") })
  end

  def test_payer_category_arrives_as_supplemental_coverage
    coverages = @population.patients.flat_map(&:coverages)

    assert_equal 5, coverages.size
    assert(coverages.all? { |c| c.source_id == "demo-rpms-supplemental" })
    assert_includes coverages.map(&:payer_category), "medicaid"
    assert_includes coverages.map(&:payer_category), "uninsured"
  end

  def test_supplemental_feed_attaches_to_existing_patients_not_new_ones
    with_attributes = @population.patients.select { |p| p.coverages.any? }

    assert_equal 5, with_attributes.size
    assert_includes with_attributes.map(&:id), "demo-pt-001"
  end

  def test_supplemental_attributes_do_not_disturb_clinical_measure_lookup
    patient = @population.patients.find { |p| p.id == "demo-pt-001" }
    period = Date.new(2025, 1, 1)..Date.new(2025, 12, 31)

    latest = patient.latest_observation("4548-4", period)
    assert latest, "clinical HbA1c lookup still works alongside supplemental observations"
    assert_kind_of Numeric, latest.value
  end

  # ---------------------------------------------------------------------------
  # Bundle-based construction stays supported (no ingest, no provenance)
  # ---------------------------------------------------------------------------

  def test_bundle_constructor_still_works_without_provenance
    bundle = { "entry" => [
      { "resource" => { "resourceType" => "Patient", "id" => "b1", "birthDate" => "1980-01-01" } },
      { "resource" => { "resourceType" => "Observation", "code" => { "coding" => [ { "code" => "4548-4" } ] },
                       "subject" => { "reference" => "Patient/b1" }, "effectiveDateTime" => "2025-01-01",
                       "valueQuantity" => { "value" => 7.0 } } }
    ] }
    population = Rook::Demo::SyntheticPopulation.new(bundle)

    assert_equal 1, population.patients.size
    assert_nil population.patients.first.observations.first.source_id
  end
end
