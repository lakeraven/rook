# frozen_string_literal: true

# DEMO / REFERENCE ASSET — NOT the production measure engine.
#
# Runs the demo-scoped IHS CRS / GPRA quality report over the committed
# synthetic FHIR population, prints a text summary to stdout, and writes an
# HTML report. Renders the SAME measure computations as the UDS demo
# (examples/uds_report_demo.rb), packaged as IHS national GPRA measures.
#
# Usage:
#   ruby -Ilib examples/gpra_report_demo.rb            # writes tmp/gpra_report.html
#   ruby -Ilib examples/gpra_report_demo.rb out.html   # writes out.html
#
# The production measure engine is the Pathling-based work in rook#65; this
# script is a presentation asset only and contains no real PHI.

require "fileutils"
require "rook/demo"

report = Rook::Demo::Report.gpra
renderer = Rook::Demo::GPRAReportRenderer.new(report)

puts renderer.to_text

out = ARGV[0] || File.expand_path("../tmp/gpra_report.html", __dir__)
FileUtils.mkdir_p(File.dirname(out))
File.write(out, renderer.to_html)
puts "\nHTML report written to: #{out}"
