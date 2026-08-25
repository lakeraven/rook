# frozen_string_literal: true

require "cgi"
require "rook/demo/report"

module Rook
  module Demo
    # DEMO / REFERENCE ONLY — see Rook::Demo.
    #
    # Renders a Report as either a plain-text summary (for the terminal) or a
    # self-contained HTML page (for the sales demo). Deliberately dependency-free
    # string building — no Rails views, no template engine.
    class ReportRenderer
      def initialize(report)
        @report = report
      end

      def to_text
        lines = []
        lines << "UDS Quality Report (DEMO / SYNTHETIC DATA)"
        lines << "Clinic: #{@report.clinic_label}"
        lines << "Measurement period: #{@report.period.first} to #{@report.period.last}"
        lines << "Population: #{@report.patient_count} synthetic patients"
        lines << ""
        @report.results.each do |result|
          lines << "== #{result.measure.title} =="
          lines << "  Measure ID:  #{result.measure.id}"
          lines << "  Denominator: #{result.denominator}"
          lines << "  Numerator:   #{result.numerator}"
          lines << "  Rate:        #{result.rate_percent}%"
          lines << "  #{result.measure.interpretation}"
          lines << "  Care-gap worklist (#{result.care_gaps.size}):"
          if result.care_gaps.empty?
            lines << "    (none)"
          else
            result.care_gaps.each do |gap|
              lines << "    - #{gap.patient.name} (#{gap.patient.id}): #{gap.reason}"
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
            <title>UDS Quality Report (Demo)</title>
            <style>#{css}</style>
          </head>
          <body>
            <header>
              <p class="badge">Demo / synthetic data — not a production report</p>
              <h1>UDS Quality Report</h1>
              <p class="meta">
                #{h @report.clinic_label} &middot;
                Measurement period #{h @report.period.first} to #{h @report.period.last} &middot;
                #{@report.patient_count} synthetic patients
              </p>
            </header>
            <main>
              #{@report.results.map { |r| measure_section(r) }.join("\n")}
            </main>
            <footer>
              <p>Rook demo asset. The production measure engine is the Pathling-based
              work in rook#65. This page contains no real PHI.</p>
            </footer>
          </body>
          </html>
        HTML
      end

      private

      def measure_section(result)
        <<~HTML
          <section class="measure">
            <h2>#{h result.measure.title}</h2>
            <p class="measure-id">#{h result.measure.id}</p>
            <div class="scorecard">
              <div class="stat"><span class="n">#{result.denominator}</span><span class="l">Denominator</span></div>
              <div class="stat"><span class="n">#{result.numerator}</span><span class="l">Numerator</span></div>
              <div class="stat rate"><span class="n">#{result.rate_percent}%</span><span class="l">Rate</span></div>
            </div>
            <p class="interp">#{h result.measure.interpretation}</p>
            <h3>Care-gap worklist (#{result.care_gaps.size})</h3>
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
                 line-height: 1.5; background: #f7f7f8; color: #1a1a1a; }
          @media (prefers-color-scheme: dark) { body { background: #16171a; color: #e6e6e6; } }
          header { max-width: 900px; margin: 0 auto 2rem; }
          h1 { margin: .3rem 0; font-size: 1.8rem; }
          .badge { display: inline-block; background: #b45309; color: #fff; font-size: .72rem;
                   font-weight: 600; letter-spacing: .04em; text-transform: uppercase;
                   padding: .25rem .55rem; border-radius: .3rem; margin: 0; }
          .meta { color: #666; font-size: .9rem; }
          @media (prefers-color-scheme: dark) { .meta { color: #9aa0a6; } }
          main { max-width: 900px; margin: 0 auto; }
          .measure { background: #fff; border: 1px solid #e2e2e5; border-radius: .6rem;
                     padding: 1.4rem 1.6rem; margin-bottom: 1.6rem; }
          @media (prefers-color-scheme: dark) { .measure { background: #202226; border-color: #33363b; } }
          .measure h2 { margin: 0 0 .1rem; font-size: 1.25rem; }
          .measure-id { margin: 0 0 1rem; font-size: .78rem; color: #888; font-family: ui-monospace, monospace; }
          .scorecard { display: flex; gap: 1rem; flex-wrap: wrap; }
          .stat { flex: 1 1 120px; background: #f3f4f6; border-radius: .5rem; padding: 1rem;
                  text-align: center; }
          @media (prefers-color-scheme: dark) { .stat { background: #2a2d33; } }
          .stat .n { display: block; font-size: 1.9rem; font-weight: 700; }
          .stat .l { display: block; font-size: .75rem; text-transform: uppercase; letter-spacing: .05em;
                     color: #777; margin-top: .2rem; }
          .stat.rate .n { color: #2563eb; }
          .interp { font-size: .85rem; color: #666; margin: .9rem 0 1.2rem; }
          @media (prefers-color-scheme: dark) { .interp { color: #9aa0a6; } }
          h3 { font-size: .95rem; margin: 0 0 .6rem; }
          table { width: 100%; border-collapse: collapse; font-size: .86rem; }
          th, td { text-align: left; padding: .5rem .6rem; border-bottom: 1px solid #ededf0; }
          @media (prefers-color-scheme: dark) { th, td { border-color: #33363b; } }
          th { font-size: .72rem; text-transform: uppercase; letter-spacing: .04em; color: #888; }
          .mono { font-family: ui-monospace, monospace; font-size: .8rem; color: #666; }
          .empty { color: #16a34a; font-size: .9rem; }
          footer { max-width: 900px; margin: 2rem auto 0; font-size: .78rem; color: #999; }
        CSS
      end
    end
  end
end
