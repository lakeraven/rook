# frozen_string_literal: true

require "fhir_models"

module Rook
  module Ports
    # Immunization-registry (IIS) port.
    #
    # FHIR-native interface contract: implementations return fhir_models
    # FHIR R4 resources, never source-system shapes. Concrete adapters
    # (RPMS, state IIS, FHIR server, mock) translate internally; consumers
    # speak only FHIR.
    module ImmunizationRegistry
      # HL7 v2 Table 0064 — IIS financial-class / VFC eligibility codes
      # (V01 not eligible, V02 Medicaid, V03 uninsured, V04 AI/AN,
      # V05 underinsured at FQHC/RHC, V07 state-specific).
      VFC_ELIGIBILITY_SYSTEM = "http://terminology.hl7.org/CodeSystem/v2-0064"

      # CVX vaccine administered codes.
      CVX_SYSTEM = "http://hl7.org/fhir/sid/cvx"

      # Extension carrying a vaccine lot's funding source ("VFC", "VFA",
      # "private", ...) on a FHIR Medication.
      FUNDING_SOURCE_EXTENSION_URL =
        "https://github.com/lakeraven/rook/fhir/StructureDefinition/vaccine-funding-source"

      # Build a FHIR::Coverage carrying a patient's IIS VFC eligibility code.
      # @param patient_id [String]
      # @param eligibility_code [String] HL7 v2 Table 0064 code (e.g. "V02")
      # @return [FHIR::Coverage]
      def self.build_vfc_coverage(patient_id:, eligibility_code:)
        FHIR::Coverage.new(
          status: "active",
          beneficiary: { reference: "Patient/#{patient_id}" },
          type: {
            coding: [ { system: VFC_ELIGIBILITY_SYSTEM, code: eligibility_code } ]
          },
          payor: [ { display: "Vaccines for Children Program" } ]
        )
      end

      # Build a FHIR::Medication representing a vaccine lot.
      # @param id [String] lot record id
      # @param lot_number [String]
      # @param vaccine_code [String] CVX code
      # @param funding_source [String, nil] e.g. "VFC", "VFA", "private"
      # @return [FHIR::Medication]
      def self.build_vaccine_lot(id:, lot_number:, vaccine_code:, funding_source: nil)
        medication = FHIR::Medication.new(
          id: id,
          code: { coding: [ { system: CVX_SYSTEM, code: vaccine_code } ] },
          batch: { lotNumber: lot_number }
        )
        if funding_source
          medication.extension << FHIR::Extension.new(
            url: FUNDING_SOURCE_EXTENSION_URL,
            valueCode: funding_source
          )
        end
        medication
      end

      # Read the v2-0064 eligibility code off a FHIR::Coverage.
      #
      # System-strict: only a coding whose system is VFC_ELIGIBILITY_SYSTEM
      # counts. A Coverage without one yields nil (unknown eligibility),
      # which consumers treat as not VFC-eligible — never a code borrowed
      # from another code system.
      # @return [String, nil]
      def self.vfc_eligibility_code(coverage)
        return nil unless coverage

        codings = Array(coverage.type&.coding)
        codings.find { |c| c.system == VFC_ELIGIBILITY_SYSTEM }&.code
      end

      # Read the CVX code off a FHIR::Medication.
      #
      # System-strict: only a coding whose system is CVX_SYSTEM counts;
      # codes from other systems are ignored.
      # @return [String, nil]
      def self.vaccine_code(medication)
        return nil unless medication

        codings = Array(medication.code&.coding)
        codings.find { |c| c.system == CVX_SYSTEM }&.code
      end

      # Read the funding source off a FHIR::Medication.
      #
      # Contract: adapters MUST populate the funding-source extension with
      # valueCode or valueCoding — valueString is not read. A lot with no
      # funding-source extension yields nil and is treated as non-VFC
      # (administrable to any patient); this fail-open-for-unfunded-lots
      # behavior is an intentional parity decision with existing VFC
      # enforcement, so an adapter that omits the extension opts the lot
      # out of VFC restriction rather than into it.
      # @return [String, nil]
      def self.funding_source(medication)
        return nil unless medication

        extension = Array(medication.extension).find { |e| e.url == FUNDING_SOURCE_EXTENSION_URL }
        extension&.valueCode || extension&.valueCoding&.code
      end

      # Abstract immunization-registry interface.
      #
      # Concrete adapters implement these methods and return fhir_models
      # resources. Rook services call through this interface; they never
      # know the backend.
      class Base
        # @param patient_id [String]
        # @return [FHIR::Coverage, nil] Coverage whose type coding carries the
        #   patient's IIS VFC eligibility code (v2 Table 0064), or nil when
        #   eligibility is unknown
        def vfc_eligibility(patient_id)
          raise NotImplementedError, "#{self.class}#vfc_eligibility not implemented"
        end

        # @param lot_id [String]
        # @return [FHIR::Medication, nil] the vaccine lot (CVX code, batch lot
        #   number, funding-source extension), or nil if not found
        def vaccine_lot(lot_id)
          raise NotImplementedError, "#{self.class}#vaccine_lot not implemented"
        end

        # @param vaccine_code [String] CVX code
        # @return [Array<FHIR::Medication>] lots on hand for the vaccine
        def vaccine_lots(vaccine_code:)
          raise NotImplementedError, "#{self.class}#vaccine_lots not implemented"
        end
      end
    end
  end
end
