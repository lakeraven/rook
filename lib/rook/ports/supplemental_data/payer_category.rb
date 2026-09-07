# frozen_string_literal: true

module Rook
  module Ports
    module SupplementalData
      # The UDS payer-category vocabulary. Payer category is NOT a
      # supplemental attribute Observation — it rides as FHIR::Coverage
      # resources returned by Base#patient_coverages, with
      # +Coverage.type.coding+ = [{system: CODE_SYSTEM, code: <category>}].
      #
      # Ships as FHIR terminology artifacts alongside the attribute
      # vocabulary — see Attributes.
      module PayerCategory
        # Internal code system URI for Coverage.type codings.
        CODE_SYSTEM = "https://terminology.lakeraven.com/CodeSystem/uds-payer-category"

        ALL = %w[medicaid medicare private uninsured other-public].freeze
      end
    end
  end
end
