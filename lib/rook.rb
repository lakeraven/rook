# frozen_string_literal: true

require "rook/version"
require "rook/result"
require "rook/ports"
require "rook/vfc_eligibility_enforcement_service"
require "rook/reportable_condition_service"

# Engine-neutral measure core: measure definitions, reporting periods,
# value-set resolution, and MeasureReport-backed results (rook#92). Every
# evaluation engine — the demo below today, the production ViewDefinition
# engine (rook#59) — lands results in these shapes.
require "rook/reporting_period"
require "rook/value_set_resolver"
require "rook/in_memory_value_set_resolver"
require "rook/measure_result"
require "rook/measure_definition"

# Demo / reference asset (synthetic UDS quality report) — NOT the production
# measure engine. It uses the neutral interfaces above; see lib/rook/demo.rb.
require "rook/demo"

module Rook
  class Error < StandardError; end
end
