# frozen_string_literal: true

require "test_helper"

class Rook::VfcEligibilityEnforcementServiceTest < Minitest::Test
  # =============================================================================
  # VALIDATE — VFC ENFORCEMENT RULES
  # =============================================================================

  def test_vfc_lot_with_vfc_eligible_patient_v02_succeeds
    service = build_service(eligibility_code: "V02", lot_funding: "VFC")
    result = service.validate(patient_id: "1", lot_id: "10")

    assert result[:success]
  end

  def test_vfc_lot_with_vfc_eligible_patient_v05_succeeds
    service = build_service(eligibility_code: "V05", lot_funding: "VFC")
    result = service.validate(patient_id: "1", lot_id: "10")

    assert result[:success]
  end

  def test_vfc_lot_with_non_eligible_patient_v01_fails
    service = build_service(eligibility_code: "V01", lot_funding: "VFC")
    result = service.validate(patient_id: "1", lot_id: "10")

    refute result[:success]
    assert result[:reason].include?("not eligible")
  end

  def test_non_vfc_lot_succeeds_for_any_patient
    service = build_service(eligibility_code: "V01", lot_funding: "VFA")
    result = service.validate(patient_id: "1", lot_id: "10")

    assert result[:success]
  end

  def test_private_lot_succeeds_for_any_patient
    service = build_service(eligibility_code: "V01", lot_funding: "private")
    result = service.validate(patient_id: "1", lot_id: "10")

    assert result[:success]
  end

  def test_missing_eligibility_fails_closed
    service = build_service(eligibility_code: nil, lot_funding: "VFC")
    result = service.validate(patient_id: "1", lot_id: "10")

    refute result[:success]
    assert result[:reason].include?("eligibility")
  end

  def test_missing_lot_data_fails_closed
    service = build_service(eligibility_code: "V02", lot_funding: nil, lot_missing: true)
    result = service.validate(patient_id: "1", lot_id: "999")

    refute result[:success]
    assert result[:reason].include?("lot")
  end

  # =============================================================================
  # VALIDATE — ERROR HANDLING (fail-closed)
  # =============================================================================

  def test_lot_lookup_error_fails_closed
    service = build_service(eligibility_code: "V02", lot_error: true)
    result = service.validate(patient_id: "1", lot_id: "10")

    refute result[:success]
    assert result[:reason].include?("lot lookup failed")
  end

  def test_eligibility_lookup_error_fails_closed
    service = build_service(eligibility_error: true, lot_funding: "VFC")
    result = service.validate(patient_id: "1", lot_id: "10")

    refute result[:success]
    assert result[:reason].include?("eligibility lookup failed")
  end

  # =============================================================================
  # VALIDATE — RESULT SHAPE
  # =============================================================================

  def test_validate_returns_hash_with_success_and_reason
    service = build_service(eligibility_code: "V02", lot_funding: "VFC")
    result = service.validate(patient_id: "1", lot_id: "10")

    assert_kind_of Hash, result
    assert result.key?(:success)
    assert result.key?(:reason)
  end

  # =============================================================================
  # ELIGIBLE_LOTS_FOR_PATIENT
  # =============================================================================

  def test_eligible_lots_excludes_vfc_for_non_eligible_patient
    service = build_service(eligibility_code: "V01", lots: all_lots)
    lots = service.eligible_lots_for_patient(patient_id: "1", vaccine_code: "08")

    vfc_lots = lots.select { |l| l[:funding_source] == "VFC" }
    assert_empty vfc_lots
  end

  def test_eligible_lots_includes_vfc_for_eligible_patient
    service = build_service(eligibility_code: "V02", lots: all_lots)
    lots = service.eligible_lots_for_patient(patient_id: "1", vaccine_code: "08")

    vfc_lots = lots.select { |l| l[:funding_source] == "VFC" }
    refute_empty vfc_lots
  end

  def test_eligible_lots_filters_by_vaccine_code
    service = build_service(eligibility_code: "V02", lots: all_lots)
    lots = service.eligible_lots_for_patient(patient_id: "1", vaccine_code: "140")

    lots.each { |l| assert_equal "140", l[:vaccine_code] }
  end

  private

  def build_service(eligibility_code: "V02", lot_funding: "VFC", lot_missing: false, lot_error: false, eligibility_error: false, lots: nil)
    eligibility_adapter = if eligibility_error
      ->(_id) { raise StandardError, "Connection refused" }
    else
      ->(_id) { eligibility_code ? { code: eligibility_code } : nil }
    end

    lot_adapter = if lot_error
      ->(_id) { raise StandardError, "Connection refused" }
    elsif lot_missing
      ->(_id) { nil }
    else
      ->(_id) { { id: "10", lot_number: "LOT123", vaccine_code: "08", funding_source: lot_funding } }
    end

    lot_list_adapter = ->(**_args) { lots || [] }

    Rook::VfcEligibilityEnforcementService.new(
      eligibility_adapter: eligibility_adapter,
      lot_adapter: lot_adapter,
      lot_list_adapter: lot_list_adapter
    )
  end

  def all_lots
    [
      { id: "1", lot_number: "LOT-VFC", vaccine_code: "08", funding_source: "VFC" },
      { id: "2", lot_number: "LOT-VFA", vaccine_code: "08", funding_source: "VFA" },
      { id: "3", lot_number: "LOT-FLU", vaccine_code: "140", funding_source: "VFC" }
    ]
  end
end
