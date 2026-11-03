# YAP — data structures and post-transcription synthesis

Written: 2026-11-03. Status: design recommendations and open questions, not implemented contracts or a final database selection. Evidence for project comparisons is in the neighboring project notes.

## Main recommendation

Use a temporal knowledge graph as the initial knowledge projection, not as the only authoritative representation. Keep source evidence, extracted interpretations, and retrieval projections distinct:

1. **Evidence:** versioned recordings, transcripts, segments, and source availability.
2. **Interpretations:** evidence-backed assertions, identity links, summaries, events, and action proposals.
3. **Projections:** temporal graph, full-text search, semantic indexes, timelines, and task views.

A graph is useful for relationship/time questions; it should not replace transcript retrieval for exact words, numbers, or facts that extraction missed. A workflow that does not need a graph should still work.

## What to borrow from each reference

| Reference | Useful lesson | Important limit |
| --- | --- | --- |
| OpenPendant | Local clip/segment storage, raw versus refined text, day/meeting recaps, follow-up UX | Inspected enrichment/chat uses external providers; Mem0 client usage does not prove temporal graph construction |
| Omi | Evidence-linked canonical memory, revisions, validity, graph projections, authoritative hydration after index retrieval | Large evolving system; source contracts and deployment activation are distinct |
| Boswell | Inspectable source artifacts, extracted structured records, multiple rebuildable local retrieval indexes | No general temporal graph established; optional cloud adapters change privacy boundaries |
| memrii | Capture-independent export contract, timestamp uncertainty, explicit per-destination grants | Audio archive/export, not a native transcription or memory backend |
| Plaud | Recording/transcript/note artifacts, source-linked outputs, tool-facing access | Proprietary processing/index internals; sync-off is not local processing |
| Limitless | Time-bounded nested Lifelogs, hybrid search and structured exports | Cloud-dependent; commercial availability and data policies changed |
| AudioMoth/MicroMoth | Local audio capture and recording-level provenance | Not an ASR, speaker-identity, or knowledge-processing stack |
| Graphiti | Episode/entity/fact modeling and temporal hybrid retrieval | Optional framework; tenancy, governance, operations, and evaluation remain application responsibilities |

## Logical data contracts

These are responsibilities, not a mandatory table layout or frozen schema.

### Recording

Stable recording identity; device/session identity; capture start/end; clock basis and uncertainty; media format; payload location/hash; retention and access state. Upload time must not replace capture time. Unknown or corrected device time must be representable.

### Transcript revision

Recording/source references, language, ASR processor/model/configuration version, revision identity, and whether the result is original ASR or a correction. ASR output is evidence of what a model heard, not unquestionable truth about what a speaker said. Keep original and corrected versions distinguishable.

### Segment / utterance

Text, relative media offsets, capture-time mapping, transcript revision, recording-scoped speaker label, and optional word alignment. A conversational episode can group segments across files without destroying their recording identities. A later transcription may split or merge segments; segment IDs must therefore be interpreted within a revision.

### Entity and identity link

People, organizations, projects, places, aliases, tentative matches, and merge/split history. A diarizer's `speaker_1` is not a persistent person ID. Distinguish an audible speaker, a person named in speech, and the recorder owner. Keep unresolved identities instead of guessing.

### Assertion

Subject, predicate, object/value, attribution, polarity, modality, temporal applicability, lifecycle, evidence, and extraction provenance. Store claims rather than immediately declaring model output to be ground truth.

For example, "Alex said they will join Acme next month" supports a reported future plan. It does not establish that Alex currently works at Acme. A quote, a hypothesis, a negation, a promise, and an observed event must not collapse into the same edge.

Confidence should identify what it measures (ASR quality, attribution, extraction, entity match), not present one arbitrary LLM score as a calibrated probability of truth.

### Evidence reference

Exact transcript revision and segment/span, optional audio offsets, source lineage, access policy, and availability/redaction state. A reference to remote or expired audio is not a promise that it can be fetched. Copies of the same audio, or repeated extraction passes, are not independent corroboration.

### Processing run

Input artifact revisions, processor/model/prompt/schema/configuration versions, execution node, status, outputs, and invalidation lineage. Reprocessing should create traceable new outputs, not overwrite evidence silently.

### Projection version

Projection implementation/version, source revisions, indexing/rebuild checkpoint, and freshness state. Vector hits and graph matches should resolve to authorized current source records before answering. Deleted or restricted material must not leak through stale indexes.

### Action proposal and execution

Extracted task/event candidate, source evidence, authorization scope, approval decision, stable execution identity, and result. A conversational mention is not execution permission. Replayed synchronization or re-extraction must not duplicate an external action.

## Temporal semantics

Use explicit distinctions:

- **Valid time:** when a claim applies in the world.
- **System/knowledge time:** when YAP recorded a claim or revision.
- **Observation time:** when the evidence was captured.

