# frozen_string_literal: true

require "cgi"
require "rook/demo/report"

module Rook
  module Demo
    # DEMO / REFERENCE ONLY — see Rook::Demo.
    #
    # Renders a Report as an IHS CRS / GPRA-style national clinical measures
    # report: a summary table (measure name / denominator / numerator / rate)
    # followed by per-measure care-gap worklists. Same underlying measure
    # results as the UDS view (ReportRenderer) — only the packaging differs.
    #
    # Deliberately dependency-free string building; no Rails views.
    class GPRAReportRenderer
      def initialize(report)
        @report = report
      end

      def to_text
        lines = []
        lines << "IHS CRS / GPRA National Clinical Measures (DEMO / SYNTHETIC DATA)"
        lines << "Facility: #{@report.clinic_label}"
        lines << "Report period: #{@report.period.first} to #{@report.period.last}"
        lines << "User population: #{@report.patient_count} synthetic patients"
        lines << ""
        lines << "Measure summary"
        lines << format("  %-42s %6s %6s %8s", "Measure", "Denom", "Num", "Rate")
        @report.results.each do |result|
          lines << format("  %-42s %6d %6d %7.1f%%",
            result.measure.title, result.denominator, result.numerator, result.rate_percent)
        end
        lines << ""
        @report.results.each do |result|
          lines << "Care-gap worklist — #{result.measure.title} (#{result.care_gaps.size})"
          if result.care_gaps.empty?
            lines << "  (none)"
          else
            result.care_gaps.each do |gap|
              lines << "  - #{gap.patient.name} (#{gap.patient.id}): #{gap.reason}"
            end
          end
          lines << ""
        end
        lines.join("\n")
      end

      def to_html
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>IHS CRS / GPRA Report (Demo)</title>
            <style>#{css}</style>
          </head>
          <body>
            <header>
              <p class="badge">Demo / synthetic data — not a production report</p>
              <h1>IHS CRS / GPRA National Clinical Measures</h1>
              <p class="meta">
                #{h @report.clinic_label} &middot;
                Report period #{h @report.period.first} to #{h @report.period.last} &middot;
                User population #{@report.patient_count} synthetic patients
              </p>
            </header>
            <main>
              <section class="summary">
                <h2>Measure summary</h2>
                #{summary_table}
              </section>
              #{@report.results.map { |r| worklist_section(r) }.join("\n")}
            </main>
            <footer>
              <p>Rook demo asset. This GPRA view (IHS/tribal-638 segment) and the UDS
              view (HRSA/UIO segment) render the same measure computations. The
              production measure engine is the Pathling-based work in rook#65. No real PHI.</p>
            </footer>
          </body>
          </html>
        HTML
      end

      private

      def summary_table
        rows = @report.results.map do |result|
          "<tr><td>#{h result.measure.title}</td>" \
            "<td class=\"num\">#{result.denominator}</td>" \
            "<td class=\"num\">#{result.numerator}</td>" \
            "<td class=\"num rate\">#{result.rate_percent}%</td></tr>"
        end.join("\n")

        <<~HTML
          <table class="measures">
            <thead><tr><th>Measure</th><th class="num">Denominator</th><th class="num">Numerator</th><th class="num">Rate</th></tr></thead>
            <tbody>#{rows}</tbody>
          </table>
        HTML
      end

      def worklist_section(result)
        <<~HTML
          <section class="worklist">
            <h3>#{h result.measure.title} &mdash; care-gap worklist (#{result.care_gaps.size})</h3>
            <p class="interp">#{h result.measure.interpretation}</p>
            #{care_gap_table(result)}
          </section>
        HTML
      end

      def care_gap_table(result)
        return "<p class=\"empty\">No care gaps — every eligible patient meets the measure.</p>" if result.care_gaps.empty?

        rows = result.care_gaps.map do |gap|
          "<tr><td>#{h gap.patient.name}</td><td class=\"mono\">#{h gap.patient.id}</td>" \
            "<td>#{h gap.patient.tribal_affiliation}</td><td>#{h gap.reason}</td></tr>"
        end.join("\n")

        <<~HTML
          <table>
            <thead><tr><th>Patient</th><th>ID</th><th>Affiliation</th><th>Care gap</th></tr></thead>
            <tbody>#{rows}</tbody>
          </table>
        HTML
      end

      def h(value)
        CGI.escapeHTML(value.to_s)
      end

      def css
        <<~CSS
          :root { color-scheme: light dark; }
          * { box-sizing: border-box; }
          body { font-family: -apple-system, system-ui, sans-serif; margin: 0; padding: 2rem;
                 line-height: 1.5; background: #f4f6f8; color: #14202b; }
          @media (prefers-color-scheme: dark) { body { background: #0f1620; color: #e6ecf2; } }
          header, main, footer { max-width: 900px; margin: 0 auto; }
          header { border-bottom: 3px solid #14532d; padding-bottom: 1rem; margin-bottom: 1.6rem; }
          h1 { margin: .3rem 0; font-size: 1.55rem; }
          .badge { display: inline-block; background: #b45309; color: #fff; font-size: .72rem;
                   font-weight: 600; letter-spacing: .04em; text-transform: uppercase;
                   padding: .25rem .55rem; border-radius: .3rem; margin: 0; }
          .meta { color: #5a6b7a; font-size: .9rem; }
          @media (prefers-color-scheme: dark) { .meta { color: #93a4b4; } }
          section { background: #fff; border: 1px solid #d8e0e6; border-radius: .5rem;
                    padding: 1.2rem 1.5rem; margin-bottom: 1.4rem; }
          @media (prefers-color-scheme: dark) { section { background: #16212e; border-color: #26333f; } }
          h2 { margin: 0 0 .8rem; font-size: 1.15rem; color: #14532d; }
          @media (prefers-color-scheme: dark) { h2 { color: #7fd1a0; } }
          h3 { margin: 0 0 .3rem; font-size: 1rem; }
          .interp { font-size: .82rem; color: #5a6b7a; margin: 0 0 .8rem; }
          @media (prefers-color-scheme: dark) { .interp { color: #93a4b4; } }
          table { width: 100%; border-collapse: collapse; font-size: .86rem; }
          th, td { text-align: left; padding: .5rem .6rem; border-bottom: 1px solid #e6ebef; }
          @media (prefers-color-scheme: dark) { th, td { border-color: #26333f; } }
          th { font-size: .72rem; text-transform: uppercase; letter-spacing: .04em; color: #7a8a99; }
          .num { text-align: right; font-variant-numeric: tabular-nums; }
          .measures tbody .rate { font-weight: 700; color: #14532d; }
          @media (prefers-color-scheme: dark) { .measures tbody .rate { color: #7fd1a0; } }
          .mono { font-family: ui-monospace, monospace; font-size: .8rem; color: #5a6b7a; }
          .empty { color: #16a34a; font-size: .9rem; }
          footer { font-size: .78rem; color: #8a97a3; border: 0; background: none; }
        CSS
      end
    end
  end
end
