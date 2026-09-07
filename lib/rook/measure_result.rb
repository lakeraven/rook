# frozen_string_literal: true

require "fhir_models"
require "rook/reporting_period"

module Rook
  # Engine-neutral measure result, backed by a FHIR R4 MeasureReport.
  #
  # MeasureReport is the engine's single native output (rook#92): whichever
  # engine evaluated the measure — the demo's plain-Ruby predicates or the
  # production ViewDefinition engine (rook#59) — results land in the same
  # summary MeasureReport shape, and every export format (UDS tables, CRS
  # flat files, dashboards) is a projection of it. The scalar readers here
  # (#denominator, #numerator, #rate) are themselves projections from the
  # wrapped MeasureReport, so renderers never depend on how the counts were
  # computed.
  #
  # The care-gap worklist rides alongside as CareGap entries (patient +
  # human-readable reason) and is also embedded in the MeasureReport as a
  # contained, subject-list-shaped FHIR List of patient references.
  class MeasureResult
    MEASURE_POPULATION_SYSTEM = "http://terminology.hl7.org/CodeSystem/measure-population"
    MEASURE_CANONICAL_BASE = "https://rook.lakeraven.com/fhir/Measure"
    CARE_GAP_LIST_ID = "care-gaps"

    # One care-gap worklist entry. +patient+ is any object with an #id (and
    # ideally a #name); +reason+ is the human-readable outreach reason.
    CareGap = Struct.new(:patient, :reason, keyword_init: true) do
      def patient_reference
        "Patient/#{patient.id}"
      end
    end

    # Builds a summary MeasureReport from population counts. This is the seam
    # every evaluation engine targets: hand over counts (plus the optional
    # care-gap worklist) and get the canonical result shape back.
    def self.from_counts(measure:, period:, denominator:, numerator:, care_gaps: [])
      period = ReportingPeriod.wrap(period)
      rate = denominator.zero? ? 0.0 : (numerator.to_f / denominator).round(4)

      report = FHIR::MeasureReport.new(
        status: "complete",
        type: "summary",
        measure: "#{MEASURE_CANONICAL_BASE}/#{measure.id}",
        period: period.to_fhir_period,
        group: [ {
          population: [
            population_entry("denominator", denominator),
            population_entry("numerator", numerator)
          ],
          measureScore: { value: rate }
        } ]
      )
      report.contained << care_gap_list(care_gaps) unless care_gaps.empty?

      new(measure: measure, period: period, measure_report: report, care_gaps: care_gaps)
    end

    def self.population_entry(code, count)
      { code: { coding: [ { system: MEASURE_POPULATION_SYSTEM, code: code } ] }, count: count }
    end
    private_class_method :population_entry

    # Subject-list-shaped evidence link: the care-gap patients as a FHIR List.
    def self.care_gap_list(care_gaps)
      FHIR::List.new(
        id: CARE_GAP_LIST_ID,
        status: "current",
        mode: "snapshot",
        title: "Care-gap worklist",
        entry: care_gaps.map do |gap|
          display = gap.patient.respond_to?(:name) ? gap.patient.name : nil
          { item: { reference: gap.patient_reference, display: display } }
        end
      )
    end
    private_class_method :care_gap_list

    def initialize(measure:, period:, measure_report:, care_gaps: [])
      @measure = measure
      @period = period
      @measure_report = measure_report
      @care_gaps = care_gaps.freeze
    end

    attr_reader :measure, :period, :measure_report, :care_gaps

    alias_method :to_fhir, :measure_report

    def denominator
      population_count("denominator")
    end

    def numerator
      population_count("numerator")
    end

    # Proportion in 0.0..1.0, projected from the MeasureReport's measureScore.
    def rate
      group&.measureScore&.value.to_f
    end

    def rate_percent
      (rate * 100).round(1)
    end

    private

    def group
      measure_report.group.first
    end

    def population_count(code)
      population = group&.population&.find do |entry|
        entry.code&.coding&.any? { |coding| coding.code == code }
      end
      population&.count.to_i
    end
  end
end
