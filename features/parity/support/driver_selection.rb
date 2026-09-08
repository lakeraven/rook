# frozen_string_literal: true

require_relative "crs_twin"

# Driver selection for the parity features (#99): the same Gherkin runs
# against different systems.
#
#   DRIVER=rook (default)  seeds FHIR through the ingest seam and asserts
#                          against Rook::Crs::NationalGpraReport — the live
#                          driver in parity_steps.rb.
#   DRIVER=crs             will seed the SAME scenario facts into a real
#                          RPMS twin via FileMan and run actual BGP v25.1.
#                          The twin is verified reachable, but FileMan
#                          seeding and CRS report invocation are NOT built
#                          yet — every scenario is reported PENDING with
#                          that reason. Never faked: a green DRIVER=crs run
#                          exists only when real CRS computed it.
#
# Until DRIVER=crs runs green, every parity claim is Rook-vs-BDD only,
# not Rook-vs-CRS.
CRS_DRIVER_PENDING =
  "CRS driver (#99 P2): twin reachable, but FileMan seeding and BGP " \
  "report invocation are not yet implemented — pending environment work, " \
  "not a verified CRS result"

PARITY_DRIVERS = %w[rook crs].freeze

# Unknown DRIVER values must fail loudly at load time — DRIVER=CRS or a typo
# silently running the rook driver would be Rook-vs-BDD wearing a CRS label.
if ENV["DRIVER"] && !PARITY_DRIVERS.include?(ENV["DRIVER"].strip.downcase)
  raise ArgumentError, "unknown DRIVER=#{ENV['DRIVER'].inspect}; use one of: #{PARITY_DRIVERS.join(', ')}"
end

def crs_driver? = ENV["DRIVER"].to_s.strip.downcase == "crs"

# Scoped by the @crs-v25 tag — the same predicate the evidence lint locks on
# every parity feature — not by a path substring.
Before("@crs-v25") do |_scenario|
  next unless crs_driver?

  unless ParityHarness::CrsTwin.configured?
    raise ParityHarness::CrsTwin::Unavailable,
      "DRIVER=crs needs ROOK_CRS_TWIN_CMD (e.g. 'docker exec <twin-container>')"
  end

  # Prove the oracle is really there before reporting pending — a missing
  # twin is a failure, not a quiet pending.
  twin = ParityHarness::CrsTwin.from_env
  kernel_now = twin.probe("$$NOW^XLFDT").first.to_f
  raise ParityHarness::CrsTwin::Unavailable, "twin kernel not responding" unless kernel_now > 3_000_000

  pending(CRS_DRIVER_PENDING)
end
