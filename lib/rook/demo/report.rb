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

      # Generic, non-identifying labels. NO real clinic/tribe/partner names —
      # "Epic" names the EHR platform flavor of the synthetic export only.
      CLINIC_LABEL = "a tribal clinic (synthetic demo data)"
      EPIC_CLINIC_LABEL = "a tribal clinic on Epic (synthetic demo data)"

      def self.uds(population: SyntheticPopulation.default, clinic_label: CLINIC_LABEL)
        new(population: population,
          framework: "UDS Table 6B (HRSA)",
          measures: uds_measures,
          clinic_label: clinic_label)
      end

      # Kept for backward compatibility: the original UDS view.
      def self.default
        uds
      end

      # SALES DEMO ONLY — NOT CRS-faithful GPRA. This packages the demo's
      # UDS/eCQM-shaped measure logic (18-75 age bands, missing A1c counted
      # as poor control, no User Population base) under GPRA labels for a
      # sales narrative. Real CRS v25 semantics differ on all of those
      # points (see the divergence flags in docs/measures/): production and
      # onboarding GPRA is Rook::Crs::NationalGpraReport, never this. The
      # demo-gpra-* measure ids and the gem-hygiene test enforce the fence.
      def self.gpra(population: SyntheticPopulation.default, clinic_label: CLINIC_LABEL)
        new(population: population,
          framework: "IHS CRS / GPRA National Clinical Measures (demo preview)",
          measures: gpra_measures,
          clinic_label: clinic_label)
      end

      def initialize(population:, framework: "UDS Table 6B (HRSA)",
        period: DEFAULT_PERIOD, measures: self.class.uds_measures,
        clinic_label: CLINIC_LABEL)
        @population = population
        @framework = framework
        @period = ReportingPeriod.wrap(period)
        @measures = measures
        @clinic_label = clinic_label
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

      attr_reader :period, :framework, :clinic_label

      def patient_count
        @population.patients.size
      end

      # One Rook::MeasureResult per measure (MeasureReport-backed). The clinic
      # label rides on each MeasureReport as its reporter identity.
      def results
        @results ||= @measures.map do |measure|
          measure.evaluate(@population.patients, @period, reporter_display: clinic_label)
        end
      end
    end
  end
end
