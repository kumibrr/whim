# GitHub release performance summary

Add a compact, automatically maintained Performance section to stable GitHub releases created from benchmark-enabled main ancestry. Show the five simulator median timings, each run's frozen CI-baseline percentage change when available, status, sample count, environment and an immutable raw-result link. Label the optimized development simulator configuration explicitly.

Use the immutable tag's original source, not the release branch's generated version metadata or current main. A measured main ancestor is equivalent only when its source tree matches after excluding the existing narrow benchmark-data allowlist. Prefer the closest equivalent source and its latest observation. Revalidate the selected observation against its frozen policy; failed/incomplete results must not look successful, and absence produces a pending message rather than unrelated timings.

The existing release-preparation Action adds the section when a release is published or preparation resumes. Its existing main-push trigger also receives history appends from Xcode Cloud, so late results replace pending text. Benchmark execution remains entirely in Xcode Cloud. Reuse the Action's existing GitHub contents-write credential; never provide credentials to measurement jobs.

Only replace a uniquely marked managed section. Preserve all other release text, skip drafts/prereleases/unsafe tags and pre-benchmark releases, never create releases or move tags, and avoid API writes when content is unchanged. Malformed managed markers and publication errors fail visibly and remain retryable.

Alternatives considered: a one-time release-event snapshot cannot fill in asynchronously arriving results; linking only to history does not provide the requested small statistics. Reuse the existing Action's release and main-push triggers for one report publisher. Adding a second publisher to the Cloud collector would duplicate writes and introduce an unnecessary dependency into working collection.

Ruling: the user's full-auto instruction delegates these routine scope and implementation choices; no additional design approval is required. No comparison to a different environment or previous release is invented.

Ruling after code inspection: release preparation already listens to every main push. Use that trigger for late results instead of changing the collector; this keeps native measurement and collection entirely in Cloud and avoids competing summary writers. The reporting step also runs after a preparation failure, since trustworthy reporting does not require version preparation to succeed.
