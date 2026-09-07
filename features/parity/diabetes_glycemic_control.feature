# CRS-faithful executable spec (rook#2 translation, rook#99 parity).
# Evidence: docs/measures/diabetes-glycemic-control.md
#   spec: docs/measures/evidence/crs-v25/spec/diabetes-glycemic-control.txt (§2.1.2)
#   M:    BGPXD2.m (DMGC, HGBA1C) @ BGP v25.1 Build 98 — see evidence.lock.json
#   populations: docs/measures/evidence/crs-v25/spec/populations.txt (User Pop Diabetic)
#   vocabulary: features/parity/VOCABULARY.md (canonical seed facts)
# These scenarios encode CRS v25 semantics — deliberately NOT the UDS/eCQM shape
# the Rook::Demo measures approximate. The rook driver runs them against
# Rook::Crs; the #99 CRS driver runs the same scenarios against real CRS.
@crs-v25
Feature: Diabetes: Glycemic Control (CRS v25 §2.1.2)

  The GPRA denominator is User Population diabetics — diabetes diagnosed prior
  to the Report Period, at least two visits during the period, and two DM
  visits ever or a DM Problem List entry. There is NO age band. Poor control is
  strictly A1c > 9: a patient with no documented A1c is NOT in the poor-control
  numerator (M-verified — opposite of the UDS/eCQM convention).

  Background:
    Given the report period is 2025-01-01 to 2025-12-31

  Scenario: Qualifying diabetic enters the denominator with no upper age limit
    Given a User Population patient "P-ELDER" aged 80 at period end
    And "P-ELDER" has a diabetes POV first recorded 2018-06-15
    And "P-ELDER" has 2 ambulatory visits during the report period
    And "P-ELDER" has a diabetes Problem List entry with status "Active" entered 2018-06-15
    When the National GPRA report is run
    Then "P-ELDER" is in the "Diabetes: Glycemic Control" GPRA denominator

  Scenario: Diabetes diagnosed during the period does not qualify
    Given a User Population patient "P-NEW" aged 50 at period end
    And "P-NEW" has a diabetes POV first recorded 2025-03-01
    And "P-NEW" has 2 ambulatory visits during the report period
    And "P-NEW" has a diabetes Problem List entry with status "Active" entered 2025-03-01
    When the National GPRA report is run
    Then "P-NEW" is not in the "Diabetes: Glycemic Control" GPRA denominator
    # No diagnosis evidence — POV or Problem List — predates the period start.

  Scenario: Only one visit during the period does not qualify
    Given a User Population patient "P-ONEVISIT" aged 50 at period end
    And "P-ONEVISIT" has a diabetes POV first recorded 2018-06-15
    And "P-ONEVISIT" has 1 ambulatory visit during the report period
    And "P-ONEVISIT" has a diabetes Problem List entry with status "Active" entered 2018-06-15
    When the National GPRA report is run
    Then "P-ONEVISIT" is not in the "Diabetes: Glycemic Control" GPRA denominator

  Scenario: A1c greater than 9 is poor control
    Given a qualifying GPRA diabetic patient "P-POOR"
    And "P-POOR" has an A1c lab result of 10.8 resulted 2025-05-14
    When the National GPRA report is run
    Then "P-POOR" is in the "Poor Glycemic Control" GPRA numerator

  Scenario: A1c of exactly 9.0 is not poor control
    Given a qualifying GPRA diabetic patient "P-NINE"
    And "P-NINE" has an A1c lab result of 9.0 resulted 2025-05-14
    When the National GPRA report is run
    Then "P-NINE" is not in the "Poor Glycemic Control" GPRA numerator

  Scenario: No documented A1c is NOT poor control (CRS differs from UDS/eCQM here)
    Given a qualifying GPRA diabetic patient "P-NOTEST"
    And "P-NOTEST" has no A1c documented during the report period
    When the National GPRA report is run
    Then "P-NOTEST" is not in the "Poor Glycemic Control" GPRA numerator
    And "P-NOTEST" is on the "diabetic patients without a documented A1c" patient list

  Scenario: Most recent A1c wins
    Given a qualifying GPRA diabetic patient "P-RECENT"
    And "P-RECENT" has an A1c lab result of 11.2 resulted 2025-01-12
    And "P-RECENT" has an A1c lab result of 7.8 resulted 2025-12-05
    When the National GPRA report is run
    Then "P-RECENT" is not in the "Poor Glycemic Control" GPRA numerator
    And "P-RECENT" is in the "Good Glycemic Control" numerator

  Scenario: Same-day tests — the resulted test beats the unresulted one
    Given a qualifying GPRA diabetic patient "P-SAMEDAY"
    And "P-SAMEDAY" has an A1c lab test with no result on 2025-08-02
    And "P-SAMEDAY" has an A1c lab result of 10.1 resulted 2025-08-02
    When the National GPRA report is run
    Then "P-SAMEDAY" is in the "Poor Glycemic Control" GPRA numerator

  Scenario: CPT 3046F counts as A1c greater than 9
    Given a qualifying GPRA diabetic patient "P-CPT"
    And "P-CPT" has CPT "3046F" recorded 2025-06-20
    When the National GPRA report is run
    Then "P-CPT" is in the "Poor Glycemic Control" GPRA numerator
