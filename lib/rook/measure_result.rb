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
  # human-readable reason) on the Ruby object only. The summary MeasureReport
  # stays clean of subject-level data (mrt-2); patient-level evidence will
  # land later as a proper subject-list MeasureReport (rook#92).
  class MeasureResult
    MEASURE_POPULATION_SYSTEM = "http://terminology.hl7.org/CodeSystem/measure-population"
    IMPROVEMENT_NOTATION_SYSTEM = "http://terminology.hl7.org/CodeSystem/measure-improvement-notation"
    IMPROVEMENT_NOTATIONS = %i[increase decrease].freeze
    MEASURE_CANONICAL_BASE = "https://rook.lakeraven.com/fhir/Measure"

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
    #
    # The signature will grow — exclusions, initial-population, stratifiers,
    # and external measure canonicals are tracked in rook#59/#92.
    #
    # +improvement_notation+ defaults from the measure's own declaration
    # (#improvement_notation, when the measure responds to it), falling back
    # to :increase; an explicit argument overrides the measure.
    #
    # +reporter_display+ (optional) names the reporting organization — e.g. a
    # clinic label or a consortium label — as MeasureReport.reporter (a
    # display-only Organization-style Reference), so reports for the same
    # measure and period from different reporters stay distinguishable.
    def self.from_counts(measure:, period:, denominator:, numerator:, care_gaps: [],
      improvement_notation: nil, reporter_display: nil)
      validate_counts!(denominator, numerator)
      improvement_notation ||= default_improvement_notation(measure)
      unless IMPROVEMENT_NOTATIONS.include?(improvement_notation)
        raise ArgumentError, "improvement_notation must be :increase or :decrease, got #{improvement_notation.inspect}"
      end

      period = ReportingPeriod.wrap(period)
      group = {
        population: [
          population_entry("denominator", denominator),
          population_entry("numerator", numerator)
        ]
      }
      # A zero denominator has no meaningful proportion: omit measureScore
      # entirely (the #rate reader projects an absent score as 0.0).
      group[:measureScore] = { value: (numerator.to_f / denominator).round(4) } if denominator.positive?

      attributes = {
        status: "complete",
        type: "summary",
        measure: "#{MEASURE_CANONICAL_BASE}/#{measure.id}",
        period: period.to_fhir_period,
        improvementNotation: {
          coding: [ { system: IMPROVEMENT_NOTATION_SYSTEM, code: improvement_notation.to_s } ]
        },
        group: [ group ]
      }
      attributes[:reporter] = { display: reporter_display } if reporter_display
      report = FHIR::MeasureReport.new(attributes)

      new(measure: measure, period: period, measure_report: report, care_gaps: care_gaps)
    end

    def self.default_improvement_notation(measure)
      measure.respond_to?(:improvement_notation) ? measure.improvement_notation : :increase
    end
    private_class_method :default_improvement_notation

    def self.validate_counts!(denominator, numerator)
      unless denominator.is_a?(Integer) && denominator >= 0
        raise ArgumentError, "denominator must be a non-negative Integer, got #{denominator.inspect}"
      end
      unless numerator.is_a?(Integer) && numerator >= 0
        raise ArgumentError, "numerator must be a non-negative Integer, got #{numerator.inspect}"
      end
      raise ArgumentError, "numerator #{numerator} exceeds denominator #{denominator}" if numerator > denominator
    end
    private_class_method :validate_counts!

    def self.population_entry(code, count)
      { code: { coding: [ { system: MEASURE_POPULATION_SYSTEM, code: code } ] }, count: count }
    end
    private_class_method :population_entry

    # Wraps an already-built summary MeasureReport. The report must carry the
    # canonical shape the scalar readers project from: a group with integer
    # denominator and numerator population counts, and a measureScore whenever
    # the denominator is nonzero (a zero denominator legitimately omits the
    # score). Anything else raises ArgumentError — loudly, instead of the
    # readers silently coercing a wrong-shape report to 0 / 0.0.
    def initialize(measure:, period:, measure_report:, care_gaps: [])
      @measure = measure
      @period = period
      @measure_report = measure_report
      @care_gaps = care_gaps.freeze
      validate_report_shape!
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

    def validate_report_shape!
      raise ArgumentError, "MeasureReport must have a group" if group.nil?

      %w[denominator numerator].each do |code|
        count = raw_population_count(code)
        unless count.is_a?(Integer)
          raise ArgumentError, "MeasureReport group must carry an integer #{code} population count"
        end
      end
      return unless population_count("denominator").positive?
      return unless group.measureScore&.value.nil?

      raise ArgumentError, "MeasureReport with a nonzero denominator must carry a measureScore"
    end

    def group
      measure_report.group.first
    end

    def population_count(code)
      # Guaranteed an Integer by #validate_report_shape!.
      raw_population_count(code)
    end

    def raw_population_count(code)
      population = group&.population&.find do |entry|
        entry.code&.coding&.any? { |coding| coding.code == code }
      end
      population&.count
    end
  end
end
