# frozen_string_literal: true

module Rook
  module CareCascade
    # Complementary small-cell suppression over a grant report's count cells
    # (rook#51).
    #
    # Primary (single-cell) suppression alone is defeated by margin arithmetic:
    # a lone suppressed cell is recovered by subtracting the other, unsuppressed
    # cells from a published margin. The recoverable relations here are:
    #
    #   * row / column / whole-cohort totals of the site x AI/AN contingency
    #     table (per stage AND for cohort_size), and
    #   * the telescoping cascade<->drop_off identity
    #       cascade[i] == drop_off[i] + cascade[i+1].
    #
    # In any such additive relation, a value is exactly recoverable iff EXACTLY
    # ONE member is suppressed (all the others being published). So this walks
    # every relation and, whenever one would have a single suppressed member,
    # also suppresses the next-smallest (nonzero) member — iterating to a
    # fixpoint. At the fixpoint no relation has exactly one suppressed member, so
    # no suppressed count is recoverable by single-equation subtraction across
    # any margin or the cross-tab. Conversion rates are suppressed whenever
    # either endpoint count is suppressed (a rate + one count back-computes the
    # other).
    #
    # Full complementary suppression can over-suppress (a small cell can force
    # its large complement to be hidden too); +min_cell_size+ stays configurable
    # to trade privacy against utility. This closes single-equation recovery; it
    # is a safeguard, not a de-identification certification — tribal-data release
    # still requires Expert Determination per Lakeraven policy.
    class SmallCellSuppressor
      SUPPRESSED = :suppressed

      # One published integer cell: its value, whether suppressed, and where to
      # write the sentinel back.
      Cell = Struct.new(:value, :suppressed, :container, :key)

      def initialize(min_cell_size)
        @min = min_cell_size
        @cells = []
        @index = {}
      end

      # Mutates +body+ (the raw, unsuppressed grant structure) in place.
      def suppress!(body, stage_keys:)
        by_site  = body[:disaggregation][:by_site]
        by_ai_an = body[:disaggregation][:by_ai_an]
        cross    = body[:disaggregation][:by_site_and_ai_an]
        sites    = by_site.keys
        labels   = by_ai_an.keys

        groups = contingency_groups(body, by_site, by_ai_an, cross, sites, labels, stage_keys)
        groups.concat(telescoping_groups(body[:cascade], body[:drop_off], stage_keys))

        fixpoint(groups)
        commit
        suppress_rates!(body, stage_keys)
        body
      end

      private

      # Additive relations of the site x AI/AN table, once per measure (each
      # stage's cascade count and the cohort_size margin).
      def contingency_groups(body, by_site, by_ai_an, cross, sites, labels, stage_keys)
        groups = []
        ([ nil ] + stage_keys).each do |measure|
          top   = measure_cell(body, measure)
          rows  = sites.to_h  { |s| [ s, measure_cell(by_site[s], measure) ] }
          cols  = labels.to_h { |l| [ l, measure_cell(by_ai_an[l], measure) ] }

          sites.each do |s|
            members = labels.filter_map { |l| cross[[ s, l ]] && measure_cell(cross[[ s, l ]], measure) }
            members << rows[s]
            groups << members.compact if members.compact.size > 1
          end
          labels.each do |l|
            members = sites.filter_map { |s| cross[[ s, l ]] && measure_cell(cross[[ s, l ]], measure) }
            members << cols[l]
            groups << members.compact if members.compact.size > 1
          end

          groups << (rows.values.compact + [ top ].compact) if (rows.values.compact + [ top ].compact).size > 1
          groups << (cols.values.compact + [ top ].compact) if (cols.values.compact + [ top ].compact).size > 1
        end
        groups
      end

      # cascade[i] == drop_off[i] + cascade[i+1] (whole-cohort only; slices carry
      # no drop_off).
      def telescoping_groups(cascade, drop_off, stage_keys)
        groups = []
        stage_keys.each_cons(2) do |from, to|
          members = [ cell(cascade, from), cell(drop_off, from), cell(cascade, to) ].compact
          groups << members if members.size > 1
        end
        last = [ cell(cascade, stage_keys.last), cell(drop_off, stage_keys.last) ].compact
        groups << last if last.size > 1
        groups
      end

      def measure_cell(slice, measure)
        return nil unless slice

        measure.nil? ? cell(slice, :cohort_size) : cell(slice[:cascade], measure)
      end

      # Memoized so the same underlying value is one shared Cell across every
      # relation it participates in (suppression must propagate).
      def cell(container, key)
        return nil unless container

        value = container[key]
        return nil unless value.is_a?(Integer)

        @index[[ container.object_id, key ]] ||= begin
          c = Cell.new(value, value.positive? && value < @min, container, key)
          @cells << c
          c
        end
      end

      def fixpoint(groups)
        loop do
          changed = false
          groups.each do |group|
            next unless group.count(&:suppressed) == 1

            candidate = group.reject(&:suppressed).select { |c| c.value.positive? }.min_by(&:value)
            next unless candidate

            candidate.suppressed = true
            changed = true
          end
          break unless changed
        end
      end

      def commit
        @cells.each { |c| c.container[c.key] = SUPPRESSED if c.suppressed }
      end

      def suppress_rates!(body, stage_keys)
        fix_rates(body[:cascade], body[:conversion_rates], stage_keys)
        disagg = body[:disaggregation]
        [ disagg[:by_site], disagg[:by_ai_an], disagg[:by_site_and_ai_an] ].each do |slices|
          slices.each_value { |slice| fix_rates(slice[:cascade], slice[:conversion_rates], stage_keys) }
        end
      end

      def fix_rates(cascade, rates, stage_keys)
        return unless rates

        stage_keys.each_cons(2) do |from, to|
          key = "#{from}_to_#{to}"
          next unless rates.key?(key)

          rates[key] = SUPPRESSED if cascade[from] == SUPPRESSED || cascade[to] == SUPPRESSED
        end
      end
    end
  end
end
