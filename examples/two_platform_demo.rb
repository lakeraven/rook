# frozen_string_literal: true

# DEMO / REFERENCE ASSET — NOT the production measure engine.
#
# The EHR-agnostic beat (rook#101): the SAME measure implementations computed
# over platform-flavored bulk exports — the first synthetic population
# (RPMS-flavored feeds), the Epic-shaped export, and the Greenway-shaped
# export — all loaded through the same Rook::Ingest NDJSON seam, differing
# only in their SourceDescriptors. Prints a side-by-side rate table, then
# writes the Epic and Greenway clinics' UDS and GPRA HTML reports.
#
# Usage:
#   ruby -Ilib examples/two_platform_demo.rb           # writes tmp/{epic,greenway}_*.html
#   ruby -Ilib examples/two_platform_demo.rb outdir    # writes outdir/{epic,greenway}_*.html
#
# Synthetic data only; no vendor API involvement, no real PHI.

require "fileutils"
require "rook/demo"

populations = {
  "RPMS-flavored clinic" => Rook::Demo::SyntheticPopulation.default,
  "Epic-flavored clinic" => Rook::Demo::SyntheticPopulation.epic,
  "Greenway-flavored clinic" => Rook::Demo::SyntheticPopulation.greenway
}

puts "Same measures, three platform exports, one ingest seam"
puts "=" * 72

reports = populations.transform_values do |population|
  Rook::Demo::Report.gpra(population: population)
end

name_width = populations.keys.map(&:length).max
measure_titles = reports.values.first.results.map { |r| r.measure.title }

measure_titles.each_with_index do |title, index|
  puts "\n#{title}"
  reports.each do |name, report|
    result = report.results[index]
    puts format("  %-#{name_width}s  %3d/%-3d  %5.1f%%",
      name, result.numerator, result.denominator, result.rate_percent)
  end
end

puts "\n(Same Rook::Demo measure classes; the populations load through the"
puts " same Rook::Ingest seam under :rpms, :epic and :greenway source descriptors.)"

out_dir = ARGV[0] || File.expand_path("../tmp", __dir__)
FileUtils.mkdir_p(out_dir)

{
  "epic" => [ populations.fetch("Epic-flavored clinic"), Rook::Demo::Report::EPIC_CLINIC_LABEL ],
  "greenway" => [ populations.fetch("Greenway-flavored clinic"), Rook::Demo::Report::GREENWAY_CLINIC_LABEL ]
}.each do |prefix, (population, clinic_label)|
  {
    "#{prefix}_uds_report.html" => Rook::Demo::ReportRenderer.new(
      Rook::Demo::Report.uds(population: population, clinic_label: clinic_label)),
    "#{prefix}_gpra_report.html" => Rook::Demo::GPRAReportRenderer.new(
      Rook::Demo::Report.gpra(population: population, clinic_label: clinic_label))
  }.each do |filename, renderer|
    path = File.join(out_dir, filename)
    File.write(path, renderer.to_html)
    puts "Wrote #{path}"
  end
end
