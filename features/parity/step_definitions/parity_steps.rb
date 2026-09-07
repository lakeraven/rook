# frozen_string_literal: true

# CRS parity step definitions (rook#99). Every step is PENDING until the
# CRS-faithful measure engine lands (rook#2) — loudly, never silently: running
# `cucumber --tags @crs-v25` reports each scenario as pending, and CI excludes
# them via the @wip tag, not by stubbing them green. When the engine arrives,
# these steps gain a rook driver; the CRS and golden drivers follow per the
# #99 design.
#
# Seed steps speak PCC-level facts (visits, POVs, Problem List entries, labs,
# measurements, BHS records) — the driver-neutral vocabulary both the rook
# driver and the CRS driver (FileMan seeding) will translate.

PENDING_ENGINE = "awaiting the CRS-faithful measure engine (rook#2); " \
                 "scenario semantics are evidence-pinned in docs/measures/"

Given("the report period is {word} to {word}") do |_start_date, _end_date|
  pending(PENDING_ENGINE)
end

Given(/^a User Population patient "([^"]*)" aged (\d+) at period end$/) do |_patient, _age|
  pending(PENDING_ENGINE)
end

Given(/^a qualifying GPRA (?:diabetic|hypertensive) patient "([^"]*)"$/) do |_patient|
  pending(PENDING_ENGINE)
end

Given(/^"([^"]*)" (?:has|had|is)(?: an?)? (.+)$/) do |_patient, _fact|
  pending(PENDING_ENGINE)
end

When("the National GPRA report is run") do
  pending(PENDING_ENGINE)
end

Then(/^"([^"]*)" is (?:in|on) the (.+)$/) do |_patient, _membership|
  pending(PENDING_ENGINE)
end

Then(/^"([^"]*)" is not in the (.+)$/) do |_patient, _membership|
  pending(PENDING_ENGINE)
end
