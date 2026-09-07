# frozen_string_literal: true

module Rook
  # Generic success/failure value object returned by enforcement services.
  #
  # Replaces bare `{ success:, reason: }` hashes. A failure always carries a
  # human-readable reason; a success never does.
  Result = Data.define(:success, :reason) do
    def self.success
      new(success: true, reason: nil)
    end

    def self.failure(reason)
      new(success: false, reason: reason)
    end

    def success?
      success
    end

    def failure?
      !success
    end
  end
end
