# frozen_string_literal: true

module Rook
  module CareCascade
    # One ordered step in a screening-to-treatment care cascade.
    #
    # +actionable+ marks a stage where a patient stalling here represents a
    # care gap that should feed an outreach worklist (e.g. reactive-but-not-
    # confirmed). Non-actionable stages are either the entry cohort
    # (+screened+) or a resolved/terminal state (a negative confirmation, or
    # completed treatment) where stalling is expected and needs no follow-up.
    class Stage
      attr_reader :key, :label, :actionable, :ordinal

      def initialize(key:, label:, ordinal:, actionable: false)
        @key = key
        @label = label
        @ordinal = ordinal
        @actionable = actionable
      end

      def actionable?
        @actionable
      end

      def to_h
        { key: key, label: label, ordinal: ordinal, actionable: actionable }
      end
    end
  end
end
