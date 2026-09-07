# frozen_string_literal: true

require "rook/result"
require "rook/ports"

module Rook
  # Vaccines for Children (VFC) eligibility enforcement.
  #
  # Validates that VFC-funded vaccine lots are only administered to
  # VFC-eligible patients. Fails closed on any error — patient safety
  # takes priority over availability.
  #
  # Consumes the FHIR-native ImmunizationRegistry port: patient eligibility
  # arrives as a FHIR::Coverage carrying the IIS eligibility code
  # (HL7 v2 Table 0064), vaccine lots as FHIR::Medication resources with
  # CVX code, batch lot number, and funding-source extension.
  #
  # VFC eligibility codes (IIS/HL7 Table 0064):
  #   V01 = Not VFC eligible
  #   V02 = VFC eligible (Medicaid)
  #   V03 = VFC eligible (Uninsured)
  #   V04 = VFC eligible (AI/AN)
  #   V05 = VFC eligible (Underinsured at FQHC/RHC)
  #   V07 = VFC eligible (state-specific)
  class VfcEligibilityEnforcementService
    VFC_ELIGIBLE_CODES = %w[V02 V03 V04 V05 V07].freeze
    VFC_FUNDING_SOURCES = %w[VFC].freeze

    # @param immunization_registry [Rook::Ports::ImmunizationRegistry::Base]
    def initialize(immunization_registry: Rook::Ports.immunization_registry)
      @immunization_registry = immunization_registry
    end

    # Validate whether a patient may receive a specific vaccine lot.
    # @return [Rook::Result]
    def validate(patient_id:, lot_id:)
      lot = fetch_lot(lot_id)
      return Result.failure("lot not found") unless lot

      # Non-VFC lots are always OK
      return Result.success unless vfc_lot?(lot)

      eligibility = fetch_eligibility(patient_id)
      return Result.failure("eligibility not available") unless eligibility

      if vfc_eligible?(eligibility)
        Result.success
      else
        Result.failure("Patient is not eligible for VFC-funded vaccine")
      end
    rescue => e
      Result.failure(e.message.include?("lot") ? "lot lookup failed" : "eligibility lookup failed")
    end

    # Returns lots available to a patient for a given vaccine code.
    # VFC-ineligible patients cannot see VFC lots.
    # @return [Array<FHIR::Medication>]
    def eligible_lots_for_patient(patient_id:, vaccine_code:)
      all_lots = @immunization_registry.vaccine_lots(vaccine_code: vaccine_code)
      eligibility = fetch_eligibility(patient_id)

      filtered = all_lots.select { |lot| registry.vaccine_code(lot) == vaccine_code }

      if vfc_eligible?(eligibility)
        filtered
      else
        filtered.reject { |lot| vfc_lot?(lot) }
      end
    end

    private

    def registry
      Rook::Ports::ImmunizationRegistry
    end

    def fetch_lot(lot_id)
      @immunization_registry.vaccine_lot(lot_id)
    rescue => e
      raise StandardError, "lot lookup failed: #{e.message}"
    end

    def fetch_eligibility(patient_id)
      @immunization_registry.vfc_eligibility(patient_id)
    rescue => e
      raise StandardError, "eligibility lookup failed: #{e.message}"
    end

    def vfc_lot?(lot)
      VFC_FUNDING_SOURCES.include?(registry.funding_source(lot))
    end

    def vfc_eligible?(coverage)
      VFC_ELIGIBLE_CODES.include?(registry.vfc_eligibility_code(coverage))
    end
  end
end
