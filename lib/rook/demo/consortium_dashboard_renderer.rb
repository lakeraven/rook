# frozen_string_literal: true

require "cgi"
require "rook/demo/consortium"

module Rook
  module Demo
    # DEMO / REFERENCE ONLY — see Rook::Demo. NOT the production engine.
    #
    # Renders a Consortium as a self-contained HTML sales-demo dashboard: KPI
    # cards, a consortium roll-up table (with a regime tag per measure — the
    # "one engine, old + new" point), a clinic x measure matrix, and a
    # per-clinic drill-down with care-gap worklists. Also renders a plain-text
    # summary for CLI use.
    #
    # Deliberately dependency-free string building; no Rails views. No
    # external assets — everything is inlined so the page works under a
    # strict CSP.
    class ConsortiumDashboardRenderer
      CARE_GAP_ROW_LIMIT = 8

      def initialize(consortium)
        @consortium = consortium
      end

      def to_text
        lines = []
        lines << "#{@consortium.name} — Population Health & Quality Reporting (SYNTHETIC DEMO)"
        lines << "GPRA & UDS quality reporting computed from stock FHIR across " \
          "#{@consortium.clinic_count} clinics on mixed EHRs."
        lines << "Clinics: #{@consortium.clinic_count}    " \
          "Total patients: #{@consortium.total_patients}    " \
          "Measures: #{@consortium.measures.size}"
        lines << ""
        lines << "Consortium roll-up"
        lines << format("  %-42s %-16s %6s %6s %8s", "Measure", "Regime", "Denom", "Num", "Rate")
        @consortium.rollup.each do |r|
          lines << format("  %-42s %-16s %6d %6d %7.1f%%",
            r.measure.title, r.regime, r.denominator, r.numerator, r.rate_percent)
        end
        lines << ""
        lines << "Clinic x measure matrix"
        @consortium.clinic_reports.each do |cr|
          rates = cr.report.results.map { |r| format("%.1f%%", r.rate_percent) }.join("  ")
          lines << format("  %-38s %-16s n=%-4d %s", cr.name, cr.ehr_label, cr.patient_count, rates)
        end
        rollup_rates = @consortium.rollup.map { |r| format("%.1f%%", r.rate_percent) }.join("  ")
        lines << format("  %-38s %-16s n=%-4d %s", "CONSORTIUM TOTAL", "", @consortium.total_patients, rollup_rates)
        lines << ""
        @consortium.clinic_reports.each do |cr|
          lines << "-- #{cr.name} (#{cr.ehr_label}) --"
          cr.report.results.each do |r|
            lines << format("  %-42s denom=%-4d num=%-4d rate=%5.1f%%",
              r.measure.title, r.denominator, r.numerator, r.rate_percent)
          end
          lines << ""
        end
        lines << "Rook demo/reference asset — synthetic data, no real PHI or partner names. " \
          "One engine computes both legacy GPRA and modern eCQM/UDS measures from stock " \
          "FHIR, EHR-agnostic. Production measure engine: rook#65."
        lines.join("\n")
      end

      def to_html
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>#{h @consortium.name} — Population Health Dashboard (Demo)</title>
            <style>#{css}</style>
          </head>
          <body>
            #{header}
            <main>
              #{kpi_cards}
              <section class="rollup">
                <h2>Consortium roll-up</h2>
                #{rollup_table}
              </section>
              <section class="matrix">
                <h2>Clinic &times; measure matrix</h2>
                #{matrix_table}
              </section>
              #{@consortium.clinic_reports.map { |cr| clinic_section(cr) }.join("\n")}
            </main>
            #{footer}
          </body>
          </html>
        HTML
      end

      private

      def header
        <<~HTML
          <header>
            <p class="badge">SYNTHETIC DEMO — not real data</p>
            <h1>#{h @consortium.name} — Population Health &amp; Quality Reporting</h1>
            <p class="meta">
              GPRA &amp; UDS quality reporting computed from stock FHIR across
              #{@consortium.clinic_count} clinics on mixed EHRs &mdash;
              reporting these clinics' own EHRs don't provide.
            </p>
          </header>
        HTML
      end

      def kpi_cards
        <<~HTML
          <section class="kpis">
            #{kpi_card("Clinics", @consortium.clinic_count)}
            #{kpi_card("Total patients", @consortium.total_patients)}
            #{kpi_card("Measures", @consortium.measures.size)}
          </section>
        HTML
      end

      def kpi_card(label, value)
        "<div class=\"kpi\"><span class=\"kpi-value\">#{h value}</span>" \
          "<span class=\"kpi-label\">#{h label}</span></div>"
      end

      def rollup_table
        rows = @consortium.rollup.map do |r|
          "<tr><td>#{h r.measure.title}</td>" \
            "<td><span class=\"regime\">#{h r.regime}</span></td>" \
            "<td class=\"num\">#{r.denominator}</td>" \
            "<td class=\"num\">#{r.numerator}</td>" \
            "<td class=\"num rate\">#{rate_bar(r.rate_percent)}</td></tr>"
        end.join("\n")

        <<~HTML
          <table class="measures">
            <thead><tr><th>Measure</th><th>Regime</th><th class="num">Denominator</th>
              <th class="num">Numerator</th><th class="num">Rate</th></tr></thead>
            <tbody>#{rows}</tbody>
          </table>
        HTML
      end

      def matrix_table
        measure_headers = @consortium.measures.map { |m| "<th class=\"num\">#{h m.title}</th>" }.join
        clinic_rows = @consortium.clinic_reports.map { |cr| matrix_row(cr) }.join("\n")
        consortium_row = matrix_row(nil, label: "CONSORTIUM TOTAL", ehr_label: "&mdash;",
          patient_count: @consortium.total_patients, results: @consortium.rollup, bold: true)

        <<~HTML
          <table class="matrix-table">
            <thead><tr><th>Clinic</th><th>EHR</th><th class="num">Patients</th>#{measure_headers}</tr></thead>
            <tbody>
              #{clinic_rows}
              #{consortium_row}
            </tbody>
          </table>
        HTML
      end

      def matrix_row(clinic_report, label: nil, ehr_label: nil, patient_count: nil, results: nil, bold: false)
        label ||= clinic_report.name
        ehr_label ||= h(clinic_report.ehr_label)
        patient_count ||= clinic_report.patient_count
        results ||= clinic_report.report.results
        cells = results.map { |r| "<td class=\"num rate\">#{rate_bar(r.rate_percent)}</td>" }.join
        row = "<tr#{bold ? ' class="consortium-row"' : ''}>" \
          "<td>#{h label}</td><td>#{ehr_label}</td><td class=\"num\">#{h patient_count}</td>#{cells}</tr>"
        row
      end

      def rate_bar(rate_percent)
        pct = rate_percent.clamp(0.0, 100.0)
        "<span class=\"bar\"><span class=\"bar-fill\" style=\"width:#{pct}%\"></span></span> #{rate_percent}%"
      end

      def clinic_section(clinic_report)
        <<~HTML
          <section class="clinic">
            <h2>#{h clinic_report.name}</h2>
            <p class="meta">#{h clinic_report.ehr_label} &middot; #{clinic_report.patient_count} synthetic patients</p>
            #{clinic_measures_table(clinic_report)}
            #{clinic_report.report.results.map { |r| worklist_section(r) }.join("\n")}
          </section>
        HTML
      end

      def clinic_measures_table(clinic_report)
        rows = clinic_report.report.results.map do |r|
          "<tr><td>#{h r.measure.title}</td>" \
            "<td class=\"num\">#{r.denominator}</td>" \
            "<td class=\"num\">#{r.numerator}</td>" \
            "<td class=\"num rate\">#{rate_bar(r.rate_percent)}</td></tr>"
        end.join("\n")

        <<~HTML
          <table class="measures">
            <thead><tr><th>Measure</th><th class="num">Denominator</th>
              <th class="num">Numerator</th><th class="num">Rate</th></tr></thead>
            <tbody>#{rows}</tbody>
          </table>
        HTML
      end

      def worklist_section(result)
        <<~HTML
          <div class="worklist">
            <h3>#{h result.measure.title} &mdash; care-gap worklist (#{result.care_gaps.size})</h3>
            #{care_gap_table(result)}
          </div>
        HTML
      end

      def care_gap_table(result)
        return "<p class=\"empty\">No care gaps — every eligible patient meets the measure.</p>" if result.care_gaps.empty?

        shown = result.care_gaps.first(CARE_GAP_ROW_LIMIT)
        remainder = result.care_gaps.size - shown.size
        rows = shown.map do |gap|
          "<tr><td>#{h gap.patient.name}</td><td class=\"mono\">#{h gap.patient.id}</td>" \
            "<td>#{h gap.reason}</td></tr>"
        end.join("\n")
        more_row = remainder.positive? ? "<tr><td colspan=\"3\" class=\"more\">+#{remainder} more</td></tr>" : ""

        <<~HTML
          <table>
            <thead><tr><th>Patient</th><th>ID</th><th>Care gap</th></tr></thead>
            <tbody>#{rows}
              #{more_row}
            </tbody>
          </table>
        HTML
      end

      def footer
        <<~HTML
          <footer>
            <p>Rook demo/reference asset &mdash; synthetic data, no real PHI or partner names. One
            engine computes both legacy GPRA and modern eCQM/UDS measures from stock FHIR,
            EHR-agnostic. Production measure engine: rook#65.</p>
          </footer>
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
          header, main, footer { max-width: 1100px; margin: 0 auto; }
          header { border-bottom: 3px solid #14532d; padding-bottom: 1rem; margin-bottom: 1.6rem; }
          h1 { margin: .3rem 0; font-size: 1.55rem; }
          .badge { display: inline-block; background: #b45309; color: #fff; font-size: .72rem;
                   font-weight: 600; letter-spacing: .04em; text-transform: uppercase;
                   padding: .25rem .55rem; border-radius: .3rem; margin: 0; }
          .meta { color: #5a6b7a; font-size: .9rem; }
          @media (prefers-color-scheme: dark) { .meta { color: #93a4b4; } }
          section, .clinic { background: #fff; border: 1px solid #d8e0e6; border-radius: .5rem;
                    padding: 1.2rem 1.5rem; margin-bottom: 1.4rem; }
          @media (prefers-color-scheme: dark) { section, .clinic { background: #16212e; border-color: #26333f; } }
          h2 { margin: 0 0 .8rem; font-size: 1.15rem; color: #14532d; }
          @media (prefers-color-scheme: dark) { h2 { color: #7fd1a0; } }
          h3 { margin: 1rem 0 .3rem; font-size: .95rem; }
          .kpis { display: flex; gap: 1rem; padding: 0; background: none; border: 0; }
          .kpi { flex: 1; background: #fff; border: 1px solid #d8e0e6; border-radius: .5rem;
                 padding: 1rem 1.2rem; text-align: center; }
          @media (prefers-color-scheme: dark) { .kpi { background: #16212e; border-color: #26333f; } }
          .kpi-value { display: block; font-size: 1.8rem; font-weight: 700; color: #14532d;
                       font-variant-numeric: tabular-nums; }
          @media (prefers-color-scheme: dark) { .kpi-value { color: #7fd1a0; } }
          .kpi-label { display: block; font-size: .78rem; color: #5a6b7a; text-transform: uppercase;
                       letter-spacing: .04em; margin-top: .2rem; }
          @media (prefers-color-scheme: dark) { .kpi-label { color: #93a4b4; } }
          table { width: 100%; border-collapse: collapse; font-size: .86rem; }
          th, td { text-align: left; padding: .5rem .6rem; border-bottom: 1px solid #e6ebef; }
          @media (prefers-color-scheme: dark) { th, td { border-color: #26333f; } }
          th { font-size: .72rem; text-transform: uppercase; letter-spacing: .04em; color: #7a8a99; }
          .num { text-align: right; font-variant-numeric: tabular-nums; }
          .measures tbody .rate, .matrix-table tbody .rate { font-weight: 700; color: #14532d; }
          @media (prefers-color-scheme: dark) { .measures tbody .rate, .matrix-table tbody .rate { color: #7fd1a0; } }
          .regime { display: inline-block; font-size: .68rem; font-weight: 600; text-transform: uppercase;
                    letter-spacing: .03em; padding: .15rem .45rem; border-radius: .25rem;
                    background: #e6ebef; color: #445566; }
          @media (prefers-color-scheme: dark) { .regime { background: #26333f; color: #b8c4cf; } }
          .bar { display: inline-block; width: 4rem; height: .45rem; border-radius: .25rem;
                 background: #e6ebef; overflow: hidden; vertical-align: middle; margin-right: .4rem; }
          @media (prefers-color-scheme: dark) { .bar { background: #26333f; } }
          .bar-fill { display: block; height: 100%; background: #16a34a; }
          @media (prefers-color-scheme: dark) { .bar-fill { background: #7fd1a0; } }
          .consortium-row { font-weight: 700; }
          .consortium-row td { border-top: 2px solid #14532d; }
          @media (prefers-color-scheme: dark) { .consortium-row td { border-top-color: #7fd1a0; } }
          .mono { font-family: ui-monospace, monospace; font-size: .8rem; color: #5a6b7a; }
          .empty { color: #16a34a; font-size: .9rem; }
          .more { text-align: center; color: #7a8a99; font-style: italic; }
          footer { font-size: .78rem; color: #8a97a3; }
          footer p { max-width: 1100px; margin: 0 auto; }
        CSS
      end
    end
  end
end
