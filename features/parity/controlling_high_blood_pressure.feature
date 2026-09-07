# CRS-faithful executable spec (rook#2 translation, rook#99 parity).
# Evidence: docs/measures/controlling-high-blood-pressure.md
#   spec: docs/measures/evidence/crs-v25/spec/controlling-high-blood-pressure.txt (§2.6.2)
#   M:    BGPXD22.m (BPCPT), BGPXD21A.m (BPCPTD) @ BGP v25.1 Build 98 — evidence.lock.json
#   populations: docs/measures/evidence/crs-v25/spec/populations.txt (User Population)
#   vocabulary: features/parity/VOCABULARY.md (canonical seed facts)
@crs-v25
Feature: Controlling High Blood Pressure — Million Hearts (CRS v25 §2.6.2)

  GPRA denominator (NQF 0018): User Population ages 18–85 with hypertension
  diagnosed during the period or the year prior, excluding ESRD-ever and current
  pregnancy. Numerator: last BP of the period < 140/90, with a same-day
  tie-break that prefers the controlled reading.

  Background:
    Given the report period is 2025-01-01 to 2025-12-31

  Scenario: Hypertensive adult in the denominator
    Given a User Population patient "H-BASE" aged 62 at period end
    And "H-BASE" has a hypertension POV recorded 2024-06-10
    When the National GPRA report is run
    Then "H-BASE" is in the "Controlling High Blood Pressure" GPRA denominator

  Scenario: Hypertension diagnosed before the prior year does not qualify by POV alone
    Given a User Population patient "H-OLD" aged 62 at period end
    And "H-OLD" has a hypertension POV recorded 2021-02-01
    And "H-OLD" has no hypertension Problem List entry
    When the National GPRA report is run
    Then "H-OLD" is not in the "Controlling High Blood Pressure" GPRA denominator

  Scenario: ESRD history ever excludes the patient
    Given a User Population patient "H-ESRD" aged 62 at period end
    And "H-ESRD" has a hypertension POV recorded 2025-02-01
    And "H-ESRD" has an ESRD diagnosis recorded 2015-01-01
    When the National GPRA report is run
    Then "H-ESRD" is not in the "Controlling High Blood Pressure" GPRA denominator

  Scenario: Current pregnancy excludes the patient
    Given a female User Population patient "H-PREG" aged 30 at period end
    And "H-PREG" has a hypertension POV recorded 2025-02-01
    And "H-PREG" is documented currently pregnant during the report period
    When the National GPRA report is run
    Then "H-PREG" is not in the "Controlling High Blood Pressure" GPRA denominator

  Scenario: Age 86 at period end is outside the band
    Given a User Population patient "H-86" aged 86 at period end
    And "H-86" has a hypertension POV recorded 2025-02-01
    When the National GPRA report is run
    Then "H-86" is not in the "Controlling High Blood Pressure" GPRA denominator

  Scenario: Last BP of the period controls
    Given a qualifying GPRA hypertensive patient "H-CTRL"
    And "H-CTRL" has a BP reading of 152/96 on 2025-03-11 at an ambulatory visit
    And "H-CTRL" has a BP reading of 124/80 on 2025-11-19 at an ambulatory visit
    When the National GPRA report is run
    Then "H-CTRL" is in the "Controlling High Blood Pressure" GPRA numerator

  Scenario: Exactly 140/90 is not controlled
    Given a qualifying GPRA hypertensive patient "H-EDGE"
    And "H-EDGE" has a BP reading of 140/90 on 2025-06-14 at an ambulatory visit
    When the National GPRA report is run
    Then "H-EDGE" is not in the "Controlling High Blood Pressure" GPRA numerator

  Scenario: Same-day readings — the controlled reading is preferred
    Given a qualifying GPRA hypertensive patient "H-SAMEDAY"
    And "H-SAMEDAY" has a BP reading of 148/94 on 2025-09-05 at an ambulatory visit
    And "H-SAMEDAY" has a BP reading of 132/84 on 2025-09-05 at an ambulatory visit
    When the National GPRA report is run
    Then "H-SAMEDAY" is in the "Controlling High Blood Pressure" GPRA numerator

  Scenario: No BP documented in the period is not controlled
    Given a qualifying GPRA hypertensive patient "H-NOBP"
    And "H-NOBP" has no BP reading during the report period
    When the National GPRA report is run
    Then "H-NOBP" is not in the "Controlling High Blood Pressure" GPRA numerator
