# Note detail layout implementation plan

## Approved outcome

Reuse the glass voice-note card from history at the top of iPhone Note detail, including its waveform player, title, date, duration, source, and status. Place additional information below the card. Remove the “Whim” navigation title. Move Delete to an icon-only glass toolbar button on the right, with a red trash icon matching the native Back button treatment.

Preserve delivery and recovery behavior: playback never authorizes sending a recovered Note; Send remains explicit; deleting a sent Note is immediate, while other Notes require the existing confirmation. Preserve error handling, missing-audio states, pending-action protection, and playback cleanup when leaving detail.

## Implementation sequence

Implement each behavior as a vertical test-driven slice: add a failing companion test, verify the intended failure, make the smallest production change, and run the affected suite before proceeding.

### 1. Provide waveform playback state in detail

- Extend `src/iphone/note-detail/NoteDetailModel.integration.test.swift` using the real service and store, with playback and waveform adapters as system-boundary fakes.
- Prove that detail exposes the selected Note's waveform and playback progress, updates play/stop state, and clears or ignores stale state when the Note or local audio disappears. Cover delayed waveform completion if loading is asynchronous.
- Extend `NoteDetailModel.swift` to supply the state needed by the existing card through `WhimClient.waveform(noteID:)` and `playbackSnapshot()`. Avoid repeated waveform extraction in the existing 500 ms refresh loop. Retain refresh-generation protection and stop-on-disappear behavior.
- Run the iPhone integration suite with `swift test --filter WhimIPhoneIntegrationTests`.

### 2. Reuse the history card in detail

- Update `e2e/iphone/record-and-review.e2e.test.yaml` to expect the card player in detail and delivery information below it; verify the new expectations fail against the old screen.
- Adapt `src/iphone/timeline/NoteRowView.swift` so its shared card can render static metadata in detail and tappable metadata in history. Do not leave a no-op “Open” button on the detail screen.
- Reuse the card in `NoteDetailView.swift`, mapping the detail projection into its presentation inputs without changing the canonical domain or client interface.
- Keep title/date/source/duration/status inside the card. Place local error explanations, recovery instructions and Send, applicable Retry actions, and Attempt details below it. Ensure Retry is offered only once on detail.
- Preserve the card's Dynamic Type layout and disabled player for expired or unavailable audio. Retain accessible playback names and stable identifiers.
- Run the affected record-and-review journey and history navigation journey to check both consumers of the shared view.

### 3. Move deletion into the toolbar

- Extend the detail journey to locate Delete in the navigation toolbar, verify the “Whim” title is absent, cancel an unsent deletion, then confirm deletion and return to history.
- Remove `.navigationTitle("Whim")` from detail and use an empty inline title so no large title space remains.
- Add a trailing toolbar trash button with red accent, an accessible “Delete Note” label, and a stable `note-delete` identifier. Use the native toolbar button style to match Back on Liquid Glass systems; visually check supported older-system appearance.
- Remove the body Delete button. Apply pending-action disabling to the toolbar item explicitly and hide it when the Note is unavailable.
- Keep the existing deletion decision and confirmation sheet. Verify sent deletion remains immediate using the existing delivery journey, extending it only where needed.
- Run the affected deletion journeys.

### 4. Verify recovery and presentation

- Update `e2e/iphone/recovered-review.e2e.test.yaml` to use the shared player while retaining its assertions that playback causes no Delivery and explicit Send delivers once. Adjust any other detail journeys still targeting the removed text player.
- Run the recovered journey after its selector updates; rely on integration coverage for state edge cases rather than duplicate all assertions in E2E.
- Inspect the screen in the simulator: card at the top, extra information below, empty toolbar center, Back left, red trash right, and visible confirmation UI. Check large accessibility text sizes and Reduce Transparency.
- Update `e2e/physical/iphone-presentation.e2e.test.md` with any visual acceptance checks requiring physical iPhone verification, especially glass appearance. Record actual verification separately from unperformed physical checks.
- Run `npm run test:all` before declaring the change complete. This includes test colocation, unit, integration, iPhone E2E, and Watch E2E checks. Report any environmental blockers or failing suites explicitly.

## Completion criteria

- History and detail render the same voice-note card and functional waveform player.
- Additional Note information is below the card without duplicate metadata or Retry controls.
- Detail has no “Whim” heading and has an accessible red-accented glass Delete button at the right of the toolbar.
- Recovery, deletion confirmation, unavailable audio, and navigation playback cleanup retain their existing semantics.
- Required automated checks pass; visual and physical checks are reported accurately.

## Implementation and verification record

Implemented on 2026-09-20. Detail now reuses the history card through shared presentation inputs, with static metadata, waveform playback, additional information below, an empty inline navigation title, and a trailing red native toolbar Delete button. Existing deletion and recovered-Note behavior are retained.

- New detail integration tests failed on absent waveform/playback state before implementation; all 29 iPhone integration tests then passed.
- The shared-player journey failed against the old detail UI and passed after card reuse. Toolbar placement, absent heading, and cancel/confirm deletion assertions passed in the full iPhone run.
- `npm run test:all` was run. Unit, integration, and eight of nine iPhone E2E journeys passed after restarting simulator test runners with stale sockets. `cold-links.e2e.test` failed while opening settings from a terminated app, then passed unchanged on a targeted rerun. The aggregate command therefore did not finish green.
- `npm run test:e2e:watch` subsequently passed separately, since the failed iPhone flow had stopped the aggregate command before its Watch E2E stage.
- A separate iOS 18.6 simulator journey passed. Screenshots were inspected at default and largest accessibility text sizes; a modern-system screenshot confirmed matching glass Back/Delete buttons with a red trash icon.
- Final code review found no actionable issues. Physical-device acceptance and Reduce Transparency visual checks remain pending in the physical presentation case.
