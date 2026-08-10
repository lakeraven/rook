# frozen_string_literal: true

require "rook/care_cascade/small_cell_suppressor"

module Rook
  module CareCascade
    # Computed screening-to-treatment cascade for one condition over a cohort.
    #
    # Holds the stage funnel (cumulative counts), per-stage conversion rates,
    # and drop-off worklists (patient ids that stalled at an actionable stage),
    # plus the same figures disaggregated by site and by AI/AN status.
    #
    # A patient is credited with reaching a stage if that stage's matcher — or
    # any later stage's matcher — is satisfied (a recorded treatment implies the
    # patient got past screening even when an interim result is missing). The
    # highest satisfied stage is the patient's "reached" stage; stalling there
    # (when the stage is actionable) puts the patient on that stage's worklist.
    #
    # === PHI boundary
    # Worklists carry patient ids (they feed outreach re-engagement) and are PHI.
    # +to_grant_report+ emits aggregate counts and rates only — no ids — for
    # onward submission.
    class Report
      # Minimum cell size for grant-output small-cell suppression (HHS/CMS
      # standard). See #to_grant_report.
      DEFAULT_MIN_CELL_SIZE = 11
      # Sentinel written in place of a redacted small cell (never the number).
      SUPPRESSED = SmallCellSuppressor::SUPPRESSED

      attr_reader :definition, :classifications

      # Classify a cohort of PatientRecords against a definition's matchers.
      def self.compute(definition:, patient_records:)
        classifications = patient_records.map do |pr|
          satisfied = definition.satisfied_stages(pr)
          reached = highest_reached(definition, satisfied)
          {
            patient_id: pr.patient_id,
            site: pr.site,
            ai_an: pr.ai_an,
            satisfied: satisfied,
            reached_ordinal: reached&.ordinal,
            reached_key: reached&.key
          }
        end
        new(definition: definition, classifications: classifications)
      end

      def self.highest_reached(definition, satisfied)
        reached = definition.stages.select { |s| satisfied[s.key] }
        reached.max_by(&:ordinal)
      end

      def initialize(definition:, classifications:)
        @definition = definition
        @classifications = classifications
      end

      def condition_key
        definition.key
      end

      def condition_name
        definition.name
      end

      def stage_keys
        definition.stage_keys
      end

      def total
        classifications.size
      end

      # Cumulative funnel: how many patients reached at least each stage.
      def counts
        definition.stages.each_with_object({}) do |stage, acc|
          acc[stage.key] = classifications.count do |c|
            c[:reached_ordinal] && c[:reached_ordinal] >= stage.ordinal
          end
        end
      end

      # How many patients stalled exactly at each stage (went no further).
      def reached_exactly_counts
        definition.stages.each_with_object({}) do |stage, acc|
          acc[stage.key] = classifications.count { |c| c[:reached_key] == stage.key }
        end
      end

      # Consecutive-stage conversion rates, e.g.
      #   { "screened_to_reactive" => 0.6, ... }
      # nil when the upstream stage has zero patients (undefined, not zero).
      def conversions
        c = counts
        definition.stages.each_cons(2).each_with_object({}) do |(from, to), acc|
          denom = c[from.key]
          acc["#{from.key}_to_#{to.key}"] = denom.zero? ? nil : (c[to.key].to_f / denom).round(4)
        end
      end

      # Patient ids that stalled exactly at +stage_key+.
      def drop_off(stage_key)
        classifications.select { |c| c[:reached_key] == stage_key }.map { |c| c[:patient_id] }
      end

      # Drop-off worklists for actionable stages only — the re-engagement
      # queues that feed outreach. { stage_key => { count:, patient_ids: [] } }.
      def worklists
        definition.stages.select(&:actionable?).each_with_object({}) do |stage, acc|
          ids = drop_off(stage.key)
          acc[stage.key] = { count: ids.size, patient_ids: ids }
        end
      end

      # Disaggregations. Each returns { subgroup_value => Report }.
      def by_site
        subreports { |c| c[:site] }
      end

      def by_ai_an
        subreports { |c| ai_an_label(c[:ai_an]) }
      end

      def by_site_and_ai_an
        subreports { |c| [ c[:site], ai_an_label(c[:ai_an]) ] }
      end

      # Internal/PHI aggregate: EXACT counts and rates, no patient ids and NO
      # small-cell suppression. This is NOT a shareable surface — it feeds #to_h
      # (the PHI outreach report) and builds the disaggregation sub-reports. The
      # ONLY funder-facing / shareable surface is #to_grant_report, which applies
      # complementary small-cell suppression. Do not emit summary_h externally.
      def summary_h
        {
          condition: { key: condition_key, name: condition_name },
          total: total,
          stages: definition.stages.map(&:to_h),
          counts: counts,
          reached_exactly: reached_exactly_counts,
          conversions: conversions,
          worklist_counts: worklists.transform_values { |w| w[:count] }
        }
      end

      # Full report including patient-id worklists and disaggregations. PHI.
      def to_h
        summary_h.merge(
          worklists: worklists,
          by_site: by_site.transform_values(&:summary_h),
          by_ai_an: by_ai_an.transform_values(&:summary_h),
          by_site_and_ai_an: by_site_and_ai_an.transform_values(&:summary_h)
        )
      end

      # Submission-shaped outcomes output for grant reporting (RWJF / ARPA-H /
      # RHTP). Aggregate counts and conversion rates, disaggregated by site and
      # AI/AN status. No patient-level data.
      #
      # === Complementary small-cell suppression (PHI re-identification safeguard, rook#51)
      # Bare counts can re-identify people in a small street-medicine cohort: a
      # cell like {site, AI/AN, treatment_completed: 1} names an individual with
      # no id present. Every count below +min_cell_size+ (default 11, the HHS/CMS
      # standard) is redacted to +:suppressed+ — the sentinel, NOT the number —
      # and then COMPLEMENTARY suppression closes margin arithmetic: whenever a
      # row/column/whole-cohort total or the telescoping cascade<->drop_off
      # identity would leave a single suppressed cell recoverable by subtraction,
      # the next-smallest cell in that relation is suppressed too (iterated to a
      # fixpoint). No suppressed count is recoverable by single-equation
      # subtraction across any margin or the by_site_and_ai_an cross-tab. A
      # conversion rate is suppressed whenever either endpoint count is
      # suppressed.
      #
      # This closes single-equation recovery; it is a SAFEGUARD, not a
      # de-identification certification (a determined adversary combining many
      # equations is out of scope here). Tribal-data release still requires
      # Expert Determination per Lakeraven policy; Safe Harbor / bare counts are
      # insufficient. See SmallCellSuppressor for the algorithm and trade-offs.
      def to_grant_report(period: nil, program: nil, min_cell_size: DEFAULT_MIN_CELL_SIZE)
        body = raw_grant_body
        SmallCellSuppressor.new(min_cell_size).suppress!(body, stage_keys: definition.stage_keys)
        {
          program: program,
          condition: { key: condition_key, name: condition_name },
          reporting_period: period,
          min_cell_size: min_cell_size
        }.merge(body)
      end

      # A single raw disaggregation slice (counts and rates, no ids). Public so a
      # parent report can build slices from its sub-reports; suppression is
      # applied centrally by SmallCellSuppressor over the assembled report.
      def grant_slice
        { cohort_size: total, cascade: counts, conversion_rates: conversions }
      end

      private

      # Assembled but UNSUPPRESSED grant structure — SmallCellSuppressor mutates
      # it in place so complementary suppression can see every margin at once.
      def raw_grant_body
        {
          cohort_size: total,
          cascade: counts,
          drop_off: reached_exactly_counts,
          conversion_rates: conversions,
          disaggregation: {
            by_site: by_site.transform_values(&:grant_slice),
            by_ai_an: by_ai_an.transform_values(&:grant_slice),
            by_site_and_ai_an: by_site_and_ai_an.transform_values(&:grant_slice)
          }
        }
      end

      # AI/AN status is tri-state: missing/unknown is preserved as its own
      # category rather than collapsed into "non-AI/AN" (which would bias grant
      # disaggregation).
      def ai_an_label(value)
        case value
        when true then "AI/AN"
        when false then "non-AI/AN"
        else "unknown"
        end
      end

      def subreports
        classifications.group_by { |c| yield(c) }.transform_values do |group|
          Report.new(definition: definition, classifications: group)
        end
      end
    end
  end
end
