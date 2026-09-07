# frozen_string_literal: true

# CRS parity step definitions (rook#99). Every step is PENDING until the
# CRS-faithful measure engine lands (rook#2) — loudly, never silently: running
# `cucumber --tags @crs-v25` reports each scenario as pending, and CI excludes
# them via the @wip tag, not by stubbing them green. When the engine arrives,
# these steps gain a rook driver; the CRS and golden drivers follow per the
# #99 design.
#
# The vocabulary is TYPED: one step per PCC/BHS-level fact, each with a
# canonical seed expansion defined in features/parity/VOCABULARY.md so the rook
# driver and the CRS FileMan-seeding driver materialize identical patients.
# A new fact gets a new step there — never a looser parse here.

PENDING_ENGINE = "awaiting the CRS-faithful measure engine (rook#2); " \
                 "scenario semantics are evidence-pinned in docs/measures/"

DATE = /\d{4}-\d{2}-\d{2}/

def seed_pending = pending(PENDING_ENGINE)

# -- Period and patient macros (canonical expansions in VOCABULARY.md) --------

Given(/^the report period is (#{DATE}) to (#{DATE})$/) do |_start_date, _end_date|
  seed_pending
end

Given(/^a (?:(female|male) )?User Population patient "([^"]*)" aged (\d+) at period end$/) do |_sex, _patient, _age|
  seed_pending
end

Given(/^a qualifying GPRA (diabetic|hypertensive) patient "([^"]*)"$/) do |_kind, _patient|
  seed_pending
end

# -- Visits -------------------------------------------------------------------

Given(/^"([^"]*)" has (\d+) ambulatory visits? during the report period$/) do |_patient, _count|
  seed_pending
end

# -- Diagnoses and Problem List -----------------------------------------------

Given(/^"([^"]*)" has a diabetes POV first recorded (#{DATE})$/) do |_patient, _date|
  seed_pending
end

Given(/^"([^"]*)" has a diabetes Problem List entry with status "([^"]*)" entered (#{DATE})$/) do |_patient, _status, _date|
  seed_pending
end

Given(/^"([^"]*)" has a hypertension POV recorded (#{DATE})$/) do |_patient, _date|
  seed_pending
end

Given(/^"([^"]*)" has no hypertension Problem List entry$/) do |_patient|
  seed_pending
end

Given(/^"([^"]*)" has an ESRD diagnosis recorded (#{DATE})$/) do |_patient, _date|
  seed_pending
end

Given(/^"([^"]*)" is documented currently pregnant during the report period$/) do |_patient|
  seed_pending
end

Given(/^"([^"]*)" has a mood disorder POV recorded (#{DATE})$/) do |_patient, _date|
  seed_pending
end

# -- Labs, CPT evidence, measurements -----------------------------------------

Given(/^"([^"]*)" has an A1c lab result of ([\d.]+) resulted (#{DATE})$/) do |_patient, _value, _date|
  seed_pending
end

Given(/^"([^"]*)" has an A1c lab test with no result on (#{DATE})$/) do |_patient, _date|
  seed_pending
end

Given(/^"([^"]*)" has no A1c documented during the report period$/) do |_patient|
  seed_pending
end

Given(/^"([^"]*)" has CPT "([^"]*)" recorded (#{DATE})$/) do |_patient, _code, _date|
  seed_pending
end

Given(/^"([^"]*)" has a BP reading of (\d+)\/(\d+) on (#{DATE}) at an ambulatory visit$/) do |_patient, _sys, _dia, _date|
  seed_pending
end

Given(/^"([^"]*)" has no BP reading during the report period$/) do |_patient|
  seed_pending
end

Given(/^"([^"]*)" has a PHQ-9 measurement recorded (#{DATE})$/) do |_patient, _date|
  seed_pending
end

# -- BHS-side facts -----------------------------------------------------------

Given(/^"([^"]*)" has a BHS depression screening \(problem code 14\.1\) recorded (#{DATE})$/) do |_patient, _date|
  seed_pending
end

Given(/^"([^"]*)" has a BH depression screening exam recorded (#{DATE}) with result "([^"]*)"$/) do |_patient, _date, _result|
  seed_pending
end

Given(/^"([^"]*)" has no depression screening during the report period$/) do |_patient|
  seed_pending
end

# -- Execution and membership assertions --------------------------------------

When("the National GPRA report is run") do
  seed_pending
end

Then(/^"([^"]*)" is (not )?in the "([^"]*)" (?:GPRA )?(numerator|denominator)$/) do |_patient, _negated, _label, _population|
  seed_pending
end

Then(/^"([^"]*)" is (not )?on the "([^"]*)" patient list$/) do |_patient, _negated, _list|
  seed_pending
end
