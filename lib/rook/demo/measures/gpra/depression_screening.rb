# frozen_string_literal: true

require "rook/demo/measure"

module Rook
  module Demo
    module Measures
      module Gpra
        # DEMO / REFERENCE ONLY — see Rook::Demo.
        #
        # IHS GPRA / CRS national clinical measure: Depression Screening.
        #
        #   Denominator: active patients aged 12 and older.
        #   Numerator:   a depression screening (PHQ-9 total score,
        #                ValueSets::DEPRESSION_SCREENING_INSTRUMENT) was
        #                recorded during the measurement period.
        #
        # A HIGHER rate is better; the care-gap worklist is the denominator
        # patients with no screening on file for the period.
        #
        # Demo approximation: the full GPRA spec excludes patients with an
        # existing depression/bipolar diagnosis (presumed already monitored).
        # This demo omits that exclusion — the synthetic population carries no
        # such diagnoses — so the denominator is simply every patient aged 12+.
        class DepressionScreening < Measure
          MINIMUM_AGE = 12

          def id
            "gpra-depression-screening"
          end

          def title
            "Depression Screening (PHQ, age 12+)"
          end

          def interpretation
            "Higher is better. Numerator = patients screened for depression in the period."
          end

          def in_denominator?(patient, period)
            patient.age_on(period.end) >= MINIMUM_AGE
          end

          def in_numerator?(patient, period)
            !patient.latest_observation(codes_in(ValueSets::DEPRESSION_SCREENING_INSTRUMENT), period).nil?
          end

          def care_gap?(patient, period)
            !in_numerator?(patient, period)
          end

          def gap_reason(_patient, _period)
            "No depression screening recorded in measurement period"
          end
        end
      end
    end
  end
end
