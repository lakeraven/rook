# frozen_string_literal: true

require "rook/demo/measure"

module Rook
  module Demo
    module Measures
      # DEMO / REFERENCE ONLY — see Rook::Demo.
      #
      # UDS Table 6B — Controlling High Blood Pressure.
      #
      #   Denominator: patients aged 18-85 (at period end) with a hypertension
      #                diagnosis.
      #   Numerator:   most recent blood pressure in the period is adequately
      #                controlled (systolic <140 AND diastolic <90).
      #
      # This is a standard measure: a HIGHER rate is better, and the care-gap
      # worklist is the denominator patients NOT in the numerator (uncontrolled
      # or no BP recorded in the period).
      class ControllingHighBloodPressure < Measure
        SYSTOLIC_GOAL = 140
        DIASTOLIC_GOAL = 90
        # BP is stored as an Observation with LOINC 85354-9 (panel); systolic and
        # diastolic live in its components (8480-6 / 8462-4).
        BP_PANEL_LOINC = "85354-9"

        def id
          "uds-6b-controlling-high-blood-pressure"
        end

        def title
          "Controlling High Blood Pressure (<140/90)"
        end

        def interpretation
          "Higher is better. Numerator = patients with a controlled most-recent BP."
        end

        def in_denominator?(patient, period)
          age = patient.age_on(period.end)
          age >= 18 && age <= 85 && patient.condition?(HYPERTENSION_CODES)
        end

        def in_numerator?(patient, period)
          bp = patient.latest_observation(BP_PANEL_LOINC, period)
          return false if bp.nil?

          systolic = bp.components[SYSTOLIC_LOINC]
          diastolic = bp.components[DIASTOLIC_LOINC]
          return false if systolic.nil? || diastolic.nil?

          systolic < SYSTOLIC_GOAL && diastolic < DIASTOLIC_GOAL
        end

        def care_gap?(patient, period)
          !in_numerator?(patient, period)
        end

        def gap_reason(patient, period)
          bp = patient.latest_observation(BP_PANEL_LOINC, period)
          return "No blood pressure recorded in measurement period" if bp.nil?

          format("Most recent BP %d/%d mmHg (%s) not controlled",
            bp.components[SYSTOLIC_LOINC], bp.components[DIASTOLIC_LOINC], bp.effective_date)
        end
      end
    end
  end
end
