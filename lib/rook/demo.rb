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
  # real measure engine. The demo *uses* the engine-neutral measure interfaces
  # (Rook::MeasureDefinition, Rook::MeasureResult, Rook::ReportingPeriod,
  # Rook::ValueSetResolver); the production ViewDefinition engine tracked in
  # rook#59 will implement the same interfaces. Keep this module out of that
  # path.
  module Demo
  end
end

require "rook/demo/synthetic_population"
require "rook/demo/value_sets"
require "rook/demo/measure"
require "rook/demo/measures/diabetes_hba1c_poor_control"
require "rook/demo/measures/controlling_high_blood_pressure"
require "rook/demo/measures/gpra/diabetes_poor_glycemic_control"
require "rook/demo/measures/gpra/controlling_high_blood_pressure"
require "rook/demo/measures/gpra/depression_screening"
require "rook/demo/report"
require "rook/demo/report_renderer"
require "rook/demo/gpra_report_renderer"
require "rook/demo/consortium_clinic"
require "rook/demo/consortium"
require "rook/demo/consortium_dashboard_renderer"
