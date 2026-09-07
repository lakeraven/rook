# ADR 0001: Measure specifications and parity artifacts are open by design

**Status:** Accepted
**Date:** 2026-09-07

## Context

Rook recreates IHS CRS: it re-encodes GPRA/GPRAMA measure logic from the
published CRS measure-definition documents and the FOIA-released BGP M source,
as evidence-pinned dossiers (`docs/measures/`), executable Gherkin parity
features (`features/parity/`), FHIR terminology artifacts
(`lib/rook/terminology/`), and — as the parity harness (#99) matures —
recorded golden-master outputs from real CRS runs.

These artifacts distill months of archaeology: population-base subtleties,
M-verified behaviors the prose spec omits (missing-A1c handling, same-day
tie-breaks), taxonomy joins. GPRA fidelity is a competitive moat for the
project's stewards, which raises the question this ADR answers: should the
distilled encoding be public, or held back?

## Decision

**The specification and verification layer is open, permanently:** dossiers,
evidence extracts and locks, Gherkin parity features, the seed vocabulary,
terminology CodeSystems/ValueSets, the harness code, and recorded golden
masters (synthetic populations only). All of it lives in this public
repository under its open license.

What is *not* open is not in this repository at all: per-tenant manifests and
configuration, client-specific adapters, credentials, and the operational
infrastructure the parity oracle runs on. That boundary is enforced by the
existing private-implementation rules, not by this ADR.

## Rationale

1. **The ingredients are already public.** The CRS measure definitions are
   public IHS documents; the BGP M source is FOIA-released. The encoding is
   translation and verification of public material — closing it would buy
   months of competitor delay at most, while costing everything below.

2. **A spec is worth more as a standard than as a secret.** If these features
   become the community's reference for "what CRS actually computes" —
   reviewable by GPRA coordinators without reading M — then other
   implementations end up validating against *this* encoding. Value migrates
   from possessing the logic to being the implementation whose execution of it
   is verified. Openness is how a spec captures that seat.

3. **Openness is load-bearing for trust.** Rook exists for health programs
   whose operators are choosing transparency and sovereignty over opaque
   vendors. An inspectable measure spec — versus 6.2M lines of closed M — is
   the product argument. Closing the spec layer would contradict the reason to
   adopt the engine at all.

4. **The durable moat is elsewhere and is strengthened, not weakened, by open
   specs:** the running legacy oracle and the ability to cheaply *re-record*
   golden masters against every new CRS release; the engine that actually
   passes the suite; and the annual cadence — each CRS release resets the
   verification clock in favor of whoever holds the oracle infrastructure. A
   copy of the feature files conforms to this spec; it does not replicate the
   capacity to keep it true.

5. **The visible gotchas are the proof of work.** Publishing the M-verified
   subtleties hands a fast follower real value — and simultaneously shows
   every evaluator who did the archaeology and how each claim traces to
   pinned evidence.

## Consequences

- Dossiers, parity features, evidence locks, terminology artifacts, and golden
  masters are written to publication standard: synthetic data only, public
  sources cited, no partner/tenant identifiers — the existing public-repo
  hygiene rules apply with no exceptions for "internal-looking" artifacts.
- Golden masters recorded from real CRS runs are committed here (they derive
  from FOIA software over synthetic populations). The recording
  infrastructure and its environments stay operational concerns outside this
  repo.
- External implementations are welcome to run the conformance and parity
  suites against themselves; divergence tagging (`@divergence`) and the
  evidence-lint rules apply to contributions equally.
- Do not accept contributions that would move tenant-specific or
  source-restricted material into this layer; the open boundary is the repo
  boundary.
