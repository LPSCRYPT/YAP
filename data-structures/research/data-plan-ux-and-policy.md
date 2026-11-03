# Data Plan — configurable privacy, placement, transfer, and retention

Written: 2026-11-03. Status: proposed YAP product/architecture design, not implemented functionality or an audited privacy guarantee. This develops the discussion of evidence-first storage, regular audio purging, and explicit transfer. It is a recommendation, not a claim about the reference projects.

## Product abstraction

Expose a first-class **Data Plan** in both the mobile app and the server UI. It is the human-readable view of one versioned policy, not a collection of independent toggles that can contradict each other. A plan determines where data is processed, which artifacts can move to named destinations, how each copy is stored/retained, and what actions require approval.

Keep workflow definition, execution placement, transfer authorization, retention, and action authorization separate internally. Present their effective combination coherently in the UI.

## Primary screen

Show the active plan name, whether all participating nodes have applied its revision, and a simple map of device/phone/server/optional provider connections. Each connection names the artifact types permitted across it, not merely the transport protocol. Each node shows its processing roles and retained data categories.

Example plan: pendant audio to phone; transcription on phone; transcripts to a named personal server; enrichment/indexing on server; external providers disabled. Audio retention example of seven days is illustrative, not a decided default.

Use explicit text and icons as well as color. Distinguish enabled, blocked, queued, offline, awaiting approval, and deletion-pending states. Never display a green 'private' indicator merely because a destination is self-hosted.

The main controls should answer:

- Where does transcription run?
- Where do enrichment, embeddings, retrieval, and agents run?
- Which data goes to which named destination?
- What is kept on each node, and for how long?
- What happens if processing or transfer fails before an expiry deadline?
- Which external actions are permitted?

## Presets and progressive disclosure

Offer a small number of presets plus Custom:

1. Phone only, subject to available on-device capabilities.
2. Phone transcription + personal server enrichment.
3. Phone relay + personal server transcription (explicit audio upload).

An external model/provider should be a separately reviewed opt-in, not an innocently named 'better quality' switch. Presets populate the same policy model as custom editing. They do not hide exceptions or grant unused routes. If the hardware cannot implement a preset, explain which capability is missing rather than silently changing it.

Use ordinary controls (destination picker, on/off route, retention duration, processing-location selector). A read-only generated map is more understandable initially than a general-purpose workflow canvas. Expert model/prompt/schema controls can be separate from everyday privacy choices.

## Policy dimensions

- **Placement:** processor contract, implementation/model, executing node, declared inputs/outputs.
- **Transfer:** source node, destination identity, artifact type, purpose, scope, permission state, expiry, conditions such as Wi-Fi-only. Connectivity preferences never grant data permission.
- **Retention:** artifact category, node/copy scope, duration, expiry anchor, strict expiry or bounded grace, applicable holds, and deletion behavior.
- **Storage:** encryption-at-rest capability/status, key custody, backup/cache coverage, and storage location. Do not imply that server-side model execution is end-to-end encrypted from the server operator.
- **Actions:** tool/destination scope, approval requirements, and stable execution identity.
- **Policy metadata:** plan ID/revision, authorizing principal, paired nodes, proposed/approved/applied status, node acknowledgements, and effective capabilities.

Raw audio, transcripts, enriched notes/assertions, embeddings/indexes, speaker identity/voiceprints, and diagnostics are distinct data categories. Embeddings and logs can contain sensitive information; they are not exempt from transfer/deletion rules. Do not allocate UI controls to voiceprints as though identity matching is already implemented.

## Enforcement, not just UI

Both app and server edit/propose the same policy format. Enforcement is local to each node at processing, transfer, and action boundaries; the phone does not trust a server request as permission to upload audio. A receiver also authenticates and authorizes incoming artifacts. Plugins use governed storage/transport interfaces; remote model calls are explicit data egress, not hidden implementation details.

