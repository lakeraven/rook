# frozen_string_literal: true

require "rook/measure_definition"
require "rook/crs/terminology"

module Rook
  module Crs
    # CRS v25 GPRA measure implementations over Crs::PatientRecord objects.
    # Each class encodes its dossier (docs/measures/) — spec §-references and
    # M-verified rules — and is exercised by the parity features
    # (features/parity/) that the #99 harness also runs against real CRS.
    module Measures
      # Shared GPRA denominator: User Pop Diabetic (§2.1.2.3; dossier
      # diabetes-glycemic-control.md). NO age band.
      module UserPopDiabetic
        def in_denominator?(patient, period)
          first = patient.first_diabetes_evidence_date
          patient.user_population?(period) &&
            !first.nil? && first < period.start_date &&
            patient.visits_during(period) >= 2 &&
            (patient.diabetes_pov_visit_dates.size >= 2 || patient.diabetes_problem_list_entry?)
        end
      end

      # GPRA: Poor Glycemic Control — A1c > 9 (§2.1.2.4 numerator 2).
      # M-verified: a patient with NO resulted A1c is NOT in this numerator
      # (HGBA1C^BGPXD2 returns not-done; opposite of the UDS/eCQM
      # convention). CPT 3046F counts as > 9.
      class PoorGlycemicControl < MeasureDefinition
        include UserPopDiabetic

        def id = "crs-v25-diabetes-poor-glycemic-control"
        def title = "Diabetes: Glycemic Control — Poor Control (A1c > 9)"
        def interpretation = "Lower is better. Numerator = most recent resulted A1c greater than 9."
        def improvement_notation = :decrease

        def in_numerator?(patient, period)
          latest = patient.latest_a1c(period)
          return false if latest.nil?
          return true if Terminology::A1C_CPT_POOR.include?(latest.cpt)

          !latest.value.nil? && latest.value > 9
        end

        def care_gap?(patient, period)
          in_numerator?(patient, period)
        end

        def gap_reason(patient, period)
          latest = patient.latest_a1c(period)
          format("Most recent A1c evidence (%s) shows poor control (> 9)", latest.date)
        end
      end

      # Good control — A1c < 8 (§2.1.2.4 numerator 4; non-GPRA). CPT 3044F
      # and 3051F count in the < 8 numerator (§2.1.2.5).
      class GoodGlycemicControl < MeasureDefinition
        include UserPopDiabetic

        def id = "crs-v25-diabetes-good-glycemic-control"
        def title = "Diabetes: Glycemic Control — Good Control (A1c < 8)"
        def interpretation = "Higher is better. Numerator = most recent resulted A1c below 8."

        def in_numerator?(patient, period)
          latest = patient.latest_a1c(period)
          return false if latest.nil?
          return true if Terminology::A1C_CPT_GOOD.include?(latest.cpt)

          !latest.value.nil? && latest.value < 8
        end

        def care_gap?(patient, period)
          !in_numerator?(patient, period)
        end

        def gap_reason(_patient, _period)
          "No resulted A1c below 8 in the measurement period"
        end
      end

      # GPRA: Controlling High Blood Pressure — Million Hearts / NQF 0018
      # (§2.6.2; dossier controlling-high-blood-pressure.md). User Population
      # 18–85 with hypertension diagnosed during the period or the year
      # prior, excluding ESRD-ever and current pregnancy. Numerator: last BP
      # of the period < 140/90, same-day tie-break preferring the controlled
      # reading.
      class ControllingHighBloodPressure < MeasureDefinition
        def id = "crs-v25-controlling-high-blood-pressure"
        def title = "Controlling High Blood Pressure — Million Hearts"
        def interpretation = "Higher is better. Numerator = last BP of the period below 140/90."

        def in_denominator?(patient, period)
          age = patient.age_on(period.end)
          window = (period.start_date << 12)..period.end
          patient.user_population?(period) &&
            age >= 18 && age <= 85 &&
            patient.hypertension_dx_in?(window) &&
            !patient.esrd_ever? &&
            !patient.currently_pregnant_during?(period)
        end

        def in_numerator?(patient, period)
          patient.last_day_bps(period).any? do |bp|
            !bp[:systolic].nil? && !bp[:diastolic].nil? &&
              bp[:systolic] < 140 && bp[:diastolic] < 90
          end
        end

        def care_gap?(patient, period)
          !in_numerator?(patient, period)
        end

        def gap_reason(patient, period)
          patient.last_day_bps(period).empty? ? "No blood pressure recorded in the measurement period" : "Most recent blood pressure not controlled (below 140/90)"
        end
      end

      # GPRA: Depression Screening (§2.5.4; dossier depression-screening.md).
      # One numerator definition — screened for depression OR diagnosed with
      # a mood disorder (two visits) during the period, refusals excluded —
      # applied per User Population age stratum (12–17 and 18+).
      class DepressionScreening < MeasureDefinition
        def initialize(age_range:, stratum_label:, **options)
          super(**options)
          @age_range = age_range
          @stratum_label = stratum_label
        end

        attr_reader :stratum_label

        def id = "crs-v25-depression-screening-#{@stratum_label.downcase.tr(' +', '-')}"
        def title = "Depression Screening (#{@stratum_label})"
        def interpretation = "Higher is better. Numerator = screened for depression or diagnosed with a mood disorder."

        def in_denominator?(patient, period)
          patient.user_population?(period) && @age_range.cover?(patient.age_on(period.end))
        end

        def in_numerator?(patient, period)
          patient.depression_screened?(period) || patient.mood_disorder_visits(period) >= 2
        end

        def care_gap?(patient, period)
          !in_numerator?(patient, period)
        end

        def gap_reason(_patient, _period)
          "No depression screening or mood disorder diagnosis in the measurement period"
        end
      end
    end
  end
end
