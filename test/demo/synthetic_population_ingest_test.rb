# frozen_string_literal: true

require "test_helper"
require "rook/demo"

# DEMO / REFERENCE ONLY — asserts the demo population loads through the
# Rook::Ingest seam (Bulk-Data NDJSON feeds) with per-resource source
# provenance retained: the primary FHIR channel merged with the supplemental
# channel of extra-FHIR UDS attributes (sliding-fee class, housing status,
# agricultural-worker/veteran status, payer category) normalized into FHIR
# shapes.
class Rook::Demo::SyntheticPopulationIngestTest < Minitest::Test
  ATTRIBUTE_CS = "https://terminology.lakeraven.com/CodeSystem/uds-supplemental-attribute"
  VALUE_CS = "https://terminology.lakeraven.com/CodeSystem/uds-supplemental-value"

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

  # NOTE: the demo reader matches bare code strings (no coding-system check);
  # this holds because LOINC codes and supplemental attribute codes are
  # disjoint sets by naming convention. System-aware matching arrives with the
  # production reader.
  def test_supplemental_attributes_do_not_disturb_clinical_measure_lookup
    patient = @population.patients.find { |p| p.id == "demo-pt-001" }
    period = Date.new(2025, 1, 1)..Date.new(2025, 12, 31)

    latest = patient.latest_observation("4548-4", period)
    assert latest, "clinical HbA1c lookup still works alongside supplemental observations"
    assert_kind_of Numeric, latest.value
  end

  HOUSING_STATUS_VALUES =
    %w[housed homeless-shelter doubling-up unsheltered transitional
       permanent-supportive other unknown].freeze

  def test_supplemental_values_ride_under_the_shared_value_code_system
    housing = @population.patients.flat_map(&:observations).select { |o| o.loinc == "housing-status" }

    refute_empty housing
    assert_includes HOUSING_STATUS_VALUES, housing.first.value

    # The flattened struct strips the value's coding system, so assert it on
    # the raw supplemental-feed resources: attribute codes ride under the
    # attribute code system and coded values under the value code system.
    raw = Rook::Ingest::NdjsonFeed.directory(
      File.join(Rook::Demo::SyntheticPopulation::FIXTURES_DIR, "supplemental"),
      source: Rook::Demo::SyntheticPopulation::SUPPLEMENTAL_SOURCE)
      .each_resource.select { |r| r["resourceType"] == "Observation" }

    refute_empty raw
    assert(raw.all? { |r| r.dig("code", "coding", 0, "system") == ATTRIBUTE_CS })
    assert(raw.all? { |r| r.dig("valueCodeableConcept", "coding", 0, "system") == VALUE_CS })
  end

  def test_agricultural_worker_status_uses_the_shared_attribute_vocabulary
    statuses = @population.patients.flat_map(&:observations)
      .select { |o| o.loinc == "agricultural-worker-status" }.map(&:value)

    assert_equal 5, statuses.size
    assert_empty statuses - %w[migratory seasonal none]
  end

  # ---------------------------------------------------------------------------
  # Undated-wins is scoped to supplemental registration attributes; clinical
  # observations require a date (the shared cross-repo UDS read rule).
  # ---------------------------------------------------------------------------

  PERIOD = (Date.new(2025, 1, 1)..Date.new(2025, 12, 31))

  # An undated supplemental observation means "registration-current": always
  # in-period, and it wins over any dated reading.
  def test_undated_supplemental_observation_is_current_and_wins_over_dated
    patient = patient_with_observations(
      supplemental_obs("housing-status", "unsheltered", effective: "2025-06-01"),
      supplemental_obs("housing-status", "housed")
    )

    undated = patient.observations.find { |o| o.effective_date.nil? }
    assert undated, "missing effective[x] loads as an undated observation"
    assert_equal "housed", patient.latest_observation("housing-status", PERIOD).value
  end

  # Supplemental reads are "current as of period end": a value dated before
  # the period start is still the current registration value.
  def test_supplemental_read_is_current_as_of_period_end
    patient = patient_with_observations(
      supplemental_obs("housing-status", "doubling-up", effective: "2024-03-01")
    )

    assert_equal "doubling-up", patient.latest_observation("housing-status", PERIOD).value
  end

  def test_undated_clinical_observation_does_not_beat_a_dated_in_period_one
    patient = patient_with_observations(
      clinical_obs("4548-4", 7.2, effective: "2025-06-01"),
      clinical_obs("4548-4", 11.0)
    )

    assert_equal 7.2, patient.latest_observation("4548-4", PERIOD).value
  end

  def test_undated_clinical_observation_never_matches_a_period_lookup
    patient = patient_with_observations(clinical_obs("4548-4", 11.0))

    assert_nil patient.latest_observation("4548-4", PERIOD)
  end

  def test_effective_period_only_observation_resolves_to_its_end
    patient = patient_with_observations(
      clinical_obs("4548-4", 8.4).tap do |o|
        o["effectivePeriod"] = { "start" => "2025-04-01", "end" => "2025-04-03" }
      end
    )

    latest = patient.latest_observation("4548-4", PERIOD)
    assert latest, "effectivePeriod-only observation matches the period lookup"
    assert_equal Date.new(2025, 4, 3), latest.effective_date
  end

  def test_effective_period_falls_back_to_start_and_instant_parses
    patient = patient_with_observations(
      clinical_obs("4548-4", 8.4).tap { |o| o["effectivePeriod"] = { "start" => "2025-04-01" } },
      clinical_obs("8302-2", 170).tap { |o| o["effectiveInstant"] = "2025-05-01T12:00:00Z" }
    )

    assert_equal Date.new(2025, 4, 1), patient.latest_observation("4548-4", PERIOD).effective_date
    assert_equal Date.new(2025, 5, 1), patient.latest_observation("8302-2", PERIOD).effective_date
  end

  # ---------------------------------------------------------------------------
  # Coverage keeps status + period; payer reads honor only current coverage
  # ---------------------------------------------------------------------------

  def test_current_coverages_excludes_non_active_and_expired_but_keeps_duals
    patient = patient_with_resources(
      coverage("medicaid", status: "entered-in-error"),
      coverage("private", status: "active", start: "2024-01-01", end_date: "2024-12-31"),
      coverage("medicare", status: "active", start: "2025-01-01", end_date: nil),
      coverage("medicaid", status: "active", start: "2025-01-01", end_date: "2025-12-31")
    )
    current = patient.current_coverages(Date.new(2025, 6, 30))

    assert_equal 4, patient.coverages.size, "coverages stays the full uncollapsed list"
    assert_equal %w[medicare medicaid], current.map(&:payer_category),
      "dual-eligible: both current coverages present; entered-in-error and expired excluded"
  end

  # ---------------------------------------------------------------------------
  # Missing/malformed subject or beneficiary references fail closed
  # ---------------------------------------------------------------------------

  def test_missing_subject_reference_raises_instead_of_vanishing
    error = assert_raises(Rook::Ingest::MalformedResourceError) do
      patient_with_observations(
        clinical_obs("4548-4", 7.0, effective: "2025-06-01").tap { |o| o.delete("subject") }
          .merge("id" => "obs-no-subject")
      )
    end

    assert_includes error.message, "Observation/obs-no-subject"
  end

  def test_malformed_beneficiary_reference_raises
    error = assert_raises(Rook::Ingest::MalformedResourceError) do
      patient_with_resources(
        coverage("medicaid", status: "active").merge(
          "id" => "cov-bad-ref", "beneficiary" => { "reference" => "Patient/" })
      )
    end

    assert_includes error.message, "Coverage/cov-bad-ref"
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

  private

  def patient_with_resources(*resources)
    all = [ { "resourceType" => "Patient", "id" => "u1", "birthDate" => "1980-01-01" }, *resources ]
    Rook::Demo::SyntheticPopulation.new(resources: all).patients.first
  end
  alias patient_with_observations patient_with_resources

  def supplemental_obs(attribute, value, effective: nil)
    obs = {
      "resourceType" => "Observation",
      "code" => { "coding" => [ { "system" => ATTRIBUTE_CS, "code" => attribute } ] },
      "subject" => { "reference" => "Patient/u1" },
      "valueCodeableConcept" => { "coding" => [ { "system" => VALUE_CS, "code" => value } ] }
    }
    obs["effectiveDateTime"] = effective if effective
    obs
  end

  def clinical_obs(loinc, value, effective: nil)
    obs = {
      "resourceType" => "Observation",
      "code" => { "coding" => [ { "system" => "http://loinc.org", "code" => loinc } ] },
      "subject" => { "reference" => "Patient/u1" },
      "valueQuantity" => { "value" => value }
    }
    obs["effectiveDateTime"] = effective if effective
    obs
  end

  def coverage(payer, status:, start: nil, end_date: nil)
    cov = {
      "resourceType" => "Coverage",
      "status" => status,
      "type" => { "coding" => [ { "code" => payer } ] },
      "beneficiary" => { "reference" => "Patient/u1" }
    }
    period = { "start" => start, "end" => end_date }.compact
    cov["period"] = period unless period.empty?
    cov
  end
end
