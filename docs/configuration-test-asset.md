# Configuration-test recording

The product owner supplied the recording in response to the request for an approved, non-sensitive v1 webhook-test asset on 2026-09-21.

The source was a 2.890229-second mono Apple Lossless `.m4a`. It was converted to mono AAC at approximately 32 kbit/s without trimming. The normalized asset retains the 48 kHz sample rate and the same duration. No transcription or audio content was added to logs or documentation.

Canonical approved asset: `src/iphone/webhook-configuration/configuration-test.m4a`.

Runtime copy: `packages/WhimCore/Sources/WhimCore/WebhookConfiguration/Fixtures/configuration-test-fixture.m4a`.

Both normalized files have SHA-256:

```text
4fd26e531c8cb93d024b0ece4b1fd112a1134520eb28a9a29874f60f6249404c
```

The release fixture gate requires these files to match. The configuration test sends this recording only to the webhook selected by the user, with `event: "configuration.test"`, and does not create a Note in local history.
