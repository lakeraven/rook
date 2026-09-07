# frozen_string_literal: true

require "date"
require "fhir_models"

module Rook
  # Engine-neutral measurement-period value object.
  #
  # An inclusive calendar interval shared by every measure evaluation: the
  # demo's plain-Ruby measures, the production ViewDefinition engine (rook#59),
  # and any future CQL engine all evaluate against the same period shape and
  # stamp it onto the resulting FHIR MeasureReport.
  #
  # Immutable. Also accepts/wraps a plain Date Range for convenience.
  class ReportingPeriod
    attr_reader :start_date, :end_date

    # Coerces a ReportingPeriod or a Date Range (inclusive or exclusive-end).
    def self.wrap(period)
      return period if period.is_a?(self)

      end_date = period.last
      end_date -= 1 if period.respond_to?(:exclude_end?) && period.exclude_end?
      new(period.first, end_date)
    end

    def initialize(start_date, end_date)
      raise ArgumentError, "period end #{end_date} precedes start #{start_date}" if end_date < start_date

      @start_date = start_date
      @end_date = end_date
      freeze
    end

    def cover?(date)
      date >= start_date && date <= end_date
    end

    # Range-compatible accessors so callers can treat a ReportingPeriod like
    # the inclusive Date Range it replaces.
    alias_method :first, :start_date
    alias_method :last, :end_date
    alias_method :end, :end_date

    # Projects the period as a FHIR R4 Period (for MeasureReport.period).
    def to_fhir_period
      FHIR::Period.new(start: start_date.iso8601, end: end_date.iso8601)
    end

    def ==(other)
      other.is_a?(self.class) && start_date == other.start_date && end_date == other.end_date
    end
    alias_method :eql?, :==

    def hash
      [ self.class, start_date, end_date ].hash
    end
  end
end
