# frozen_string_literal: true

require "rook/measure_result"
require "rook/demo/consortium_clinic"
require "rook/demo/report"

module Rook
  module Demo
    # DEMO / REFERENCE ONLY — see Rook::Demo. NOT the production engine.
    #
    # Builds the 3-clinic consortium demo: three SYNTHETIC clinics on mixed,
    # GENERICALLY-labeled EHRs, each with its own synthetic FHIR population
    # and its own GPRA Report, rolled up into a consortium-wide denominator /
    # numerator / rate per measure.
    #
    # This is the sales-demo point made concrete: clinics whose own (non-RPMS)
    # EHRs give them no IHS GPRA/UDS reporting get one anyway — computed the
    # SAME way (stock FHIR, EHR-agnostic) as the single-clinic GPRA/UDS demo
    # (Report / GPRAReportRenderer), just summed across clinics.
    class Consortium
      NAME = "Meridian Tribal Health Consortium"

      # One clinic's built population plus its own GPRA Report.
      ClinicReport = Struct.new(:clinic, :report, keyword_init: true) do
        def name
          clinic.name
        end

        def ehr_label
          clinic.ehr_label
        end

        def patient_count
          report.patient_count
        end
      end

      # Consortium-wide total for one measure: a MeasureReport-backed
      # Rook::MeasureResult built from the summed clinic counts, tagged with
      # the reporting regime for the dashboard.
      Rollup = Struct.new(:result, :regime, keyword_init: true) do
        def measure
          result.measure
        end

        def denominator
          result.denominator
        end

        def numerator
          result.numerator
        end

        def rate
          result.rate
        end

        def rate_percent
          result.rate_percent
        end
      end

      # Regime tag surfaced on the dashboard: the point of the demo is that
      # ONE engine computes both the legacy GPRA measure and the modern
      # eCQM/UDS measures from the same stock FHIR population.
      REGIME_BY_MEASURE_ID = {
        "gpra-diabetes-poor-glycemic-control" => "GPRA (legacy)",
        "gpra-controlling-high-blood-pressure" => "eCQM (modern)",
        "gpra-depression-screening" => "eCQM (modern)"
      }.freeze

      PROFILES = [
        ConsortiumClinic::Profile.new(
          name: "Cottonwood Bend Community Clinic", ehr_label: "Ambulatory EHR A",
          id_prefix: "cbc", patient_count: 60,
          diabetes_poor_control_fraction: 0.35, bp_controlled_fraction: 0.62,
          depression_screened_fraction: 0.82
        ),
        ConsortiumClinic::Profile.new(
          name: "Painted Hills Health Center", ehr_label: "Ambulatory EHR A",
          id_prefix: "phh", patient_count: 30,
          diabetes_poor_control_fraction: 0.22, bp_controlled_fraction: 0.74,
          depression_screened_fraction: 0.90
        ),
        ConsortiumClinic::Profile.new(
          name: "Cedar Flats Urban Indian Clinic", ehr_label: "Ambulatory EHR B",
          id_prefix: "cfc", patient_count: 45,
          diabetes_poor_control_fraction: 0.48, bp_controlled_fraction: 0.55,
          depression_screened_fraction: 0.68
        )
      ].freeze

      def self.build
        new
      end

      def initialize(profiles: PROFILES)
        raise ArgumentError, "Consortium requires at least one clinic profile" if profiles.empty?

        @clinic_reports = profiles.map do |profile|
          clinic = ConsortiumClinic.build(profile)
          report = Report.new(population: clinic.population,
            framework: "IHS CRS / GPRA National Clinical Measures",
            measures: Report.gpra_measures)
          ClinicReport.new(clinic: clinic, report: report)
        end
      end

      attr_reader :clinic_reports

      def name
        NAME
      end

      def clinic_count
        @clinic_reports.size
      end

      def total_patients
        @clinic_reports.sum(&:patient_count)
      end

      # Canonical, ordered measure list (identical ids/titles across every
      # clinic's Report — only instances differ).
      def measures
        @clinic_reports.first.report.results.map(&:measure)
      end

      def rollup
        @rollup ||= measures.map do |measure|
          results = @clinic_reports.map { |cr| result_for(cr.report, measure.id) }
          result = MeasureResult.from_counts(
            measure: measure,
            period: @clinic_reports.first.report.period,
            denominator: results.sum(&:denominator),
            numerator: results.sum(&:numerator),
            improvement_notation: measure.improvement_notation
          )
          Rollup.new(result: result, regime: REGIME_BY_MEASURE_ID.fetch(measure.id, "GPRA (legacy)"))
        end
      end

      private

      def result_for(report, measure_id)
        report.results.find { |r| r.measure.id == measure_id } ||
          raise("no result for measure #{measure_id}")
      end
    end
  end
end
