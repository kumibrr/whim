# Development policy

- Build every behavior change as a vertical test-driven slice: identify the use case and public seam, add or update its failing companion test, implement the minimum behavior, then run the affected suite.
- Add a regression test that reproduces every bug before fixing it.
- Test behavior through the agreed interfaces in the v1 design specification. Mock system boundaries; use real owned modules together in integration tests.
- Keep the root `test:unit`, `test:integration`, and `test:e2e` scripts runnable throughout development. Run `test:all` before declaring a change complete.
- Put each assertion in the lowest suite that proves the behavior. Add or update E2E coverage when a complete user journey changes; avoid repeating identical assertions across suites.
- Treat unautomatable Apple hardware behavior as a physical acceptance case and add the closest deterministic automated regression coverage.
- Read `CONTEXT.md` for canonical domain terms and `docs/superpowers/specs/2026-09-04-whim-v1-design.md` for v1 behavior and test seams.
