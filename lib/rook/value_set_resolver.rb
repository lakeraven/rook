# frozen_string_literal: true

module Rook
  # Port for value-set expansion: measures reference value sets by canonical
  # identifier/URL and never carry code lists themselves.
  #
  # Implementations answer "which codes are in this value set?" — the in-memory
  # resolver (Rook::InMemoryValueSetResolver) for demos and tests, and a
  # terminology-server-backed resolver (rook#63) that expands the same URLs via
  # a FHIR terminology service can drop in behind the same two methods.
  #
  # Matching is intentionally exact-string and code-only (system-blind) for the
  # demo resolver; the terminology-backed resolver (rook#63) should introduce
  # system-aware (system, code) pairs behind this same port.
  class ValueSetResolver
    # Returns the flat array of code strings in the value set's expansion.
    def codes(value_set_url)
      raise NotImplementedError, "#{self.class} must implement #codes"
    end

    # Membership test; override when a backend can answer without expanding.
    def include?(value_set_url, code)
      codes(value_set_url).include?(code)
    end
  end
end
