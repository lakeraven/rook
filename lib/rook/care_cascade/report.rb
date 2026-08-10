# frozen_string_literal: true

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
        subreports { |c| c[:ai_an] ? "AI/AN" : "non-AI/AN" }
      end

      def by_site_and_ai_an
        subreports { |c| [ c[:site], c[:ai_an] ? "AI/AN" : "non-AI/AN" ] }
      end

      # Aggregate figures only (no patient ids) — safe for dashboards/summary.
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
          by_ai_an: by_ai_an.transform_values(&:summary_h)
        )
      end

      # Submission-shaped outcomes output for grant reporting (RWJF / ARPA-H /
      # RHTP). Aggregate counts and conversion rates, disaggregated by site and
      # AI/AN status. No patient-level data.
      def to_grant_report(period: nil, program: nil)
        {
          program: program,
          condition: { key: condition_key, name: condition_name },
          reporting_period: period,
          cohort_size: total,
          cascade: counts,
          drop_off: reached_exactly_counts,
          conversion_rates: conversions,
          disaggregation: {
            by_site: by_site.transform_values { |r| grant_slice(r) },
            by_ai_an: by_ai_an.transform_values { |r| grant_slice(r) }
          }
        }
      end

      private

      def grant_slice(report)
        {
          cohort_size: report.total,
          cascade: report.counts,
          conversion_rates: report.conversions
        }
      end

      def subreports
        classifications.group_by { |c| yield(c) }.transform_values do |group|
          Report.new(definition: definition, classifications: group)
        end
      end
    end
  end
end
