# Background maintenance acceptance

Status: pending paired physical iPhone and Apple Watch.

- Configure the controlled webhook, capture on each device, and return to the Home Screen/watch face before delivery completes. Verify eventual delivery while the app remains in the background.
- Return retryable failures: verify no retry before one minute, then fifteen minutes, and no automatic request after three failures. OS launches may occur later than these earliest eligible times.
- Keep a Whim complication on the active watch face. Verify a scheduled Watch refresh resumes eligible work and completes within its execution budget.
- Expire an active background task during upload. Verify its next launch recovers the saved Attempt without an overlapping upload or stuck lease.
- Use Immediately retention, receive a successful delivery, and verify local audio disappears while title/history remain. For time-based retention, verify a background wake after the Receipt deadline performs cleanup.
- Reset with pending background work and a delivered failure notification. Verify notifications disappear, old work never uploads, and a stale Watch refresh completes without restoring erased state.
- Disable Background App Refresh on iPhone. Verify recording, foreground delivery, and retention settings still work.

Deterministic companions: MaintenanceService.integration.test.swift covers deadlines and exclusions; WhimService.integration.test.swift covers expiry, cancellation, Reset, peer Reset, and lease recovery. Native registration metadata is checked by scripts/verify-system-surfaces.py. OS scheduling budgets and physical lock behavior are not simulated by those tests.
