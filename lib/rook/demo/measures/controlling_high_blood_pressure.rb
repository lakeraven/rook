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
      #                diagnosis (ValueSets::HYPERTENSION).
      #   Numerator:   most recent blood pressure in the period is adequately
      #                controlled (systolic <140 AND diastolic <90).
      #
      # BP is stored as an Observation coded from ValueSets::BLOOD_PRESSURE_PANEL
      # (LOINC 85354-9); systolic and diastolic live in its components
      # (ValueSets::SYSTOLIC_BLOOD_PRESSURE / DIASTOLIC_BLOOD_PRESSURE).
      #
      # This is a standard measure: a HIGHER rate is better, and the care-gap
      # worklist is the denominator patients NOT in the numerator (uncontrolled
      # or no BP recorded in the period).
      class ControllingHighBloodPressure < Measure
        SYSTOLIC_GOAL = 140
        DIASTOLIC_GOAL = 90

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
          age >= 18 && age <= 85 && patient.condition?(codes_in(ValueSets::HYPERTENSION))
        end

        def in_numerator?(patient, period)
          bp = latest_bp(patient, period)
          return false if bp.nil?

          systolic = systolic_of(bp)
          diastolic = diastolic_of(bp)
          return false if systolic.nil? || diastolic.nil?

          systolic < SYSTOLIC_GOAL && diastolic < DIASTOLIC_GOAL
        end

        def care_gap?(patient, period)
          !in_numerator?(patient, period)
        end

        def gap_reason(patient, period)
          bp = latest_bp(patient, period)
          return "No blood pressure recorded in measurement period" if bp.nil?

          format("Most recent BP %d/%d mmHg (%s) not controlled",
            systolic_of(bp), diastolic_of(bp), bp.effective_date)
        end

        private

        def latest_bp(patient, period)
          patient.latest_observation(codes_in(ValueSets::BLOOD_PRESSURE_PANEL), period)
        end

        def systolic_of(bp)
          bp.component_value(codes_in(ValueSets::SYSTOLIC_BLOOD_PRESSURE))
        end

        def diastolic_of(bp)
          bp.component_value(codes_in(ValueSets::DIASTOLIC_BLOOD_PRESSURE))
        end
      end
    end
  end
end
