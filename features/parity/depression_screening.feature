# CRS-faithful executable spec (rook#2 translation, rook#99 parity).
# Evidence: docs/measures/depression-screening.md
#   spec: docs/measures/evidence/crs-v25/spec/depression-screening.txt (§2.5.4)
#   M:    BGPXD25.m, BGPXD27.m, BGPXPC11.m @ BGP v25.1 Build 98 — evidence.lock.json
#   populations: docs/measures/evidence/crs-v25/spec/populations.txt (User Population)
#   vocabulary: features/parity/VOCABULARY.md (canonical seed facts)
@wip @crs-v25 @pending-engine
Feature: Depression Screening (CRS v25 §2.5.4)

  GPRA denominators are User Population split 12–17 and 18+ (by sex). The
  numerator is screened for depression OR diagnosed with a mood disorder during
  the period; refusals are excluded. Screening evidence spans PCC and BHS: exam
  code 36, Z13.3* POV, CPT 1220F/3725F/G0444, BHS problem code 14.1, or a
  PHQ-9 / PHQ-T / EPDS measurement.

  Background:
    Given the report period is 2025-01-01 to 2025-12-31

  Scenario: Adolescents and adults land in separate GPRA denominators
    Given a User Population patient "D-TEEN" aged 14 at period end
    And a User Population patient "D-ADULT" aged 40 at period end
    When the National GPRA report is run
    Then "D-TEEN" is in the "Depression Screening 12-17" GPRA denominator
    And "D-ADULT" is in the "Depression Screening 18+" GPRA denominator

  Scenario: A PHQ-9 measurement counts as screening
    Given a User Population patient "D-PHQ" aged 40 at period end
    And "D-PHQ" has a PHQ-9 measurement recorded 2025-07-10
    When the National GPRA report is run
    Then "D-PHQ" is in the "Depression Screening 18+" GPRA numerator

  Scenario: A mood disorder diagnosis on two visits counts without any screening
    Given a User Population patient "D-MOOD" aged 40 at period end
    And "D-MOOD" has a mood disorder POV recorded 2025-03-04
    And "D-MOOD" has a mood disorder POV recorded 2025-09-16
    When the National GPRA report is run
    Then "D-MOOD" is in the "Depression Screening 18+" GPRA numerator

  Scenario: A single mood disorder visit is not enough
    Given a User Population patient "D-ONEMOOD" aged 40 at period end
    And "D-ONEMOOD" has a mood disorder POV recorded 2025-03-04
    And "D-ONEMOOD" has no depression screening during the report period
    When the National GPRA report is run
    Then "D-ONEMOOD" is not in the "Depression Screening 18+" GPRA numerator

  # M-verified path: BH exam 36 counts only with result P or N (^AMHREC check
  # in BGPXD25/BGPXPC11); a PCC V Exam refusal variant is an open question in
  # the dossier and gets its own scenario once the M pass settles it.
  Scenario: A refused BH screening exam does not count
    Given a User Population patient "D-REFUSED" aged 40 at period end
    And "D-REFUSED" has a BH depression screening exam recorded 2025-07-10 with result "R"
    When the National GPRA report is run
    Then "D-REFUSED" is not in the "Depression Screening 18+" GPRA numerator

  Scenario: A BHS-side screening counts (PCC or BHS data)
    Given a User Population patient "D-BHS" aged 40 at period end
    And "D-BHS" has a BHS depression screening (problem code 14.1) recorded 2025-05-22
    When the National GPRA report is run
    Then "D-BHS" is in the "Depression Screening 18+" GPRA numerator

  Scenario: Age 11 at period end is outside every denominator
    Given a User Population patient "D-CHILD" aged 11 at period end
    When the National GPRA report is run
    Then "D-CHILD" is not in the "Depression Screening 12-17" GPRA denominator
    And "D-CHILD" is not in the "Depression Screening 18+" GPRA denominator
