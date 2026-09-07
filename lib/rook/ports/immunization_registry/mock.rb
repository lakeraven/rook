# frozen_string_literal: true

require_relative "base"

module Rook
  module Ports
    module ImmunizationRegistry
      # In-memory mock for testing without a backend.
      #
      # Seed simple attributes; reads come back as fhir_models resources,
      # exactly as a concrete adapter would return them.
      class Mock < Base
        def initialize
          super
          @eligibility = {}
          @lots = {}
        end

        # Seed a patient's VFC eligibility.
        # @param patient_id [String]
        # @param eligibility_code [String] HL7 v2 Table 0064 code (e.g. "V02")
        def seed_eligibility(patient_id:, eligibility_code:)
          @eligibility[patient_id] = ImmunizationRegistry.build_vfc_coverage(
            patient_id: patient_id, eligibility_code: eligibility_code
          )
        end

        # Seed a vaccine lot.
        #
        # Enforces the port contract: every lot MUST carry a funding source
        # (see ImmunizationRegistry.funding_source), so a non-conformant
        # adapter shape is caught in integration, not at point of care.
        # @param id [String]
        # @param lot_number [String]
        # @param vaccine_code [String] CVX code
        # @param funding_source [String] e.g. "VFC", "VFA", "private"
        # @raise [ArgumentError] when funding_source is missing or blank
        def seed_lot(id:, lot_number:, vaccine_code:, funding_source:)
          if funding_source.to_s.strip.empty?
            raise ArgumentError,
              "funding_source is required: adapters must emit a funding source on every lot"
          end

          @lots[id] = ImmunizationRegistry.build_vaccine_lot(
            id: id, lot_number: lot_number,
            vaccine_code: vaccine_code, funding_source: funding_source
          )
        end

        def vfc_eligibility(patient_id)
          @eligibility[patient_id]
        end

        def vaccine_lot(lot_id)
          @lots[lot_id]
        end

        def vaccine_lots(vaccine_code:)
          @lots.values.select { |lot| ImmunizationRegistry.vaccine_code(lot) == vaccine_code }
        end
      end
    end
  end
end
