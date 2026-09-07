# DEMO / REFERENCE ONLY — the user story behind Rook::Demo (see lib/rook/demo.rb).
# This is the sales-demo quality report, NOT the production Pathling measure
# engine (rook#60 / rook#65). It runs against the committed synthetic FHIR R4
# population so the numbers are fixed and reviewable.

Feature: Quality and grant reporting for a tribal clinic
  As a quality lead at a tribal / urban-Indian clinic
  I want a UDS or GPRA quality report over my patient population
  So that I can meet my funding and reporting obligations
  And see exactly which patients still have care gaps to close

  Background:
    Given a synthetic population of 35 AI/AN patients

  # The UIO view: an urban Indian organization files quality with HRSA as UDS.
  Scenario: A UIO quality lead runs the UDS Table 6B report
    When I generate the UDS quality report
    Then the report covers 35 patients
    And the report is framed as "UDS Table 6B (HRSA)"
    And the "Diabetes: HbA1c Poor Control (>9%)" measure reports 8 of 20 at 40.0%
    And the "Controlling High Blood Pressure (<140/90)" measure reports 9 of 15 at 60.0%

  # The tribal-638 view: the SAME measures, packaged as IHS CRS / GPRA.
  Scenario: A tribal-638 quality lead runs the GPRA report
    When I generate the GPRA quality report
    Then the report covers 35 patients
    And the report is framed as "IHS CRS / GPRA National Clinical Measures (demo preview)"
    And the "Depression Screening (PHQ, age 12+)" measure reports 28 of 35 at 80.0%

  # The report is not just a number — it is a worklist of who to reach out to.
  Scenario: The quality lead works the care-gap list to close gaps
    When I generate the UDS quality report
    Then the "Diabetes: HbA1c Poor Control (>9%)" measure lists 8 patients with a care gap
    And every care-gap entry names a patient and gives a reason
