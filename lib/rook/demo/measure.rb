# frozen_string_literal: true

module Rook
  module Demo
    # DEMO / REFERENCE ONLY — see Rook::Demo.
    #
    # Base class for the two hardcoded UDS demo measures. This is a deliberately
    # tiny, single-measure-shaped abstraction for the sales demo — it is NOT a
    # general measure engine. The production engine is the Pathling-based work
    # tracked in rook#60 / rook#65; do not grow this into a substitute for it.
    #
    # Subclasses implement:
    #   #in_denominator?(patient, period) -> Boolean
    #   #in_numerator?(patient, period)   -> Boolean  (patient already in denom)
    #   #care_gap?(patient, period)       -> Boolean  (denom patient needing outreach)
    class Measure
      # LOINC / code sets shared by the demo measures.
      HBA1C_LOINC = "4548-4"
      SYSTOLIC_LOINC = "8480-6"
      DIASTOLIC_LOINC = "8462-4"

      # Diabetes: ICD-10 E11.9 + SNOMED 44054006 (as authored in the fixture).
      DIABETES_CODES = %w[E11.9 44054006].freeze
      # Hypertension: ICD-10 I10 + SNOMED 38341003.
      HYPERTENSION_CODES = %w[I10 38341003].freeze

      def id
        raise NotImplementedError
      end

      def title
        raise NotImplementedError
      end

      # Human-readable note on how to read the rate (higher vs lower is better).
      def interpretation
        raise NotImplementedError
      end

      def denominator(patients, period)
        patients.select { |p| in_denominator?(p, period) }
      end

      def numerator(patients, period)
        denominator(patients, period).select { |p| in_numerator?(p, period) }
      end

      # Denominator patients who need outreach (the care-gap worklist).
      def care_gaps(patients, period)
        denominator(patients, period).select { |p| care_gap?(p, period) }
      end

      def rate(patients, period)
        denom = denominator(patients, period).size
        return 0.0 if denom.zero?

        (numerator(patients, period).size.to_f / denom).round(4)
      end
    end
  end
end
