# frozen_string_literal: true

require "date"
require "rook/reporting_period"
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
    # Computes a demo-scoped quality report over a synthetic population: a thin
    # consumer of the engine-neutral measure interfaces — each measure's
    # #evaluate returns a Rook::MeasureResult (MeasureReport-backed, with the
    # care-gap worklist alongside); this class only picks the population, the
    # Rook::ReportingPeriod, and the measure list.
    #
    # One engine, two views over the SAME measure computations:
    #   .uds  -> HRSA UDS Table 6B packaging (urban Indian organization segment)
    #   .gpra -> IHS CRS / GPRA packaging (tribal 638 segment)
    class Report
      DEFAULT_PERIOD = ReportingPeriod.new(Date.new(2025, 1, 1), Date.new(2025, 12, 31))

      # Generic, non-identifying label. NO real clinic/tribe/partner names.
      CLINIC_LABEL = "a tribal clinic (synthetic demo data)"

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
        @period = ReportingPeriod.wrap(period)
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

      # One Rook::MeasureResult per measure (MeasureReport-backed).
      def results
        @results ||= @measures.map { |measure| measure.evaluate(@population.patients, @period) }
      end
    end
  end
end
