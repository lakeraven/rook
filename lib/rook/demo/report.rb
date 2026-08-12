# frozen_string_literal: true

require "date"
require "rook/demo/synthetic_population"
require "rook/demo/measures/diabetes_hba1c_poor_control"
require "rook/demo/measures/controlling_high_blood_pressure"
require "rook/demo/measures/gpra/diabetes_poor_glycemic_control"
require "rook/demo/measures/gpra/controlling_high_blood_pressure"
require "rook/demo/measures/gpra/depression_screening"

module Rook
  module Demo
    # DEMO / REFERENCE ONLY — see Rook::Demo.
    #
    # Computes a demo-scoped quality report over a synthetic population: for each
    # hardcoded measure, the denominator / numerator / rate plus a care-gap
    # worklist (denominator patients needing outreach).
    #
    # One engine, two views over the SAME measure computations:
    #   .uds  -> HRSA UDS Table 6B packaging (urban Indian organization segment)
    #   .gpra -> IHS CRS / GPRA packaging (tribal 638 segment)
    class Report
      DEFAULT_PERIOD = (Date.new(2025, 1, 1)..Date.new(2025, 12, 31))

      # Generic, non-identifying label. NO real clinic/tribe/partner names.
      CLINIC_LABEL = "a tribal clinic (synthetic demo data)"

      Result = Struct.new(:measure, :denominator, :numerator, :rate, :care_gaps, keyword_init: true) do
        def rate_percent
          (rate * 100).round(1)
        end
      end

      GapEntry = Struct.new(:patient, :reason, keyword_init: true)

      def self.uds
        new(population: SyntheticPopulation.default,
          framework: "UDS Table 6B (HRSA)",
          measures: uds_measures)
      end

      # Kept for backward compatibility: the original UDS view.
      def self.default
        uds
      end

      def self.gpra
        new(population: SyntheticPopulation.default,
          framework: "IHS CRS / GPRA National Clinical Measures",
          measures: gpra_measures)
      end

      def initialize(population:, framework: "UDS Table 6B (HRSA)",
        period: DEFAULT_PERIOD, measures: self.class.uds_measures)
        @population = population
        @framework = framework
        @period = period
        @measures = measures
      end

      def self.uds_measures
        [
          Measures::DiabetesHbA1cPoorControl.new,
          Measures::ControllingHighBloodPressure.new
        ]
      end

      def self.gpra_measures
        [
          Measures::Gpra::DiabetesPoorGlycemicControl.new,
          Measures::Gpra::ControllingHighBloodPressure.new,
          Measures::Gpra::DepressionScreening.new
        ]
      end

      attr_reader :period, :framework

      def clinic_label
        CLINIC_LABEL
      end

      def patient_count
        @population.patients.size
      end

      def results
        @results ||= @measures.map do |measure|
          patients = @population.patients
          Result.new(
            measure: measure,
            denominator: measure.denominator(patients, @period).size,
            numerator: measure.numerator(patients, @period).size,
            rate: measure.rate(patients, @period),
            care_gaps: measure.care_gaps(patients, @period).map do |patient|
              GapEntry.new(patient: patient, reason: measure.gap_reason(patient, @period))
            end
          )
        end
      end
    end
  end
end
