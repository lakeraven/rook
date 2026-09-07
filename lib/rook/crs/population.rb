# frozen_string_literal: true

require "date"

require "rook/crs/terminology"

module Rook
  module Crs
    # Builds CRS-faithful patient records from ingest-seam FHIR resources
    # (hashes, per docs/measures/fhir-mapping.md) and answers the population
    # questions the CRS v25 measures ask. Semantics carry dossier citations
    # (docs/measures/); anything spec-silent is flagged there, not decided
    # silently here.
    class Population
      def initialize(resources)
        @records = build_records(resources)
      end

      def patients
        @records.values
      end

      def record(patient_id)
        @records.fetch(patient_id.to_s)
      end

      private

      def build_records(resources)
        by_type = resources.group_by { |r| r["resourceType"] }
        records = (by_type["Patient"] || []).to_h do |p|
          [ p.fetch("id").to_s, PatientRecord.new(p) ]
        end
        {
          "Encounter" => :add_encounter, "Condition" => :add_condition,
          "Observation" => :add_observation, "Procedure" => :add_procedure
        }.each do |type, adder|
          (by_type[type] || []).each do |resource|
            id = subject_id(resource)
            records[id]&.public_send(adder, resource)
          end
        end
        records
      end

      def subject_id(resource)
        (resource.dig("subject", "reference") || resource.dig("beneficiary", "reference"))
          .to_s.split("/").last.to_s
      end
    end

    # One patient's CRS-relevant facts plus the derived population/measure
    # predicates. Date handling: FHIR date/dateTime strings compared as Date.
    class PatientRecord
      attr_reader :id, :encounters, :conditions, :observations, :procedures

      def initialize(patient)
        @patient = patient
        @id = patient.fetch("id").to_s
        @encounters = []
        @conditions = []
        @observations = []
        @procedures = []
      end

      def add_encounter(r) = @encounters << r
      def add_condition(r) = @conditions << r
      def add_observation(r) = @observations << r
      def add_procedure(r) = @procedures << r

      # -- Registration facts -------------------------------------------------

      def birth_date
        Date.parse(@patient.fetch("birthDate"))
      end

      # Age as of +date+ (CRS: age computed as of the end of the Report
      # Period — §2.6.2.5 "Age").
      def age_on(date)
        years = date.year - birth_date.year
        years -= 1 if date < birth_date.next_year(years)
        years
      end

      # Alive on the last day of the Report Period (populations.md).
      def alive_on?(date)
        deceased = @patient["deceasedDateTime"]
        return false if @patient["deceasedBoolean"] == true
        deceased.nil? || Date.parse(deceased) > date
      end

      def beneficiary_class
        ext(Terminology::IHS_BENEFICIARY_EXT)&.dig("valueCode")
      end

      def gpra_community?
        ext(Terminology::GPRA_COMMUNITY_EXT)&.dig("valueBoolean") == true
      end

      # -- Population bases (populations.md; spec §1.2.2–1.2.3) --------------

      # User Population (National GPRA): seen at least once in the three
      # years prior to period end via an ambulatory / hospitalization /
      # telemedicine visit; alive at period end; AI/AN (Beneficiary 01);
      # GPRA community residency.
      def user_population?(period)
        window = (period.end << 36)..period.end
        qualifying = encounters.any? do |e|
          klass = e.dig("class", "code")
          date = encounter_date(e)
          %w[AMB IMP VR].include?(klass) && date && window.cover?(date)
        end
        qualifying && alive_on?(period.end) && beneficiary_class == "01" && gpra_community?
      end

      # -- Visits -------------------------------------------------------------

      def ambulatory_visit_dates
        encounters.filter_map { |e| encounter_date(e) if e.dig("class", "code") == "AMB" }
      end

      def visits_during(period)
        ambulatory_visit_dates.count { |d| period.cover?(d) }
      end

      # -- Diagnosis facts ----------------------------------------------------

      def povs
        conditions.select { |c| condition_category(c) == "encounter-diagnosis" }
      end

      def problem_list
        conditions.select { |c| condition_category(c) == "problem-list-item" }
      end

      # First DM POV or Problem List entry date (§2.1.2.5: "First DM Purpose
      # of Visit recorded in the V POV file or Problem List Entry where the
      # status is not Deleted with Date of Onset or Date Entered prior to the
      # Report Period"). Deleted PL entries are absent by mapping; Inactive
      # DM PL entries still count (the DM rule excludes only Deleted).
      def first_diabetes_evidence_date
        dates = povs.select { |c| coded?(c, :diabetes_code?) }.filter_map { |c| condition_date(c) }
        dates += problem_list.select { |c| coded?(c, :diabetes_code?) }.filter_map { |c| condition_date(c) }
        dates.min
      end

      def diabetes_problem_list_entry?
        problem_list.any? { |c| coded?(c, :diabetes_code?) }
      end

      # Distinct dates of visits carrying a DM POV, ever ("two DM-related
      # visits ever", §2.1.2.3).
      def diabetes_pov_visit_dates
        povs.select { |c| coded?(c, :diabetes_code?) }.filter_map { |c| condition_date(c) }.uniq
      end

      # Hypertension diagnosis within the window (period + year prior):
      # POV, or Problem List entry with clinicalStatus not inactive
      # (§2.6.2.5 — "status is not Inactive or Deleted").
      def hypertension_dx_in?(window)
        pov_hit = povs.any? do |c|
          coded?(c, :hypertension_code?) && (d = condition_date(c)) && window.cover?(d)
        end
        pl_hit = problem_list.any? do |c|
          coded?(c, :hypertension_code?) &&
            c.dig("clinicalStatus", "coding", 0, "code") != "inactive" &&
            (d = condition_date(c)) && window.cover?(d)
        end
        pov_hit || pl_hit
      end

      # ESRD ever (§2.6.2.5) — trio scope: diagnosis set; CPT/procedure ESRD
      # evidence arrives with the full taxonomy (#83).
      def esrd_ever?
        conditions.any? { |c| coded?(c, :esrd_code?) }
      end

      def currently_pregnant_during?(period)
        observations.any? do |o|
          obs_code(o) == [ Terminology::LOINC, Terminology::PREGNANCY_STATUS_LOINC ] &&
            value_coding(o) == [ Terminology::SNOMED, Terminology::PREGNANT_SNOMED ] &&
            (d = obs_date(o)) && period.cover?(d)
        end
      end

      # -- A1c selection (§2.1.2.5; M-verified HGBA1C^BGPXD2) -----------------

      # Most recent RESULTED A1c candidate in the period, across lab results
      # (ordered by result date-time, falling back to visit date-time) and
      # CPT band evidence. Unresulted tests are skipped in selection (they
      # only mark "documented"), which yields same-day resulted-beats-
      # unresulted. Returns nil when no resulted candidate exists.
      A1cCandidate = Struct.new(:date, :value, :cpt, keyword_init: true)

      def latest_a1c(period)
        a1c_candidates(period).select { |c| c.value || c.cpt }.max_by(&:date)
      end

      # Any A1c evidence in the period, resulted or not ("documented").
      def a1c_documented?(period)
        !a1c_candidates(period).empty?
      end

      # -- Blood pressure (§2.6.2.5) ------------------------------------------

      # Readings on the LAST date with a BP documented in the period; the
      # same-day rule ("first look for a blood pressure less than 140/90 on
      # that day") is applied by the measure over this set.
      def last_day_bps(period)
        readings = observations.filter_map do |o|
          next unless obs_code(o) == [ Terminology::LOINC, "85354-9" ]
          date = obs_date(o)
          next unless date && period.cover?(date)
          systolic = component_value(o, "8480-6")
          diastolic = component_value(o, "8462-4")
          { date: date, systolic: systolic, diastolic: diastolic }
        end
        last = readings.map { |r| r[:date] }.max
        readings.select { |r| r[:date] == last }
      end

      # -- Depression screening evidence (§2.5.4.5) ---------------------------

      def depression_screened?(period)
        screened_by_measurement?(period) || screened_by_bh_exam?(period) ||
          screened_by_pov?(period) || screened_by_cpt?(period) ||
          screened_by_bhs_problem?(period)
      end

      # Mood disorder: at least two visits during the period with a mood
      # disorder POV (distinct visit dates).
      def mood_disorder_visits(period)
        povs.select { |c| coded?(c, :mood_disorder_code?) }
            .filter_map { |c| condition_date(c) }
            .select { |d| period.cover?(d) }
            .uniq.size
      end

      private

      def screened_by_measurement?(period)
        observations.any? do |o|
          system, code = obs_code(o)
          Terminology.depression_measurement?(system, code) &&
            (d = obs_date(o)) && period.cover?(d)
        end
      end

      # BH exam 36 counts only with result P or N — refusals (R) excluded
      # (M-verified: ^AMHREC result check in BGPXD25/BGPXPC11).
      def screened_by_bh_exam?(period)
        observations.any? do |o|
          obs_code(o) == [ Terminology::BH_EXAM_SYSTEM, "36" ] &&
            %w[P N].include?(value_coding(o)&.last) &&
            (d = obs_date(o)) && period.cover?(d)
        end
      end

      def screened_by_pov?(period)
        povs.any? do |c|
          coded?(c, :depression_screen_pov?) && (d = condition_date(c)) && period.cover?(d)
        end
      end

      def screened_by_cpt?(period)
        procedures.any? do |p|
          Terminology::DEPRESSION_SCREEN_CPTS.include?(p.dig("code", "coding", 0, "code")) &&
            (d = parse_date(p["performedDateTime"])) && period.cover?(d)
        end
      end

      def screened_by_bhs_problem?(period)
        observations.any? do |o|
          obs_code(o) == [ Terminology::BHS_PROBLEM_SYSTEM, "14.1" ] &&
            (d = obs_date(o)) && period.cover?(d)
        end
      end

      def a1c_candidates(period)
        labs = observations.filter_map do |o|
          system, code = obs_code(o)
          next unless Terminology.a1c_lab_code?(system, code)
          date = parse_date(o["issued"]) || obs_date(o)
          next unless date && period.cover?(date)
          A1cCandidate.new(date: date, value: o.dig("valueQuantity", "value"), cpt: nil)
        end
        cpts = procedures.filter_map do |p|
          code = p.dig("code", "coding", 0, "code")
          next unless Terminology::A1C_CPTS.include?(code)
          date = parse_date(p["performedDateTime"])
          next unless date && period.cover?(date)
          A1cCandidate.new(date: date, value: nil, cpt: code)
        end
        labs + cpts
      end

      def ext(url)
        Array(@patient["extension"]).find { |e| e["url"] == url }
      end

      def coded?(condition, predicate)
        Array(condition.dig("code", "coding")).any? do |coding|
          Terminology.public_send(predicate, coding["system"], coding["code"])
        end
      end

      def condition_category(condition)
        condition.dig("category", 0, "coding", 0, "code")
      end

      def condition_date(condition)
        parse_date(condition["recordedDate"] || condition["onsetDateTime"])
      end

      def encounter_date(encounter)
        parse_date(encounter.dig("period", "start"))
      end

      def obs_code(observation)
        coding = observation.dig("code", "coding", 0)
        [ coding&.dig("system"), coding&.dig("code") ]
      end

      def value_coding(observation)
        coding = observation.dig("valueCodeableConcept", "coding", 0)
        coding && [ coding["system"], coding["code"] ]
      end

      def obs_date(observation)
        parse_date(observation["effectiveDateTime"])
      end

      def component_value(observation, loinc)
        Array(observation["component"]).each do |comp|
          next unless Array(comp.dig("code", "coding")).any? { |c| c["code"] == loinc }
          return comp.dig("valueQuantity", "value")
        end
        nil
      end

      # Fail closed on unparseable dates (same rule as the supplemental
      # port): a bad date must not silently become "undated".
      def parse_date(value)
        return nil if value.nil? || value.to_s.empty?

        Date.parse(value.to_s)
      rescue ArgumentError
        raise ArgumentError, "unparseable date on patient #{id}: #{value.inspect}"
      end
    end
  end
end
