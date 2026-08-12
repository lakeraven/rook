# frozen_string_literal: true

module Rook
  # DEMO / REFERENCE ASSET — NOT the production measure engine.
  #
  # Rook::Demo is a small, plain-Ruby, sales-demo illustration of UDS quality
  # reporting over a synthetic FHIR R4 population. It hardcodes two UDS Table 6B
  # measures and renders a presentable report with per-measure denominator /
  # numerator / rate and a care-gap worklist.
  #
  # It is intentionally minimal and MUST NOT be mistaken for, or grown into, the
  # real measure engine. Production measure execution is the CSIRO Pathling-based
  # work tracked in rook#60 (spike) and rook#65 (IHS measure library). Keep this
  # module out of that path.
  module Demo
  end
end

require "rook/demo/synthetic_population"
require "rook/demo/measure"
require "rook/demo/measures/diabetes_hba1c_poor_control"
require "rook/demo/measures/controlling_high_blood_pressure"
require "rook/demo/measures/gpra/diabetes_poor_glycemic_control"
require "rook/demo/measures/gpra/controlling_high_blood_pressure"
require "rook/demo/measures/gpra/depression_screening"
require "rook/demo/report"
require "rook/demo/report_renderer"
require "rook/demo/gpra_report_renderer"
