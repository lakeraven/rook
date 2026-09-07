# frozen_string_literal: true

require "rook/reporting_period"
require "rook/measure_result"

module Rook
  # Engine-neutral base class for a quality-measure definition.
  #
  # A measure definition carries identity (#id, #title, #interpretation) and
  # references clinical vocabularies ONLY by value-set URL through an injected
  # Rook::ValueSetResolver — never by hardcoded code lists. Evaluation lands in
  # a Rook::MeasureResult (a FHIR MeasureReport, rook#92) regardless of which
  # engine computed the populations; the production ViewDefinition engine
  # (rook#59) targets the same interfaces via MeasureResult.from_counts.
  #
  # This class also provides an in-memory evaluation strategy over an
  # enumerable of patient objects, driven by three predicates a subclass
  # implements:
  #   #in_denominator?(patient, period) -> Boolean
  #   #in_numerator?(patient, period)   -> Boolean  (patient already in denom)
  #   #care_gap?(patient, period)       -> Boolean  (denom patient needing outreach)
  # plus #gap_reason(patient, period) for the care-gap worklist.
  class MeasureDefinition
    def initialize(value_set_resolver: nil)
      @value_set_resolver = value_set_resolver
    end

    attr_reader :value_set_resolver

    def id
      raise NotImplementedError
    end

    def title
      raise NotImplementedError
    end

    # Human-readable note on how to read the rate (higher vs lower is better).
    def interpretation
      raise NotImplementedError
    end

    # Short reason string for a care-gap worklist entry.
    def gap_reason(patient, period)
      raise NotImplementedError
    end

    # Evaluates the measure over an enumerable of patients and returns the
    # canonical Rook::MeasureResult (MeasureReport-backed).
    def evaluate(patients, period)
      period = ReportingPeriod.wrap(period)
      gaps = care_gaps(patients, period).map do |patient|
        MeasureResult::CareGap.new(patient: patient, reason: gap_reason(patient, period))
      end

      MeasureResult.from_counts(
        measure: self,
        period: period,
        denominator: denominator(patients, period).size,
        numerator: numerator(patients, period).size,
        care_gaps: gaps
      )
    end

    def denominator(patients, period)
      patients.select { |p| in_denominator?(p, period) }
    end

    def numerator(patients, period)
      denominator(patients, period).select { |p| in_numerator?(p, period) }
    end

    # Denominator patients who need outreach (the care-gap worklist).
    def care_gaps(patients, period)
      denominator(patients, period).select { |p| care_gap?(p, period) }
    end

    def rate(patients, period)
      denom = denominator(patients, period).size
      return 0.0 if denom.zero?

      (numerator(patients, period).size.to_f / denom).round(4)
    end

    private

    # Expands a value-set URL to its code list via the injected resolver.
    def codes_in(value_set_url)
      raise "#{self.class} references value sets but has no value_set_resolver" unless value_set_resolver

      value_set_resolver.codes(value_set_url)
    end
  end
end
