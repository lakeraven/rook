# frozen_string_literal: true

require "rook/reporting_period"
require "rook/crs/population"
require "rook/crs/measures"

module Rook
  module Crs
    # The CRS-faithful National GPRA report over an ingest-seam resource set:
    # evaluates the encoded v25 measures, keeps MeasureReport-backed results
    # (the native output every projection — #98 flat file included — reads
    # from), and exposes per-patient population membership, which is what the
    # parity harness (#99) diffs patient-by-patient against real CRS.
    #
    # Membership labels match features/parity/VOCABULARY.md.
    class NationalGpraReport
      MEASURES = {
        "Diabetes: Glycemic Control" => -> { Measures::PoorGlycemicControl.new },
        "Poor Glycemic Control" => -> { Measures::PoorGlycemicControl.new },
        "Good Glycemic Control" => -> { Measures::GoodGlycemicControl.new },
        "Controlling High Blood Pressure" => -> { Measures::ControllingHighBloodPressure.new },
        "Depression Screening 12-17" => -> {
          Measures::DepressionScreening.new(age_range: 12..17, stratum_label: "12-17")
        },
        "Depression Screening 18+" => -> {
          Measures::DepressionScreening.new(age_range: 18.., stratum_label: "18+")
        }
      }.freeze

      def initialize(resources:, period:)
        @population = Population.new(resources)
        @period = ReportingPeriod.wrap(period)
        @measures = MEASURES.transform_values(&:call)
      end

      attr_reader :period

      # One MeasureReport-backed result per distinct measure.
      def results
        @results ||= @measures.values.uniq(&:id).map do |measure|
          measure.evaluate(@population.patients, @period)
        end
      end

      def in_denominator?(patient_id, label)
        membership(label, :denominator).include?(patient_id.to_s)
      end

      def in_numerator?(patient_id, label)
        membership(label, :numerator).include?(patient_id.to_s)
      end

      # CRS patient lists (§2.1.2.7). Trio scope: the no-documented-A1c list;
      # the remaining lists arrive with their measures.
      def on_patient_list?(patient_id, list)
        case list
        when "diabetic patients without a documented A1c"
          measure = @measures.fetch("Diabetes: Glycemic Control")
          measure.denominator(@population.patients, @period)
                 .reject { |p| p.a1c_documented?(@period) }
                 .map(&:id).include?(patient_id.to_s)
        else
          raise ArgumentError, "unknown patient list: #{list.inspect}"
        end
      end

      private

      def membership(label, population_kind)
        measure = @measures.fetch(label) do
          raise ArgumentError, "unknown membership label: #{label.inspect} " \
                               "(see features/parity/VOCABULARY.md)"
        end
        patients =
          case population_kind
          when :denominator then measure.denominator(@population.patients, @period)
          when :numerator then measure.numerator(@population.patients, @period)
          end
        patients.map(&:id)
      end
    end
  end
end
