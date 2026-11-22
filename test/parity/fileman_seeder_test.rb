# frozen_string_literal: true

require "test_helper"
require "date"
require_relative "../../features/parity/support/crs_twin"
require_relative "../../features/parity/support/fileman_seeder"

# The parity seeder drives stock FileMan, Kernel and BGP entry points only.
# It installs no M routine on the twin: Lakeraven authors no M, so nothing
# here may write a routine, and every M call names an entry point from
# STOCK_ENTRY_POINTS. These tests run without a twin; the live round trip
# stays in crs_twin_smoke_test.rb.
class FilemanSeederTest < Minitest::Test
  # Records the direct-mode M the seeder sends and answers from a script.
  class FakeTwin
    attr_reader :inputs

    def initialize(responses = {})
      @responses = responses
      @inputs = []
    end

    def run_direct(m_input, allow_errors: false)
      @inputs << m_input
      key = @responses.keys.find { |pattern| m_input.match?(pattern) }
      Array(key ? @responses[key] : "OK^1")
    end
  end

  def seeder(twin = FakeTwin.new)
    ParityHarness::FilemanSeeder.new(twin)
  end

  def test_no_routine_ships_with_the_harness
    refute File.exist?(File.expand_path("../../features/parity/support/m/ROOKSEED.m", __dir__)),
      "ROOKSEED.m must be gone: the harness authors no M"
    refute ParityHarness::CrsTwin.method_defined?(:install_routine),
      "the twin client must not be able to install a routine"
  end

  def test_every_call_uses_only_stock_entry_points
    twin = FakeTwin.new
    s = seeder(twin)
    dfn = s.seed_patient(id: "T1", sex: "F", dob: Date.new(1975, 7, 1), community: "EXAMPLE TOWN")
    visit = s.seed_visit(dfn: dfn, date: Date.new(2025, 6, 10))
    s.seed_pov(visit_ien: visit, dfn: dfn, icd_code: "E11.9")
    s.seed_problem(dfn: dfn, icd_code: "E11.9", onset: Date.new(2018, 6, 15))
    s.problem_list_hit?(dfn: dfn, taxonomy: "SURVEILLANCE DIABETES",
      from: Date.new(2018, 1, 1), to: Date.new(2018, 12, 31))
    s.show(dfn)

    allowed = ParityHarness::FilemanSeeder::STOCK_ENTRY_POINTS
    called = twin.inputs.flat_map { |m| m.scan(/\$?\$?[A-Z%][A-Z0-9]*\^[A-Z%][A-Z0-9]*/) }.uniq

    refute_empty called
    assert_empty called - allowed, "non-stock entry points called: #{(called - allowed).inspect}"
    refute twin.inputs.any? { |m| m.include?("ROOKSEED") }
  end

  def test_writes_go_through_update_die_with_the_seeded_fields
    twin = FakeTwin.new
    seeder(twin).seed_patient(id: "T2", sex: "M", dob: Date.new(1970, 7, 1))

    file2 = twin.inputs.find { |m| m.include?("FDA(2,") }

    assert_includes file2, %(FDA(2,"+1,",.01)="ZZROOKPARITY,T2")
    assert_includes file2, %(FDA(2,"+1,",.03)=2700701)
    assert_includes file2, "UPDATE^DIE("
  end

  def test_a_fileman_rejection_raises_with_its_text
    twin = FakeTwin.new(/FDA\(2,/ => "ERR^file2: The value is not valid")

    error = assert_raises(ParityHarness::FilemanSeeder::SeedRejected) do
      seeder(twin).seed_patient(id: "T3", sex: "X", dob: Date.new(1970, 1, 1))
    end
    assert_match(/not valid/, error.message)
  end

  def test_an_empty_answer_is_a_rejection_not_a_seed
    twin = FakeTwin.new(/FDA\(2,/ => [])

    assert_raises(ParityHarness::FilemanSeeder::SeedRejected) do
      seeder(twin).seed_patient(id: "T4", sex: "F", dob: Date.new(1970, 1, 1))
    end
  end

  def test_problem_numbers_count_up_per_patient
    twin = FakeTwin.new
    s = seeder(twin)
    s.seed_problem(dfn: 7, icd_code: "E11.9")
    s.seed_problem(dfn: 7, icd_code: "I10")
    s.seed_problem(dfn: 8, icd_code: "I10")

    numbers = twin.inputs.grep(/FDA\(9000011,/).map { |m| m[/FDA\(9000011,"\+1,",\.07\)=(\d+)/, 1].to_i }

    assert_equal [ 1, 2, 1 ], numbers
  end

  def test_problem_list_hit_reads_the_bgp_answer
    twin = FakeTwin.new(/PLTAXNDR/ => "OK^1")

    assert seeder(twin).problem_list_hit?(dfn: 7, taxonomy: "SURVEILLANCE DIABETES",
      from: Date.new(2018, 1, 1), to: Date.new(2018, 12, 31))
  end
end
