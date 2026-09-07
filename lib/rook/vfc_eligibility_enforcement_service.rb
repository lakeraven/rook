# frozen_string_literal: true

require "date"
require "rook/result"
require "rook/ports"

module Rook
  # Vaccines for Children (VFC) eligibility enforcement.
  #
  # Validates that VFC-funded vaccine lots are only administered to
  # VFC-eligible patients. Fails closed on any error or indeterminate
  # data — patient safety takes priority over availability.
  #
  # Consumes the FHIR-native ImmunizationRegistry port: patient eligibility
  # arrives as a FHIR::Coverage carrying the IIS eligibility code
  # (HL7 v2 Table 0064), vaccine lots as FHIR::Medication resources with
  # CVX code, batch lot number, and funding-source extension.
  #
  # Eligibility is honored only from a determinate Coverage: it must be
  # status "active", currently within its period (when one is present), its
  # beneficiary must be present and match the requested patient, and it must
  # carry a v2 Table 0064 coding. Anything else reads as
  # eligibility-not-available, never as an affirmative determination.
  #
  # A lot's funding source releases it from VFC restriction only when it is
  # a recognized non-VFC value (see KNOWN_NON_VFC_FUNDING_SOURCES). Missing,
  # blank, or unrecognized funding is treated as VFC-restricted: only a
  # determinately VFC-eligible patient may receive it, and denial carries a
  # distinct "lot funding source unverified" reason so staff see a lot-data
  # problem rather than a patient determination.
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
    # The only funding sources that release a lot from VFC restriction
    # (compared case-insensitively after trimming). Anything else —
    # blank, unrecognized ("public", "state"), or any casing of "vfc" —
    # keeps the lot VFC-restricted (fail closed).
    KNOWN_NON_VFC_FUNDING_SOURCES = %w[vfa private].freeze

    # @param immunization_registry [Rook::Ports::ImmunizationRegistry::Base]
    # @raise [ArgumentError] when no port is supplied and none is configured
    def initialize(immunization_registry: Rook::Ports.immunization_registry)
      if immunization_registry.nil?
        raise ArgumentError, "no immunization registry port configured"
      end

      @immunization_registry = immunization_registry
    end

    # Validate whether a patient may receive a specific vaccine lot.
    # @return [Rook::Result]
    def validate(patient_id:, lot_id:)
      lot = fetch_lot(lot_id)
      return Result.failure("lot not found") unless lot

      funding = funding_class(registry.funding_source(lot))
      # Lots with a recognized non-VFC funding source are always OK; VFC and
      # unverified-funding lots require a determinate VFC-eligible patient.
      return Result.success if funding == :non_vfc

      determination = eligibility_determination(fetch_eligibility(patient_id), patient_id)
      return Result.success if determination == :eligible

      if funding == :unverified
        Result.failure("lot funding source unverified")
      elsif determination == :unknown
        Result.failure("eligibility not available")
      else
        Result.failure("Patient is not eligible for VFC-funded vaccine")
      end
    rescue => e
      Result.failure(e.message.include?("lot") ? "lot lookup failed" : "eligibility lookup failed")
    end

    # Returns lots available to a patient for a given vaccine code.
    # Patients without a determinate VFC-eligible status cannot see VFC lots
    # or lots with an unknown funding source.
    #
    # Unlike #validate, port errors propagate to the caller — intentional:
    # a loud failure beats silently presenting an empty (or partial)
    # inventory as if it were the truth.
    # @return [Array<FHIR::Medication>]
    def eligible_lots_for_patient(patient_id:, vaccine_code:)
      all_lots = @immunization_registry.vaccine_lots(vaccine_code: vaccine_code)
      determination = eligibility_determination(fetch_eligibility(patient_id), patient_id)

      filtered = all_lots.select { |lot| registry.vaccine_code(lot) == vaccine_code }
      return filtered if determination == :eligible

      filtered.select { |lot| funding_class(registry.funding_source(lot)) == :non_vfc }
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

    # Classify a lot's funding source as :vfc, :non_vfc, or :unverified.
    # Only a recognized non-VFC value releases the lot; blank, unrecognized,
    # or missing funding fails closed as :unverified (VFC-restricted).
    def funding_class(funding)
      normalized = funding.to_s.strip.downcase
      return :unverified if normalized.empty?
      return :vfc if normalized == "vfc"

      KNOWN_NON_VFC_FUNDING_SOURCES.include?(normalized) ? :non_vfc : :unverified
    end

    # Classify a Coverage as :eligible, :not_eligible, or :unknown.
    #
    # Only an active, currently-in-period Coverage whose beneficiary matches
    # the requested patient and which carries a v2 Table 0064 coding yields
    # a determination; everything else is :unknown (eligibility not
    # available), never a false affirmative. A Coverage without a
    # beneficiary is indeterminate — it cannot be tied to this patient.
    def eligibility_determination(coverage, patient_id)
      return :unknown unless coverage
      return :unknown unless coverage.status == "active"
      return :unknown unless coverage_current?(coverage)
      return :unknown unless beneficiary_matches?(coverage, patient_id)

      code = registry.vfc_eligibility_code(coverage)
      return :unknown if code.nil?

      VFC_ELIGIBLE_CODES.include?(code) ? :eligible : :not_eligible
    end

    # Coverage.period, when present, must cover today. Unparseable dates
    # fail closed (indeterminate).
    def coverage_current?(coverage)
      period = coverage.period
      return true if period.nil?

      today = Date.today
      start_ok = period.start.nil? || Date.parse(period.start.to_s) <= today
      end_ok = period.end.nil? || today <= Date.parse(period.end.to_s)
      start_ok && end_ok
    rescue ArgumentError, TypeError
      false
    end

    def beneficiary_matches?(coverage, patient_id)
      reference = coverage.beneficiary&.reference
      return false if reference.nil?

      reference == "Patient/#{patient_id}" || reference == patient_id.to_s
    end
  end
end
