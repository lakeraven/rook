# frozen_string_literal: true

require "rook/value_set_resolver"

module Rook
  # In-memory Rook::ValueSetResolver: a frozen map of value-set URL to code
  # list, seeded at construction. Suitable for demos, tests, and small fixed
  # vocabularies; production resolution against a terminology service is
  # rook#63 and honors the same interface.
  class InMemoryValueSetResolver < ValueSetResolver
    # +value_sets+ maps a canonical value-set URL to an enumerable of codes.
    def initialize(value_sets = {})
      super()
      @value_sets = value_sets.to_h { |url, codes| [ url, Array(codes).map(&:to_s).freeze ] }.freeze
    end

    def codes(value_set_url)
      @value_sets.fetch(value_set_url) do
        raise KeyError, "unknown value set: #{value_set_url}"
      end
    end
  end
end
