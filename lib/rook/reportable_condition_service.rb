# frozen_string_literal: true

module Rook
  # Detects whether a diagnosis is a reportable condition per public health
  # surveillance requirements. Supports configurable condition lists by
  # jurisdiction (federal, state, tribal).
  #
  # Used by electronic case reporting (eCR) workflows to trigger eICR
  # generation when a reportable condition is diagnosed.
  class ReportableConditionService
    def initialize(conditions:, jurisdiction: "US")
      @conditions = conditions
      @jurisdiction = jurisdiction
      @code_index = build_code_index
    end

    # Check whether a diagnosis code is reportable.
    # Returns { reportable: true/false, condition_name:, jurisdiction:, urgency: }
    def check(diagnosis_code:, diagnosis_display: nil)
      return not_reportable_result if diagnosis_code.nil? || diagnosis_code.to_s.strip.empty?

      condition = @code_index[diagnosis_code]
      if condition
        {
          reportable: true,
          condition_name: condition[:name],
          jurisdiction: @jurisdiction,
          urgency: condition[:urgency]
        }
      else
        not_reportable_result
      end
    end

    private

    def build_code_index
      index = {}
      @conditions.each do |condition|
        condition[:codes].each { |code| index[code] = condition }
      end
      index
    end

    def not_reportable_result
      { reportable: false, condition_name: nil, jurisdiction: @jurisdiction, urgency: nil }
    end
  end
end
