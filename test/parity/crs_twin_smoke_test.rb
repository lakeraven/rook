# frozen_string_literal: true

require "test_helper"
require "date"
require_relative "../../features/parity/support/crs_twin"
require_relative "../../features/parity/support/fileman_seeder"

# Environment gate for the #99 CRS driver: proves the parity oracle — a
# license-free YottaDB RPMS twin with the pinned BGP build — is genuinely
# reachable and carries what the driver needs. Skips (loudly) without
# ROOK_CRS_TWIN_CMD; runs REAL M when configured. This is what makes the
# DRIVER=crs pending state honest: the environment is verified, only the
# seeding/report layers are outstanding.
class CrsTwinSmokeTest < Minitest::Test
  def twin
    @twin ||= ParityHarness::CrsTwin.from_env
  end

  def setup
    skip "set ROOK_CRS_TWIN_CMD to run the CRS twin smoke" unless ParityHarness::CrsTwin.configured?
  end

  def test_kernel_is_alive
    now = twin.probe("$$NOW^XLFDT").first.to_f

    assert_operator now, :>, 3_000_000, "kernel $$NOW^XLFDT should return a FileMan date-time"
  end

  def test_crs_measure_code_links
    header = twin.probe('$P($T(+1^BGPXD2),";",2,3)').first.to_s

    assert_match(/measure/, header, "BGPXD2 (CRS 2025 diabetes measures) must link and identify itself")
  end

  def test_fileman_clinical_globals_exist
    flags = twin.probe('$D(^DPT)_" "_$D(^AUPNPAT)_" "_$D(^AUPNVSIT)_" "_$D(^BGPSITE)').first.to_s

    assert_equal "10 10 10 10", flags,
      "registration (^DPT/^AUPNPAT), visit (^AUPNVSIT), and CRS site (^BGPSITE) globals must exist"
  end

  def seeder
    @seeder ||= ParityHarness::FilemanSeeder.new(twin)
  end

  def unique_id
    "SMK#{Time.now.strftime('%H%M%S')}#{rand(100)}"
  end

  def test_fileman_seeding_round_trip
    dfn = seeder.seed_patient(id: unique_id, sex: "F", dob: Date.new(1975, 7, 1))
    visit = seeder.seed_visit(dfn: dfn, date: Date.new(2025, 6, 10))
    seeder.seed_pov(visit_ien: visit, dfn: dfn, icd_code: "E11.9")

    readback = seeder.show(dfn)

    assert_match(/BEN=01/, readback, "beneficiary must read back through $$BEN^AUPNPAT")
    assert_match(/VISITS=1/, readback, "visit must land on the patient's AC cross-reference")
  end

  # First live agreement check between the M oracle and a rule Rook::Crs
  # encoded from it: the Problem List date rule (onset governs when present
  # — PLTAXNDR^BGPXDU). The real routine runs against a seeded entry.
  def test_micro_parity_problem_list_onset_governs
    dfn = seeder.seed_patient(id: unique_id, sex: "M", dob: Date.new(1970, 7, 1))
    seeder.seed_problem(dfn: dfn, icd_code: "E11.9", status: "A", onset: Date.new(2018, 6, 15))

    in_2018 = seeder.problem_list_hit?(dfn: dfn, taxonomy: "SURVEILLANCE DIABETES",
      from: Date.new(2018, 1, 1), to: Date.new(2018, 12, 31))
    in_2025 = seeder.problem_list_hit?(dfn: dfn, taxonomy: "SURVEILLANCE DIABETES",
      from: Date.new(2025, 1, 1), to: Date.new(2025, 12, 31))

    assert in_2018, "onset 2018 must hit a 2018 window (onset governs)"
    refute in_2025, "onset 2018 must MISS a 2025 window even though the entry was entered today — "                     "real BGP agrees with the onset-governs rule Rook::Crs encodes"
  end

  def test_bgp_taxonomies_are_loaded
    flags = twin.probe(
      '$D(^ATXAX("B","SURVEILLANCE DIABETES"))_" "_' \
      '$D(^ATXAX("B","BGP HGBA1C LOINC CODES"))_" "_' \
      '$D(^ATXLAB("B","DM AUDIT HGB A1C TAX"))'
    ).first.to_s

    assert_equal "10 10 10", flags, "BGP national + site lab taxonomies must be populated"
  end
end
