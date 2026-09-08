# frozen_string_literal: true

require_relative "crs_twin"

module ParityHarness
  # Seeds canonical RPMS records into the CRS twin through the FileMan API
  # (#99 P2): installs ROOKSEED.m (features/parity/support/m/) and drives its
  # entry points. Every write goes through UPDATE^DIE inside the twin — input
  # transforms and cross-references fire, so BGP sees real PCC data.
  #
  # Values cross in FileMan INTERNAL format; this class owns the conversion
  # (dates → 3YYMMDD). A seeded fact that FileMan rejects raises with the
  # DIERR text — a rejected seed must never look planted.
  class FilemanSeeder
    ROUTINE = File.read(File.expand_path("m/ROOKSEED.m", __dir__))

    class SeedRejected < StandardError; end

    def initialize(twin)
      @twin = twin
      @installed = false
    end

    # @return [Integer] DFN of the created patient
    def seed_patient(id:, sex:, dob:, beneficiary: "01", community: nil)
      call("PT", m_str(id), m_str(sex), fm_date(dob), m_str(beneficiary), m_str(community.to_s))
    end

    # @return [Integer] visit IEN. service_category: "A" ambulatory, "H"
    # hospitalization, ... (VISIT .07 set); clinic: RPMS clinic code.
    def seed_visit(dfn:, date:, service_category: "A", clinic: "01")
      call("VST", dfn, fm_datetime(date), m_str(service_category), m_str(clinic.to_s))
    end

    # @return [Integer] V POV IEN
    def seed_pov(visit_ien:, dfn:, icd_code:)
      call("POV", visit_ien, dfn, m_str(icd_code))
    end

    # status: "A" active / "I" inactive. onset/entered nil = omit.
    # @return [Integer] problem IEN
    def seed_problem(dfn:, icd_code:, status: "A", onset: nil, entered: nil)
      call("PRB", dfn, m_str(icd_code), m_str(status),
        onset ? fm_date(onset) : m_str(""), entered ? fm_date(entered) : m_str(""))
    end

    # Runs the REAL BGP building block $$PLTAXNDR^BGPXDU against a seeded
    # patient — live micro-parity between the M oracle and the rule
    # Rook::Crs encodes from it (Problem List: onset governs, else entered).
    def problem_list_hit?(dfn:, taxonomy:, from:, to:, skip_inactive: false)
      call("PLTAX", dfn, m_str(taxonomy), fm_date(from), fm_date(to), skip_inactive ? 1 : 0) == 1
    end

    # Read-back line: "LAST,FIRST^SEX^DOB|BEN=..|VISITS=n"
    def show(dfn)
      ensure_installed
      @twin.run_entry("SHOW^ROOKSEED(#{dfn})").last
    end

    # FileMan internal date: (year-1700)*10000 + month*100 + day.
    def fm_date(date)
      ((date.year - 1700) * 10_000) + (date.month * 100) + date.day
    end

    # Visit .01 wants a date & time; noon keeps it unambiguous.
    def fm_datetime(date)
      "#{fm_date(date)}.12"
    end

    private

    def call(entry, *args)
      ensure_installed
      line = @twin.run_entry("#{entry}^ROOKSEED(#{args.join(',')})").last.to_s
      status, detail = line.split("^", 2)
      raise SeedRejected, "#{entry}: #{line.empty? ? 'no response' : line}" unless status == "OK"

      Integer(detail)
    end

    def ensure_installed
      return if @installed

      @twin.install_routine("ROOKSEED", ROUTINE)
      @installed = true
      # Blank-slate twins ship without the standard BENEFICIARY reference
      # rows; ensure the canonical AI/AN row (code 01) exists — environment
      # setup through FileMan, documented, never a silent global poke.
      call("ENSBEN", m_str("01"), m_str("INDIAN/ALASKA NATIVE"))
    end

    def m_str(text)
      raise ArgumentError, "M string cannot contain quotes: #{text.inspect}" if text.include?('"')

      %("#{text}")
    end
  end
end
