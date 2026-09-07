# frozen_string_literal: true

require "rook/measure_definition"
require "rook/demo/value_sets"

module Rook
  module Demo
    # DEMO / REFERENCE ONLY — see Rook::Demo.
    #
    # Base class for the hardcoded demo measures: a Rook::MeasureDefinition
    # wired to the demo's in-memory value sets (Rook::Demo::ValueSets). The
    # demo *uses* the engine-neutral measure interfaces
    # (Rook::MeasureDefinition, Rook::MeasureResult, Rook::ValueSetResolver);
    # the production ViewDefinition engine tracked in rook#59 will implement
    # the same interfaces. Do not grow this into a substitute for it.
    #
    # Subclasses implement the predicates documented on
    # Rook::MeasureDefinition (#in_denominator?, #in_numerator?, #care_gap?,
    # #gap_reason).
    class Measure < MeasureDefinition
      def initialize(value_set_resolver: ValueSets.resolver)
        super
      end
    end
  end
end
