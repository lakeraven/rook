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
        # @param id [String]
        # @param lot_number [String]
        # @param vaccine_code [String] CVX code
        # @param funding_source [String, nil] e.g. "VFC", "VFA", "private"
        def seed_lot(id:, lot_number:, vaccine_code:, funding_source: nil)
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
