# frozen_string_literal: true

require "rook/version"
require "rook/vfc_eligibility_enforcement_service"
require "rook/reportable_condition_service"

# Demo / reference asset (synthetic UDS quality report) — NOT the production
# measure engine. See lib/rook/demo.rb and rook#65 (Pathling-based engine).
require "rook/demo"

module Rook
  class Error < StandardError; end
end
