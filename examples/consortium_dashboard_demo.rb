# frozen_string_literal: true

# DEMO / REFERENCE ASSET — NOT the production measure engine.
#
# Builds the 3-clinic consortium demo (Rook::Demo::Consortium) — three
# SYNTHETIC clinics on mixed, generically-labeled EHRs, each with its own
# synthetic FHIR population, rolled up into a consortium-wide GPRA/UDS
# report — and writes it as a self-contained HTML dashboard. Prints the text
# summary to stdout.
#
# Usage:
#   ruby -Ilib examples/consortium_dashboard_demo.rb            # writes tmp/consortium_dashboard.html
#   ruby -Ilib examples/consortium_dashboard_demo.rb out.html   # writes out.html
#
# The production measure engine is the Pathling-based work in rook#65; this
# script is a presentation asset only and contains no real PHI or partner
# names.

require "fileutils"
require "rook/demo"

consortium = Rook::Demo::Consortium.build
renderer = Rook::Demo::ConsortiumDashboardRenderer.new(consortium)

puts renderer.to_text

out = ARGV[0] || File.expand_path("../tmp/consortium_dashboard.html", __dir__)
FileUtils.mkdir_p(File.dirname(out))
File.write(out, renderer.to_html)
puts "\nHTML dashboard written to: #{out}"
