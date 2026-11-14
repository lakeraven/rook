# CRS-faithful executable spec (rook#2 translation, rook#99 parity).
# Evidence: docs/measures/dental.md
#   spec: docs/measures/evidence/crs-v25/spec/dental.txt (§2.2.1–2.2.3)
#   M:    BGPXD21.m, BGPXD211.m, BGPXD3.m, BGPXD3A.m, BGPXD1.m @ BGP v25.1 Build 98 — evidence.lock.json
#   populations: docs/measures/evidence/crs-v25/spec/populations.txt (User Population)
#   vocabulary: features/parity/VOCABULARY.md (canonical seed facts)
@crs-v25
Feature: Dental Group — Access, Sealants, Topical Fluoride (CRS v25 §2.2)

  All three GPRA denominators are User Population, aged as of the FIRST day of
  the Report Period (M: BGPAGEB). Access counts any documented dental visit;
  Sealants (ages 2–15) counts a sealant in the period or IHS Dental Tracking
  code 0007 in the past three years; Topical Fluoride (ages 1–15) counts any
  fluoride application in the period.

  Background:
    Given the report period is 2025-01-01 to 2025-12-31

  # -- 2.2.1 Access to Dental Services ---------------------------------------

  Scenario: An IHS Dental Tracking code documents a dental visit
    Given a User Population patient "DA-TRACK" aged 30 at period start
    And "DA-TRACK" has RPMS dental code "0190" recorded 2025-03-12
    When the National GPRA report is run
    Then "DA-TRACK" is in the "Access to Dental Services" GPRA denominator
    And "DA-TRACK" is in the "Access to Dental Services" GPRA numerator

  Scenario: A dental CPT documents a dental visit
    Given a User Population patient "DA-CPT" aged 30 at period start
    And "DA-CPT" has CPT "D0120" recorded 2025-04-02
    When the National GPRA report is run
    Then "DA-CPT" is in the "Access to Dental Services" GPRA numerator

  Scenario: A dental exam documents a dental visit
    Given a User Population patient "DA-EXAM" aged 30 at period start
    And "DA-EXAM" has a dental exam recorded 2025-05-20
    When the National GPRA report is run
    Then "DA-EXAM" is in the "Access to Dental Services" GPRA numerator

  Scenario: A dental visit POV documents a dental visit
    Given a User Population patient "DA-POV" aged 30 at period start
    And "DA-POV" has a dental visit POV recorded 2025-06-09
    When the National GPRA report is run
    Then "DA-POV" is in the "Access to Dental Services" GPRA numerator

  Scenario: Any other dental procedure code on a real visit counts
    Given a User Population patient "DA-REST" aged 30 at period start
    And "DA-REST" has RPMS dental code "D2391" recorded 2025-07-15
    When the National GPRA report is run
    Then "DA-REST" is in the "Access to Dental Services" GPRA numerator

  Scenario: A dental procedure code on a chart review does not count
    Given a User Population patient "DA-CHART" aged 30 at period start
    And "DA-CHART" has RPMS dental code "D2391" recorded 2025-07-15 on a chart review
    When the National GPRA report is run
    Then "DA-CHART" is in the "Access to Dental Services" GPRA denominator
    And "DA-CHART" is not in the "Access to Dental Services" GPRA numerator

  Scenario: A dental visit before the report period does not count
    Given a User Population patient "DA-OLD" aged 30 at period start
    And "DA-OLD" has RPMS dental code "0190" recorded 2024-11-20
    When the National GPRA report is run
    Then "DA-OLD" is not in the "Access to Dental Services" GPRA numerator

  Scenario: A non-beneficiary is outside every dental denominator
    Given an otherwise-qualifying patient "DA-NONBEN" aged 8 with beneficiary class "02"
    And "DA-NONBEN" has RPMS dental code "D1351" recorded 2025-03-12
    When the National GPRA report is run
    Then "DA-NONBEN" is not in the "Access to Dental Services" GPRA denominator
    And "DA-NONBEN" is not in the "Dental Sealants" GPRA denominator

  # -- 2.2.2 Dental Sealants ---------------------------------------------------

  Scenario: A sealant code during the report period is an intact sealant
    Given a User Population patient "DS-ADA" aged 8 at period start
    And "DS-ADA" has RPMS dental code "D1351" recorded 2025-03-12
    When the National GPRA report is run
    Then "DS-ADA" is in the "Dental Sealants" GPRA denominator
    And "DS-ADA" is in the "Dental Sealants" GPRA numerator

  Scenario: A sealant CPT during the report period is an intact sealant
    Given a User Population patient "DS-CPT" aged 8 at period start
    And "DS-CPT" has CPT "D1351" recorded 2025-03-12
    When the National GPRA report is run
    Then "DS-CPT" is in the "Dental Sealants" GPRA numerator

  Scenario: A sealant repair counts as an intact sealant
    Given a User Population patient "DS-REPAIR" aged 8 at period start
    And "DS-REPAIR" has RPMS dental code "D1353" recorded 2025-03-12
    When the National GPRA report is run
    Then "DS-REPAIR" is in the "Dental Sealants" GPRA numerator

  Scenario: Tracking code 0007 within three years of period end counts
    Given a User Population patient "DS-0007" aged 8 at period start
    And "DS-0007" has RPMS dental code "0007" recorded 2023-06-01
    When the National GPRA report is run
    Then "DS-0007" is in the "Dental Sealants" GPRA numerator

  Scenario: Tracking code 0007 more than three years before period end does not count
    Given a User Population patient "DS-0007OLD" aged 8 at period start
    And "DS-0007OLD" has RPMS dental code "0007" recorded 2022-06-01
    When the National GPRA report is run
    Then "DS-0007OLD" is not in the "Dental Sealants" GPRA numerator

  Scenario: Age is taken at period start, so a 15-year-old who turns 16 stays in
    Given a User Population patient "DS-AGE15" aged 15 at period start
    And a User Population patient "DS-AGE16" aged 16 at period start
    And a User Population patient "DS-AGE1" aged 1 at period start
    When the National GPRA report is run
    Then "DS-AGE15" is in the "Dental Sealants" GPRA denominator
    And "DS-AGE16" is not in the "Dental Sealants" GPRA denominator
    And "DS-AGE1" is not in the "Dental Sealants" GPRA denominator

  Scenario: A child with no sealant is a care gap
    Given a User Population patient "DS-NONE" aged 8 at period start
    And "DS-NONE" has no dental services during the report period
    When the National GPRA report is run
    Then "DS-NONE" is in the "Dental Sealants" GPRA denominator
    And "DS-NONE" is not in the "Dental Sealants" GPRA numerator

  # -- 2.2.3 Topical Fluoride --------------------------------------------------

  Scenario: A fluoride dental code counts
    Given a User Population patient "TF-ADA" aged 4 at period start
    And "TF-ADA" has RPMS dental code "D1206" recorded 2025-02-14
    When the National GPRA report is run
    Then "TF-ADA" is in the "Topical Fluoride" GPRA denominator
    And "TF-ADA" is in the "Topical Fluoride" GPRA numerator

  Scenario: The pre-CDT fluoride code TF hard-codes counts
    Given a User Population patient "TF-1354" aged 4 at period start
    And "TF-1354" has RPMS dental code "1354" recorded 2025-02-14
    When the National GPRA report is run
    Then "TF-1354" is in the "Topical Fluoride" GPRA numerator

  Scenario: A fluoride varnish CPT counts
    Given a User Population patient "TF-CPT" aged 4 at period start
    And "TF-CPT" has CPT "99188" recorded 2025-02-14
    When the National GPRA report is run
    Then "TF-CPT" is in the "Topical Fluoride" GPRA numerator

  Scenario: A fluoride POV counts
    Given a User Population patient "TF-POV" aged 4 at period start
    And "TF-POV" has a topical fluoride POV recorded 2025-02-14
    When the National GPRA report is run
    Then "TF-POV" is in the "Topical Fluoride" GPRA numerator

  Scenario: The fluoride denominator runs from age 1 to 15 at period start
    Given a User Population patient "TF-AGE1" aged 1 at period start
    And a User Population patient "TF-AGE16" aged 16 at period start
    When the National GPRA report is run
    Then "TF-AGE1" is in the "Topical Fluoride" GPRA denominator
    And "TF-AGE16" is not in the "Topical Fluoride" GPRA denominator

  Scenario: A sealant alone is not a fluoride application
    Given a User Population patient "TF-SEAL" aged 4 at period start
    And "TF-SEAL" has RPMS dental code "D1351" recorded 2025-02-14
    When the National GPRA report is run
    Then "TF-SEAL" is not in the "Topical Fluoride" GPRA numerator
