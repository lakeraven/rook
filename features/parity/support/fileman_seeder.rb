# frozen_string_literal: true

require_relative "crs_twin"

module ParityHarness
  # Seeds canonical RPMS records into the CRS twin (#99 P2) by driving stock
  # FileMan, Kernel and BGP entry points in direct mode. It installs no M
  # routine: Lakeraven authors no M, so the harness only fills FileMan's FDA
  # arrays and calls documented entry points (STOCK_ENTRY_POINTS). Every
  # write goes through UPDATE^DIE or FILE^DIE inside the twin, so input
  # transforms and cross-references fire and BGP sees real PCC data.
  #
  # Values cross in FileMan INTERNAL format; this class owns the conversion
  # (dates → 3YYMMDD). A seeded fact that FileMan rejects raises with the
  # DIERR text — a rejected seed must never look planted.
  class FilemanSeeder
    class SeedRejected < StandardError; end

    # The only M entry points the harness may call. Each is a stock FileMan,
    # Kernel, ICD or BGP API shipped with RPMS.
    STOCK_ENTRY_POINTS = %w[
      UPDATE^DIE FILE^DIE $$FIND1^DIC LIST^DIC FIND^DIC $$GET1^DIQ
      $$ICDDX^ICDEX $$BEN^AUPNPAT $$PLTAXNDR^BGPXDU
    ].freeze

    PATIENT_PREFIX = "ZZROOKPARITY,"
    NARRATIVE = "ROOK PARITY SEED"

    # Kernel context any background job carries: V-file cross-references
    # read DUZ and DUZ("AG"), and direct mode has no sign-on. DUZ(2) is the
    # first LOCATION entry in internal-number order.
    CONTEXT = [
      %(S U="^" S:'$D(DUZ) DUZ=1 S:'$D(DUZ(0)) DUZ(0)="@" S:$G(DUZ("AG"))="" DUZ("AG")="I"),
      %(D LIST^DIC(9999999.06,"","@","",1,"","","#","","","RKLOC") S RKLOC=+$G(RKLOC("DILIST",2,1)) S:'$G(DUZ(2)) DUZ(2)=RKLOC)
    ].freeze

    def initialize(twin)
      @twin = twin
      @problem_numbers = Hash.new(0)
      @beneficiary_ensured = false
    end

    # @return [Integer] DFN of the created patient
    def seed_patient(id:, sex:, dob:, beneficiary: "01", community: nil)
      ensure_beneficiary
      lines = [ %(S RKB=$$FIND1^DIC(9999999.25,"","X",#{m_str(beneficiary)},"C")),
                %(I 'RKB W "ERR^no beneficiary code #{beneficiary}",! Q) ]
      lines += if community.to_s.empty?
        [ %(S RKC="") ]
      else
        [ %(S RKC=$$FIND1^DIC(9999999.05,"","X",#{m_str(community.to_s)},"B")),
          %(I 'RKC W "ERR^no community #{community}",! Q) ]
      end
      # File 2 first, then the DINUMed IHS PATIENT entry, in one input: each
      # twin call is a fresh M process, so the lookups must share it.
      write(lines + [
        %(K FDA,IENA,MSG S FDA(2,"+1,",.01)=#{m_str(PATIENT_PREFIX + id)},FDA(2,"+1,",.02)=#{m_str(sex)},FDA(2,"+1,",.03)=#{fm_date(dob)}),
        %(D UPDATE^DIE("","FDA","IENA","MSG") I $D(MSG("DIERR")) W "ERR^file2: ",$G(MSG("DIERR",1,"TEXT",1)),! Q),
        %(S RKD=+$G(IENA(1)) I 'RKD W "ERR^no dfn",! Q),
        %(K FDA,IENA,MSG S IENA(1)=RKD,FDA(9000001,"+1,",.01)=RKD),
        %(S:RKB FDA(9000001,"+1,",1111)=RKB S:RKC FDA(9000001,"+1,",1118)=RKC),
        %(D UPDATE^DIE("","FDA","IENA","MSG") W $S($D(MSG("DIERR")):"ERR^file9000001: "_$G(MSG("DIERR",1,"TEXT",1)),1:"OK^"_RKD),!)
      ])
    end

    # @return [Integer] visit IEN. service_category: "A" ambulatory, "H"
    # hospitalization, ... (VISIT .07 set); clinic: RPMS clinic code.
    def seed_visit(dfn:, date:, service_category: "A", clinic: "01")
      write([
        %(I 'RKLOC W "ERR^no location on twin",! Q),
        %(S RKK=$$FIND1^DIC(40.7,"","X",#{m_str(clinic.to_s)},"C")),
        %(I 'RKK W "ERR^no clinic #{clinic}",! Q),
        %(K FDA,IENA,MSG S FDA(9000010,"+1,",.01)=#{fm_datetime(date)},FDA(9000010,"+1,",.02)=#{fm_datetime(date)},FDA(9000010,"+1,",.03)="I"),
        %(S FDA(9000010,"+1,",.05)=#{Integer(dfn)},FDA(9000010,"+1,",.06)=RKLOC,FDA(9000010,"+1,",.07)=#{m_str(service_category)},FDA(9000010,"+1,",.08)=RKK),
        update("file9000010")
      ])
    end

    # @return [Integer] V POV IEN
    def seed_pov(visit_ien:, dfn:, icd_code:)
      write(icd_and_narrative(icd_code) + [
        %(K FDA,IENA,MSG S FDA(9000010.07,"+1,",.01)=RKI,FDA(9000010.07,"+1,",.02)=#{Integer(dfn)}),
        %(S FDA(9000010.07,"+1,",.03)=#{Integer(visit_ien)},FDA(9000010.07,"+1,",.04)=RKN),
        update("vpov")
      ])
    end

    # status: "A" active / "I" inactive. onset/entered nil = omit.
    # Problem numbers count up per patient within this seeder; every seeded
    # patient is new, so the harness is the only writer of its problems.
    # @return [Integer] problem IEN
    def seed_problem(dfn:, icd_code:, status: "A", onset: nil, entered: nil)
      number = @problem_numbers[Integer(dfn)] + 1
      ien = write(icd_and_narrative(icd_code) + [
        %(K FDA,IENA,MSG S FDA(9000011,"+1,",.01)=RKI,FDA(9000011,"+1,",.02)=#{Integer(dfn)},FDA(9000011,"+1,",.05)=RKN),
        %(S FDA(9000011,"+1,",.06)=RKLOC,FDA(9000011,"+1,",.07)=#{number},FDA(9000011,"+1,",.12)=#{m_str(status)}),
        (onset ? %(S FDA(9000011,"+1,",.13)=#{fm_date(onset)}) : nil),
        (entered ? %(S FDA(9000011,"+1,",.08)=#{fm_date(entered)}) : nil),
        update("prob")
      ].compact)
      @problem_numbers[Integer(dfn)] = number
      ien
    end

    # Runs the REAL BGP building block $$PLTAXNDR^BGPXDU against a seeded
    # patient — live micro-parity between the M oracle and the rule
    # Rook::Crs encodes from it (Problem List: onset governs, else entered).
    def problem_list_hit?(dfn:, taxonomy:, from:, to:, skip_inactive: false)
      write([
        %(W "OK^",+$$PLTAXNDR^BGPXDU(#{Integer(dfn)},#{m_str(taxonomy)},#{fm_date(from)},#{fm_date(to)},#{skip_inactive ? 1 : 0}),!)
      ]) == 1
    end

    # Read-back line: "LAST,FIRST^SEX^DOB|BEN=..|VISITS=n"
    def show(dfn)
      d = Integer(dfn)
      run([
        %(K RKV D FIND^DIC(9000010,"","@","QX",#{d},"*","AC","","","RKV")),
        %(W $$GET1^DIQ(2,"#{d},",.01),U,$$GET1^DIQ(2,"#{d},",.02,"I"),U,$$GET1^DIQ(2,"#{d},",.03,"I"),"|BEN=",$$BEN^AUPNPAT(#{d},"C"),"|VISITS=",+$G(RKV("DILIST",0)),!)
      ]).last
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

    # Blank-slate twins ship without the standard BENEFICIARY reference row;
    # ensure the canonical AI/AN row (code 01) exists through FileMan, and
    # repair its name if it exists misnamed.
    def ensure_beneficiary
      return if @beneficiary_ensured

      name = m_str("INDIAN/ALASKA NATIVE")
      write([
        %(S RKB=$$FIND1^DIC(9999999.25,"","X","01","C")),
        %(I RKB K FDA,MSG S FDA(9999999.25,RKB_",",.01)=#{name} D FILE^DIE("","FDA","MSG") W $S($D(MSG("DIERR")):"ERR^benef: "_$G(MSG("DIERR",1,"TEXT",1)),1:"OK^"_RKB),! Q),
        %(K FDA,IENA,MSG S FDA(9999999.25,"+1,",.01)=#{name},FDA(9999999.25,"+1,",.02)="01"),
        update("benef")
      ])
      @beneficiary_ensured = true
    end

    # Resolves the ICD-10 entry through the stock ICD API and the harness
    # provider narrative (created through FileMan on first use).
    def icd_and_narrative(code)
      [
        %(S RKI=+$$ICDDX^ICDEX(#{m_str(code)},,,"E") S:RKI<1 RKI=0),
        %(I 'RKI W "ERR^no icd #{code}",! Q),
        %(S RKN=$$FIND1^DIC(9999999.27,"","X",#{m_str(NARRATIVE)},"B")),
        %(I 'RKN K FDA,IENA,MSG S FDA(9999999.27,"+1,",.01)=#{m_str(NARRATIVE)} D UPDATE^DIE("","FDA","IENA","MSG") S RKN=+$G(IENA(1))),
        %(I 'RKN W "ERR^no provider narrative",! Q)
      ]
    end

    # UPDATE^DIE on the current FDA, then one status line.
    def update(label)
      %(D UPDATE^DIE("","FDA","IENA","MSG") W $S($D(MSG("DIERR")):"ERR^#{label}: "_$G(MSG("DIERR",1,"TEXT",1)),+$G(IENA(1)):"OK^"_+$G(IENA(1)),1:"ERR^#{label}: no ien"),!)
    end

    # Runs the lines, takes the first status line, raises unless it is OK.
    def write(lines)
      out = run(lines)
      line = out.find { |l| l.start_with?("OK^", "ERR^") }.to_s
      status, detail = line.split("^", 2)
      raise SeedRejected, (line.empty? ? "no response" : line) unless status == "OK"

      Integer(detail)
    end

    # Direct-mode input: Kernel context, then the step. Each step line that
    # can fail ends the line with Q after writing ERR^, so a later line in
    # the same input never runs on a failed lookup's empty variable.
    def run(lines)
      @twin.run_direct(guard([ *CONTEXT, *lines ]).join("\n"))
    end

    # Direct mode runs every line regardless of an earlier Q. Prefixing each
    # step line with a flag check makes an ERR^ stop the rest.
    def guard(lines)
      [ %(K RKSTOP), *lines.map { |l| l.include?("ERR^") && l.include?(" Q") ? l.sub(/ Q\z/, " S RKSTOP=1") : l } ]
        .each_with_index.map { |l, i| i.zero? ? l : %(I '$G(RKSTOP) #{l}) }
    end

    def m_str(text)
      raise ArgumentError, "M string cannot contain quotes: #{text.inspect}" if text.include?('"')

      %("#{text}")
    end
  end
end
