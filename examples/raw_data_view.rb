# frozen_string_literal: true

# DEMO / REFERENCE ASSET — NOT the production measure engine.
#
# Writes an HTML page showing the raw synthetic FHIR data a demo report is
# computed from: one row per patient (demographics, condition codes, HbA1c,
# BP, PHQ-9, UDS supplemental attributes and payer), each expandable to the
# exact resources ingested. Pairs with the UDS/GPRA reports so a viewer can
# trace any rate back to its inputs.
#
# Usage:
#   ruby -Ilib examples/raw_data_view.rb                    # greenway -> tmp/greenway_raw_data.html
#   ruby -Ilib examples/raw_data_view.rb epic               # epic     -> tmp/epic_raw_data.html
#   ruby -Ilib examples/raw_data_view.rb rpms out.html      # rpms     -> out.html
#
# Reads the committed NDJSON fixtures directly (the bytes the ingest seam
# reads); synthetic data only, no real PHI.

require "cgi/escape"
require "fileutils"
require "json"
require "rook/demo"

FIXTURE_DIRS = {
  "rpms" => Rook::Demo::SyntheticPopulation::FIXTURES_DIR,
  "epic" => File.join(Rook::Demo::SyntheticPopulation::FIXTURES_DIR, "epic"),
  "greenway" => File.join(Rook::Demo::SyntheticPopulation::FIXTURES_DIR, "greenway")
}.freeze

HBA1C = "4548-4"
BP_PANEL = "85354-9"
PHQ9 = "44261-6"

platform = (ARGV[0] || "greenway").downcase
fixtures = FIXTURE_DIRS.fetch(platform) { abort "unknown platform #{platform.inspect}; use #{FIXTURE_DIRS.keys.join('|')}" }
out = ARGV[1] || File.expand_path("../tmp/#{platform}_raw_data.html", __dir__)

resources = Dir[File.join(fixtures, "{primary_fhir,supplemental}", "*.ndjson")].sort.flat_map do |path|
  File.foreach(path).reject { |line| line.strip.empty? }.map { |line| JSON.parse(line) }
end
patients = resources.select { |r| r["resourceType"] == "Patient" }
linked = resources.reject { |r| r["resourceType"] == "Patient" }.group_by do |r|
  (r.dig("subject", "reference") || r.dig("beneficiary", "reference")).to_s.split("/").last
end

def h(value)
  CGI.escapeHTML(value.to_s)
end

def code_of(resource)
  resource.dig("code", "coding", 0, "code")
end

def on(resource)
  resource["effectiveDateTime"].to_s[0, 10]
end

rows = patients.map do |patient|
  related = linked.fetch(patient["id"], [])
  observations = related.select { |r| r["resourceType"] == "Observation" }
  by_code = ->(code) { observations.select { |o| code_of(o) == code } }

  conditions = related.select { |r| r["resourceType"] == "Condition" }
    .map { |c| c.dig("code", "coding").map { |coding| coding["code"] }.join(" / ") }
  a1c = by_code.(HBA1C).map { |o| "#{o.dig('valueQuantity', 'value')}% (#{on(o)})" }
  bp = by_code.(BP_PANEL).map do |o|
    sys, dia = o["component"].map { |c| c.dig("valueQuantity", "value") }
    "#{sys}/#{dia} (#{on(o)})"
  end
  phq = by_code.(PHQ9).map { |o| "#{o.dig('valueQuantity', 'value')} (#{on(o)})" }
  supplemental = observations
    .select { |o| o.dig("code", "coding", 0, "system") == Rook::Demo::SyntheticPopulation::SUPPLEMENTAL_ATTRIBUTE_SYSTEM }
    .map { |o| "#{code_of(o)}: #{o.dig('valueCodeableConcept', 'coding', 0, 'code')}" }
  payers = related.select { |r| r["resourceType"] == "Coverage" }.map { |c| "payer: #{c.dig('type', 'coding', 0, 'code')}" }
  raw = ([ patient ] + related).map { |r| JSON.pretty_generate(r) }.join("\n\n")
  name = [ patient.dig("name", 0, "given", 0), patient.dig("name", 0, "family") ].compact.join(" ")

  <<~ROW
    <tr><td>#{h name}<br><small>#{h patient['id']}</small></td><td>#{h patient['gender']}</td>
    <td>#{h patient['birthDate']}</td><td>#{conditions.map { |c| h c }.join('<br>')}</td>
    <td>#{a1c.map { |v| h v }.join('<br>')}</td><td>#{bp.map { |v| h v }.join('<br>')}</td>
    <td>#{phq.map { |v| h v }.join('<br>')}</td><td>#{(supplemental + payers).map { |v| h v }.join('<br>')}</td></tr>
    <tr class="raw"><td colspan="8"><details><summary>Raw FHIR (#{related.size + 1} resources)</summary><pre>#{h raw}</pre></details></td></tr>
  ROW
end

FileUtils.mkdir_p(File.dirname(out))
File.write(out, <<~HTML)
  <!doctype html>
  <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Raw Source Data</title>
  <style>
    :root { --bg: #fff; --fg: #111; --muted: #666; --line: #ccc; --head: #f2f2f2; --code: #f7f7f7; }
    @media (prefers-color-scheme: dark) { :root { --bg: #161616; --fg: #eee; --muted: #999; --line: #444; --head: #222; --code: #1e1e1e; } }
    body { font: 14px/1.4 system-ui, sans-serif; margin: 24px 16px; background: var(--bg); color: var(--fg); }
    .wrap { overflow-x: auto; }
    table { border-collapse: collapse; width: 100%; }
    th, td { border: 1px solid var(--line); padding: 4px 6px; vertical-align: top; text-align: left; }
    th { background: var(--head); }
    small { color: var(--muted); }
    pre { font-size: 11px; max-height: 320px; overflow: auto; background: var(--code); padding: 8px; }
  </style></head><body>
  <h1>Raw source data behind the report</h1>
  <p>Synthetic FHIR R4 bulk export (#{h platform}-flavored, DEMO / SYNTHETIC DATA, no real PHI):
  #{patients.size} patients, #{resources.size} resources. Report period 2025-01-01 to 2025-12-31.
  Expand a row to see the exact FHIR resources ingested.</p>
  <div class="wrap"><table>
  <tr><th>Patient</th><th>Sex</th><th>DOB</th><th>Conditions</th><th>HbA1c</th><th>BP</th><th>PHQ-9</th><th>UDS supplemental</th></tr>
  #{rows.join}
  </table></div></body></html>
HTML
puts "Raw data view written to: #{out}"
