# frozen_string_literal: true

require "rook/demo/measure"

module Rook
  module Demo
    module Measures
      # DEMO / REFERENCE ONLY — see Rook::Demo.
      #
      # UDS Table 6B — Diabetes: Hemoglobin A1c (HbA1c) Poor Control (>9%).
      #
      #   Denominator: patients aged 18-75 (at period end) with a diabetes
      #                diagnosis (ValueSets::DIABETES).
      #   Numerator:   most recent HbA1c in the period is >9%, OR no HbA1c was
      #                recorded during the period.
      #
      # This is an inverse measure: the numerator is the *poor-control* group,
      # so a LOWER rate is better and the numerator IS the care-gap worklist.
      class DiabetesHbA1cPoorControl < Measure
        POOR_CONTROL_THRESHOLD = 9.0

        def id
          "uds-6b-diabetes-hba1c-poor-control"
        end

        def title
          "Diabetes: HbA1c Poor Control (>9%)"
        end

        def interpretation
          "Lower is better. Numerator = patients with poor control or no HbA1c in the period."
        end

        def in_denominator?(patient, period)
          age = patient.age_on(period.end)
          age >= 18 && age <= 75 && patient.condition?(codes_in(ValueSets::DIABETES))
        end

        def in_numerator?(patient, period)
          latest = latest_hba1c(patient, period)
          latest.nil? || latest.value > POOR_CONTROL_THRESHOLD
        end

        # For an inverse measure, being in the numerator is the gap.
        def care_gap?(patient, period)
          in_numerator?(patient, period)
        end

        # Short reason string for the worklist.
        def gap_reason(patient, period)
          latest = latest_hba1c(patient, period)
          return "No HbA1c recorded in measurement period" if latest.nil?

          format("Most recent HbA1c %.1f%% (%s) exceeds 9%%", latest.value, latest.effective_date)
        end

        private

        def latest_hba1c(patient, period)
          patient.latest_observation(codes_in(ValueSets::HBA1C_LABORATORY_TEST), period)
        end
      end
    end
  end
end
