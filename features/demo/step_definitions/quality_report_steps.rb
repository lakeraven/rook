# frozen_string_literal: true

# DEMO / REFERENCE ONLY. Step definitions drive the real Rook::Demo::Report over
# the committed synthetic population — the user story executed, not mocked.
# No rspec: a tiny assert keeps this dependency-free.

def assert(condition, message)
  raise "BDD assertion failed: #{message}" unless condition
end

def result_for(title)
  result = @report.results.find { |r| r.measure.title == title }
  assert(result, "no measure titled #{title.inspect} in the report")
  result
end

# NB: "/" is the alternation operator in Cucumber Expressions, so the literal
# slash in "AI/AN" must be escaped.
Given("a synthetic population of {int} AI\\/AN patients") do |count|
  population = Rook::Demo::SyntheticPopulation.default
  assert(population.patients.size == count,
    "expected #{count} synthetic patients, got #{population.patients.size}")
end

When("I generate the UDS quality report") do
  @report = Rook::Demo::Report.uds
end

When("I generate the GPRA quality report") do
  @report = Rook::Demo::Report.gpra
end

Then("the report covers {int} patients") do |count|
  assert(@report.patient_count == count,
    "expected #{count} patients, got #{@report.patient_count}")
end

Then("the report is framed as {string}") do |framework|
  assert(@report.framework == framework,
    "expected framework #{framework.inspect}, got #{@report.framework.inspect}")
end

Then("the {string} measure reports {int} of {int} at {float}%") do |title, num, denom, pct|
  result = result_for(title)
  assert(result.numerator == num, "#{title}: numerator #{result.numerator} != #{num}")
  assert(result.denominator == denom, "#{title}: denominator #{result.denominator} != #{denom}")
  assert(result.rate_percent == pct, "#{title}: rate #{result.rate_percent}% != #{pct}%")
end

Then("the {string} measure lists {int} patients with a care gap") do |title, count|
  result = result_for(title)
  assert(result.care_gaps.size == count,
    "#{title}: care-gap worklist #{result.care_gaps.size} != #{count}")
end

Then("every care-gap entry names a patient and gives a reason") do
  @report.results.each do |result|
    result.care_gaps.each do |gap|
      assert(gap.patient && !gap.patient.name.strip.empty?, "care-gap entry has no patient name")
      assert(gap.reason && !gap.reason.strip.empty?, "care-gap entry has no reason")
    end
  end
end
