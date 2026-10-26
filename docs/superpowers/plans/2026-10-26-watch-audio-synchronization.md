# Watch Audio Synchronization Implementation Plan

**Goal:** Make pending Watch audio visible and recoverable with three total transfers per cycle, manual synchronization retry and deletion.

**Spec:** `docs/superpowers/specs/2026-10-26-watch-audio-synchronization-design.md`

**Architecture:** Add persisted synchronization state to metadata-only Notes. Extend the peer protocol with correlated audio requests; keep file validation, durability, replay and tombstones behind the existing WhimCore interfaces.

## Constraints

- Audio Synchronization never changes an existing Delivery Receipt.
- Missing local audio cannot start playback, enrichment, Delivery or retention.
- Each behavior uses a failing companion test before implementation.
- Keep root test scripts runnable; finish with `npm run test:all`.

## Slices

- [x] Metadata visibility: add a cross-device integration regression; persist pending Notes and expose their state in projections; exclude them from processing and recovery errors.
- [x] Bounded repair: add correlated request/response integration tests, then implement three total transfers, restart/duplicate safety and source retention.
- [x] User recovery: test WhimService Retry/Delete and iPhone formatting/detail commands, then show synchronization labels, actions and Failed filtering.
- [x] Installed application: extend DEBUG peer scenarios and Maestro coverage for waiting, exhaustion, manual repair and removal; update physical acceptance.
- [x] Independently review the change, run affected checks and the full local suite, and report any remaining limitations.

Verification: `npm run test:all` passed locally using temporary cache/Java overrides: unit and integration suites, 18 iPhone Maestro flows, and 18 Watch UI tests. Physical paired-device acceptance remains unrun.

## UI refinements requested after screenshot review

- Show synchronization failure in the card status position, replacing the Delivery label.
- Keep synchronization retry in Note details as a circular Liquid Glass icon; preserve its accessible action label.
- Confirm Note deletion with a native alert and verify cancellation preserves the Note.
- Extend the installed-app regressions, run `test:all`, and capture fresh simulator screenshots.

UI refinement verification: `npm run test:all` passed on 2026-10-26, including all 18 iPhone Maestro journeys and all 18 Watch UI tests (zero failures or skips). The status-placement and sync-only bulk-retry regressions failed before their fixes. Fresh simulator screenshots verify the detail Liquid Glass retry icon and native delete alert.

## Note detail ordering and retry rows

- Remove the standalone transfer-count error and use a smaller glass icon beside Retry sync.
- Persist a row for each requested audio resend, atomically with its synchronization-state transition. Keep rows across restart, manual retry and successful repair.
- Show those rows under Delivery details with clear waiting, failed, superseded and synced outcomes.
- Verify the installed-app journey and full suite, then capture updated details.

Retry-history verification: `npm run test:all` passed on 2026-10-26, including 18/18 iPhone Maestro journeys and 18/18 Watch UI tests with no failures or skips. The label, missing retry rows, and persisted-history regressions failed before implementation and passed afterward. A focused read-only review found no actionable issues. The user confirmed retaining full sync history. Updated failed and repaired detail screens were captured from the compiled simulator build.
