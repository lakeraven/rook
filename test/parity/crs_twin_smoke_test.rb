# frozen_string_literal: true

require "test_helper"
require_relative "../../features/parity/support/crs_twin"

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

  def test_bgp_taxonomies_are_loaded
    flags = twin.probe(
      '$D(^ATXAX("B","SURVEILLANCE DIABETES"))_" "_' \
      '$D(^ATXAX("B","BGP HGBA1C LOINC CODES"))_" "_' \
      '$D(^ATXLAB("B","DM AUDIT HGB A1C TAX"))'
    ).first.to_s

    assert_equal "10 10 10", flags, "BGP national + site lab taxonomies must be populated"
  end
end
