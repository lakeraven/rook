# frozen_string_literal: true

require "rook/version"

module Rook
  class Error < StandardError; end
end

require "rook/vfc_eligibility_enforcement_service"
require "rook/reportable_condition_service"
require "rook/care_cascade/cascade_service"