Example: on November 3, a person says they joined Acme on October 1. YAP learns the claim on November 3; its asserted start is October 1. On November 5, the person corrects the start to October 3. Preserve enough history to answer both the latest question and "what did YAP believe on November 4?"

This calls for bitemporal assertion history with observation provenance. It does not mean every record needs invented precise intervals. Unknown dates, approximate dates, time zones, future plans, and open bounds must remain distinguishable.

Do not use the recording date as an implicit validity start. Do not automatically supersede every old relation with the same predicate: multiple employers, residences, preferences, or interpretations can coexist. Define which predicates are single-valued, and under what scope, before applying closure rules.

History preservation is subordinate to privacy deletion. "Append-only" must never mean a user cannot purge sensitive content or its derived copies.

## Proposed post-transcription pipeline

1. **Validate and preserve input.** Accept a typed transcript artifact from any authorized execution node; normalize schema/units without losing its original revision and provenance. Do not require audio upload when the workflow receives a transcript.
2. **Add speech annotations where available.** Alignment, diarization, speaker identification, and acoustic context are separate processor outputs. Many require audio. If raw audio stays on the phone, run those steps there or explicitly mark them unavailable; do not infer voice identity from text alone.
3. **Group contextual episodes.** Associate speech into conversations/meetings using timing and available evidence. Preserve segment references and handle late/out-of-order uploads. Concurrent recordings are not automatically the same conversation.
4. **Run independent semantic processors.** Produce summaries, entity mentions, assertion candidates, events, and action proposals. Do not require extracting assertions from summaries: summaries are lossy and can omit the exact detail needed for retrieval.
5. **Resolve and reconcile.** Resolve identities cautiously; detect duplicates/conflicts; preserve uncertain matches; distinguish user corrections from automatic reinterpretations. Apply validated changes through an authoritative mutation boundary.
6. **Update projections.** Build the selected temporal graph, search, timeline, and task views from versioned outputs. Source correction, permission changes, and deletion must invalidate affected projections.
7. **Retrieve and authorize.** Use keyword/time filters, semantic search, or graph traversal as appropriate, then retrieve source evidence and apply access policy. Tool execution remains separately authorized.

These processors are logical roles. Placement is an execution-profile concern: the phone can transcribe and annotate while a server enriches and indexes, or a capable node can host more of the pipeline locally. Unavailable steps must not trigger unauthorized audio upload or provider substitution.

## Initial implementation direction — not selected yet

- Phone: SQLite metadata and local artifact files.
- Server: PostgreSQL for artifact metadata, evidence, assertions, and processing state; filesystem/object storage for large payloads.
- Retrieval: full-text search plus optional embeddings; keep indexes rebuildable from retained artifacts.
- Temporal graph: start with explicit entity/assertion semantics; relational tables can represent these before a dedicated graph engine is warranted.
- Evaluate Graphiti as an adapter against the same evidence and query contracts, rather than adopting its internal schema as the app API.

This is a conservative operating baseline, not a decision that SQL must be the only backend or that graph databases are unnecessary. Select graph technology based on actual traversal/query needs, lifecycle semantics, cost, and deployment constraints.

## Questions to resolve before freezing schemas

1. What exact questions should the first temporal graph answer better than full-text/vector retrieval?
2. Which initial entities and predicates are allowed? Which are single-valued over time?
3. Do assertions require human review, or only sensitive/ambiguous ones? How are user corrections protected from re-extraction?
4. What is the representation of uncertain event time, hearsay, hypotheses, negation, and future intent?
5. What identities and version tokens synchronize between phone and server? How do independently created corrections reconcile?
6. What audio/transcript retention defaults apply, and how are unavailable sources represented?
7. Where do diarization and identity matching run, and are voiceprints permitted/stored at all?
8. How do deletion and access revocation propagate to graph edges, vectors, summaries, caches, and agent context?
9. Which processor contracts are shared core types, and which belong to a graph-oriented plugin ontology?
10. What is the cost/latency/energy budget for phone transcription and repeated server enrichment?

## Evaluation scenarios to design later

No benchmark was run during this research. Useful future cases include:

- Exact-quote retrieval that a summary omitted.
- A fact learned today but valid from an earlier date.
- A later correction to an earlier claim.
- Conflicting assertions from two speakers, without silently picking one as truth.
- Two simultaneous valid relationships with the same predicate.
- Speculative/future speech that must not become a current fact or executed task.
- ASR mistakes followed by user correction and projection rebuild.
- The same recording arriving twice or through two devices, without inflated corroboration.
- Deleted or access-revoked source material remaining in a stale index.
- Phone-produced transcript with unavailable audio, partial speaker metadata, and delayed synchronization.

Compare retrieval quality and evidence correctness across transcript-only, vector, graph, and hybrid configurations before making the temporal graph mandatory in any profile.
