# frozen_string_literal: true

require "test_helper"

class Rook::VfcEligibilityEnforcementServiceTest < Minitest::Test
  Registry = Rook::Ports::ImmunizationRegistry

  # Port implementation whose lookups raise, for fail-closed tests.
  class ErrorRegistry < Registry::Base
    def initialize(lot_error: false, eligibility_error: false, delegate: Registry::Mock.new)
      super()
      @lot_error = lot_error
      @eligibility_error = eligibility_error
      @delegate = delegate
    end

    def vfc_eligibility(patient_id)
      raise StandardError, "Connection refused" if @eligibility_error
      @delegate.vfc_eligibility(patient_id)
    end

    def vaccine_lot(lot_id)
      raise StandardError, "Connection refused" if @lot_error
      @delegate.vaccine_lot(lot_id)
    end

    def vaccine_lots(vaccine_code:)
      @delegate.vaccine_lots(vaccine_code: vaccine_code)
    end
  end

  # =============================================================================
  # VALIDATE — VFC ENFORCEMENT RULES
  # =============================================================================

  def test_vfc_lot_with_vfc_eligible_patient_v02_succeeds
    service = build_service(eligibility_code: "V02", lot_funding: "VFC")
    result = service.validate(patient_id: "1", lot_id: "10")

    assert result.success?
  end

  def test_vfc_lot_with_vfc_eligible_patient_v05_succeeds
    service = build_service(eligibility_code: "V05", lot_funding: "VFC")
    result = service.validate(patient_id: "1", lot_id: "10")

    assert result.success?
  end

  def test_vfc_lot_with_non_eligible_patient_v01_fails
    service = build_service(eligibility_code: "V01", lot_funding: "VFC")
    result = service.validate(patient_id: "1", lot_id: "10")

    refute result.success?
    assert result.reason.include?("not eligible")
  end

  def test_non_vfc_lot_succeeds_for_any_patient
    service = build_service(eligibility_code: "V01", lot_funding: "VFA")
    result = service.validate(patient_id: "1", lot_id: "10")

    assert result.success?
  end

  def test_private_lot_succeeds_for_any_patient
    service = build_service(eligibility_code: "V01", lot_funding: "private")
    result = service.validate(patient_id: "1", lot_id: "10")

    assert result.success?
  end

  def test_missing_eligibility_fails_closed
    service = build_service(eligibility_code: nil, lot_funding: "VFC")
    result = service.validate(patient_id: "1", lot_id: "10")

    refute result.success?
    assert result.reason.include?("eligibility")
  end

  def test_missing_lot_data_fails_closed
    service = build_service(eligibility_code: "V02", lot_funding: nil, lot_missing: true)
    result = service.validate(patient_id: "1", lot_id: "999")

    refute result.success?
    assert result.reason.include?("lot")
  end

  # =============================================================================
  # VALIDATE — ERROR HANDLING (fail-closed)
  # =============================================================================

  def test_lot_lookup_error_fails_closed
    service = build_service(eligibility_code: "V02", lot_error: true)
    result = service.validate(patient_id: "1", lot_id: "10")

    refute result.success?
    assert result.reason.include?("lot lookup failed")
  end

  def test_eligibility_lookup_error_fails_closed
    service = build_service(eligibility_error: true, lot_funding: "VFC")
    result = service.validate(patient_id: "1", lot_id: "10")

    refute result.success?
    assert result.reason.include?("eligibility lookup failed")
  end

  # =============================================================================
  # VALIDATE — RESULT SHAPE
  # =============================================================================

  def test_validate_returns_result_value_object
    service = build_service(eligibility_code: "V02", lot_funding: "VFC")
    result = service.validate(patient_id: "1", lot_id: "10")

    assert_kind_of Rook::Result, result
    assert result.success?
    refute result.failure?
    assert_nil result.reason
  end

  # =============================================================================
  # VALIDATE — FHIR-NATIVE INPUTS
  # =============================================================================

  def test_reads_eligibility_from_fhir_coverage_type_coding
    registry = Registry::Mock.new
    registry.seed_lot(id: "10", lot_number: "LOT123", vaccine_code: "08", funding_source: "VFC")
    registry.seed_eligibility(patient_id: "1", eligibility_code: "V04")

    coverage = registry.vfc_eligibility("1")
    assert_kind_of FHIR::Coverage, coverage
    assert_equal Registry::VFC_ELIGIBILITY_SYSTEM, coverage.type.coding.first.system

    result = Rook::VfcEligibilityEnforcementService.new(immunization_registry: registry)
      .validate(patient_id: "1", lot_id: "10")
    assert result.success?
  end

  def test_reads_funding_source_from_fhir_medication_extension
    registry = Registry::Mock.new
    registry.seed_lot(id: "10", lot_number: "LOT123", vaccine_code: "08", funding_source: "VFC")
    registry.seed_eligibility(patient_id: "1", eligibility_code: "V01")

    lot = registry.vaccine_lot("10")
    assert_kind_of FHIR::Medication, lot
    assert_equal "LOT123", lot.batch.lotNumber
    assert_equal "VFC", Registry.funding_source(lot)

    result = Rook::VfcEligibilityEnforcementService.new(immunization_registry: registry)
      .validate(patient_id: "1", lot_id: "10")
    refute result.success?
  end

  def test_medication_without_funding_extension_is_not_vfc
    registry = Registry::Mock.new
    registry.seed_lot(id: "10", lot_number: "LOT123", vaccine_code: "08")
    registry.seed_eligibility(patient_id: "1", eligibility_code: "V01")

    result = Rook::VfcEligibilityEnforcementService.new(immunization_registry: registry)
      .validate(patient_id: "1", lot_id: "10")
    assert result.success?
  end

  # =============================================================================
  # ELIGIBLE_LOTS_FOR_PATIENT
  # =============================================================================

  def test_eligible_lots_excludes_vfc_for_non_eligible_patient
    service = build_service(eligibility_code: "V01", seed_all_lots: true)
    lots = service.eligible_lots_for_patient(patient_id: "1", vaccine_code: "08")

    vfc_lots = lots.select { |l| Registry.funding_source(l) == "VFC" }
    assert_empty vfc_lots
    refute_empty lots
  end

  def test_eligible_lots_includes_vfc_for_eligible_patient
    service = build_service(eligibility_code: "V02", seed_all_lots: true)
    lots = service.eligible_lots_for_patient(patient_id: "1", vaccine_code: "08")

    vfc_lots = lots.select { |l| Registry.funding_source(l) == "VFC" }
    refute_empty vfc_lots
  end

  def test_eligible_lots_filters_by_vaccine_code
    service = build_service(eligibility_code: "V02", seed_all_lots: true)
    lots = service.eligible_lots_for_patient(patient_id: "1", vaccine_code: "140")

    refute_empty lots
    lots.each { |l| assert_equal "140", Registry.vaccine_code(l) }
  end

  def test_eligible_lots_returns_fhir_medications
    service = build_service(eligibility_code: "V02", seed_all_lots: true)
    lots = service.eligible_lots_for_patient(patient_id: "1", vaccine_code: "08")

    lots.each { |l| assert_kind_of FHIR::Medication, l }
  end

  # =============================================================================
  # PORT REGISTRY (configure idiom)
  # =============================================================================

  def test_service_defaults_to_configured_port
    registry = Registry::Mock.new
    registry.seed_lot(id: "10", lot_number: "LOT123", vaccine_code: "08", funding_source: "VFC")
    registry.seed_eligibility(patient_id: "1", eligibility_code: "V02")

    Rook::Ports.configure { |c| c.immunization_registry = registry }
    result = Rook::VfcEligibilityEnforcementService.new.validate(patient_id: "1", lot_id: "10")

    assert result.success?
  ensure
    Rook::Ports.reset_configuration!
  end

  private

  def build_service(eligibility_code: "V02", lot_funding: "VFC", lot_missing: false,
                    lot_error: false, eligibility_error: false, seed_all_lots: false)
    mock = Rook::Ports::ImmunizationRegistry::Mock.new
    mock.seed_eligibility(patient_id: "1", eligibility_code: eligibility_code) if eligibility_code
    unless lot_missing || seed_all_lots
      mock.seed_lot(id: "10", lot_number: "LOT123", vaccine_code: "08", funding_source: lot_funding)
    end
    seed_lots(mock) if seed_all_lots

    registry = if lot_error || eligibility_error
      ErrorRegistry.new(lot_error: lot_error, eligibility_error: eligibility_error, delegate: mock)
    else
      mock
    end

    Rook::VfcEligibilityEnforcementService.new(immunization_registry: registry)
  end

  def seed_lots(mock)
    mock.seed_lot(id: "1", lot_number: "LOT-VFC", vaccine_code: "08", funding_source: "VFC")
    mock.seed_lot(id: "2", lot_number: "LOT-VFA", vaccine_code: "08", funding_source: "VFA")
    mock.seed_lot(id: "3", lot_number: "LOT-FLU", vaccine_code: "140", funding_source: "VFC")
  end
end
