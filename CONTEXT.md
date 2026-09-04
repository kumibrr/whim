# Whim

Whim captures voice notes on iPhone and Apple Watch, enriches them locally, and delivers them to a user-controlled workflow while preserving recoverability.

## Language

**Note**:
One finalized audio recording and its metadata, identified by an immutable note ID.
_Avoid_: Voice memo, clip

**Recording Session**:
An active, unfinished audio capture that has not yet become a Note.
_Avoid_: Note, recording

**Workflow**:
The post-capture behavior assigned to a Note. Whim v1 has one built-in Workflow.
_Avoid_: Automation, pipeline

**Step**:
One named behavior in a Workflow.
_Avoid_: Task, action, job

**Delivery**:
The logical requirement to submit one Note to its Workflow destination.
_Avoid_: Upload, request

**Attempt**:
One device's HTTP request made toward satisfying a Delivery. A Delivery may have multiple sequential or concurrent Attempts.
_Avoid_: Delivery, retry

**Receipt**:
Evidence that an Attempt received a successful HTTP response from the Workflow destination.
_Avoid_: Response, result

**Configuration Revision**:
A non-secret identifier for the webhook configuration used by an Attempt.
_Avoid_: Configuration snapshot

**Retention Policy**:
The period after successful Delivery before Whim removes a Note's local audio.
_Avoid_: Expiration, history policy