Use explicit versioned policy updates and authenticated control channels bound to known node identities. Expanding permissions (new external destination, raw-audio transfer, longer retention, new biometric processing) requires user approval. A server-side edit cannot silently broaden the phone's existing consent. Endpoint or identity changes require review.

A node may tighten its local policy. A broader policy becomes effective only after required authorization and node acknowledgement. Show partial application; do not claim a global setting is active when a phone/server is offline. Re-evaluate queued work against the current effective policy immediately before execution. Cancelling permission stops unsent work but cannot recall data already sent.

Do not promise instantaneous global revocation of an offline node. Decide whether sensitive grants need expiring leases; document the resulting offline usability tradeoff before implementation. Policy mismatch should block newly unauthorized work, not trigger a permissive fallback.

Start with static step placement and registered adapters, not automatic workload migration or a distributed policy platform.

## Change preview and receipts

Before applying an edit, summarize the delta in plain language:

- Which new data will leave which node?
- Which destination/model gains access?
- Does the change apply only to new recordings or also an existing backlog?
- Does it shorten/extend retention of existing copies?
- Is deletion requested, and which nodes can confirm it?
- What functionality becomes unavailable?

Changing a setting from now on must not silently upload the existing library. Retroactive export is a separately scoped action. Requesting deletion of existing data is also distinct from disabling future sync.

Show an activity/history view with artifact ID, processor/model, execution node, source revision, permitted transfer, destination acknowledgement, and deletion outcome. Keep this metadata minimal: an audit log should not become a second indefinite transcript store.

## Retention and purge UX

For each data class/node show the retention rule, age anchor (for example capture time), next scheduled purge, current retained size, and exceptions. Distinguish scheduled deletion, completed local deletion, remote deletion requested, remote deletion confirmed, offline/pending, and provider-unverified.

A strict expiry deadline remains binding when ASR or sync fails. Warn about pending unprocessed recordings without quietly extending their lifetime. A bounded retry grace must be an explicit choice with a visible deadline. Do not use successful server sync as an implicit reason to retain raw audio indefinitely.

If audio is also retained on the pendant, it needs its own supported deletion/overwrite policy. Phone deletion does not prove pendant deletion. Account for scratch files, upload queues, backups, thumbnails/derived artifacts, and caches where relevant. 'Delete everywhere' must report coverage and exceptions rather than assert universal completion.

Deleting audio can leave a permitted transcript and source-availability marker. Deleting a conversation's semantic content requires cascading invalidation/purge of its extracted claims, graph/vector entries, summaries, and caches under the chosen policy. Retained backup copies must have explicit expiry and restore-time deletion handling.

External provider deletion/training/retention claims are third-party guarantees, not locally enforceable facts. Display that distinction.

## Per-recording inspection

Provide a compact 'Data trail' for each recording: where audio exists, which node produced the transcript, where transcripts/derived artifacts were sent, what remains retained, and available deletion actions. Cite actual processing/transfer receipts rather than only showing intended configuration.

Useful controls: Pause outgoing sync, Process locally, one-time authorized transfer, Delete audio now, and Manage retained copies. Pausing outgoing sync must not silently pause capture or local transcription; describe its scope.

## Open questions

- Is the plan owned by one account, one device, or a workspace? How are shared recordings and administrators governed?
- Which permissions require phone-local confirmation versus approval from another authenticated account client?
- What is the initial audio-retention duration and expiry anchor?
- What happens at strict expiry when no usable transcript exists?
- Which pendant firmware can report/confirm local audio removal?
- What backup, cache, and model-provider deletion capabilities can actually be verified?
- Which capability and policy states should be visible on the main screen versus advanced settings?

## Initial implementation slice

Start with one Data Plan screen, three presets, explicit node/provider registration, per-artifact transfer permissions, configurable audio expiry, a change preview, and an applied-policy/activity view. Use the same underlying contracts for mobile/server editing. Add policy tests for forbidden egress, expired audio, offline policy mismatch, queued work after revocation, and duplicate actions before enabling automatic execution. This is a proposed implementation scope, not work performed in this research change.
