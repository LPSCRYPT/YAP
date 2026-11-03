# Omi — data architecture research

Researched: 2026-11-03.

Evidence: public documentation and source inspection, not an authenticated service test or deployment audit. The observed `main` revision was [`d673bb46deb51ae137411323e0ecf1b509fcc2f3`](https://github.com/BasedHardware/omi/commit/d673bb46deb51ae137411323e0ecf1b509fcc2f3), committed 2026-11-03. Reads used moving `main` URLs; the revision records the repository snapshot observed during research, not a guarantee that every fetch was atomic against that commit.

## Important correction to the earlier discussion

The earlier description of Omi as conversations + short memories + summary vectors was incomplete for the current source. It also contains canonical memory records, evidence contracts, graph assertions/nodes/edges, temporal validity fields, and transcript-chunk vector retrieval.

Do not repeat the older blanket claims that Omi only embeds summaries, has no graph layer, or never updates derived indexes. Current code has multiple index namespaces and lifecycle/projection machinery. Presence of those implementations does not prove their activation in every production account.

## Recording and conversation artifacts

[Storing conversations documentation](https://github.com/BasedHardware/omi/blob/main/backend/docs/storing-conversations.md) describes:

- Conversation ID, creation time, actual start/end time, source, language, and processing status.
- Transcript segments with text, relative start/end offsets, speaker label, owner attribution, and optional person ID.
- Structured title, overview, category, action items, and calendar events.
- Optional audio references, photographs, location, app results, visibility, and protection level.
- Action items both inline and in a standalone collection, with completion and due-date state.
- Separate source recording and generated outputs: a recording can remain accessible even when generated notes or memories are absent.

Offline arrivals are associated using capture intervals rather than upload completion. Document-size boundaries split at transcript segments. Capture groups can associate simultaneous recordings while retaining originals; coincident timestamps alone are not evidence of shared speech.

The same document still presents a historical dual-collection view of `conversations` and `memories`. This is useful for the conceptual distinction but insufficient as a complete current schema inventory.

### Local summaries and canonical output

The documentation describes display-only `client_processing` projections for desktop reads. Transcript hashes and revisions control freshness; projected action items are not automatically canonical tasks. This is an important distinction for YAP's phone/server split: a locally generated interpretation must identify its source revision, and presentation-level merging must not silently confer authoritative identity or execution permission.

## Canonical memory contract

Source: [`backend/models/product_memory.py`](https://github.com/BasedHardware/omi/blob/main/backend/models/product_memory.py).

`MemoryItem` includes:

- Identity: memory/account/canonical IDs, version, item revision, content hash.
- Lifecycle: active, superseded, hidden, tombstoned; processing state; short-term/long-term/archive compatibility layers; expiration.
- Provenance: evidence, source state, capture-device IDs, capture/update times, source commit and ledger commit/sequence.
- Interpretation: content, subject entity, predicate, arguments, confidence, corroboration metadata, supersession target.
- Temporal/semantic fields: `valid_from`, `valid_to`, subject scope, fact/document/trigger kind, slot, write reason, and whether a record is intent-backed or user-asserted.
- Governance: sensitivity labels, visibility, account generation, graph-readiness/assertion metadata.

Timezone-aware timestamps and other invariants are enforced in the model. The presence of temporal fields is stronger evidence than mere timestamped transcript storage, but is not by itself proof of complete bitemporal semantics for all reads.

## Evidence is independently modeled

Source: [`backend/models/memory_evidence.py`](https://github.com/BasedHardware/omi/blob/main/backend/models/memory_evidence.py).

Evidence includes source ID/type/version, conversation ID, artifact and quote references, content hash, lineage and client-device identity. Metadata includes capture time, extractor/version, attribution, capture confidence, and independence group.

It separately tracks whether source material is active, missing, tombstoned, or purged; whether it was preserved; and whether provenance is visible, redacted, or hidden. Missing metadata is not treated as proof that the user authored the source.

YAP lesson: a citation is not just a URL. It needs a stable identity, revision, evidence span, availability state, and access policy. Multiple copies or retranscriptions of the same audio should not count as independent corroboration.

## Graph storage and enrichment

Sources:

- [`database/knowledge_graph.py`](https://github.com/BasedHardware/omi/blob/main/backend/database/knowledge_graph.py)
- [`utils/memory/graph_enrichment.py`](https://github.com/BasedHardware/omi/blob/main/backend/utils/memory/graph_enrichment.py)

The graph implementation uses Firestore collections including `knowledge_nodes`, `knowledge_edges`, and `memory_graph_assertions`, alongside canonical `memory_items`. A dedicated graph database is not required for this representation.

Node fields include labels, node types, aliases, memory references, and timestamps. Edge fields include source/target identity, relationship label, memory references, and creation time. The simple compatibility node/edge schema should not be confused with the richer canonical memory/assertion contract.

Graph enrichment accepts a typed, server-validated plan tied to a canonical memory snapshot. Plans contain subject, predicate, arguments, optional subject/object endpoints, qualifiers, and a deterministic hash. Receipts bind the plan to memory revision, content hash, evidence IDs, and account/source generations. The module explicitly does not parse raw LLM output or directly write graph documents.

YAP lesson: extraction, validation, authoritative mutation, and graph projection should be separate operations. A model response should not directly overwrite the knowledge store.

## Retrieval and indexes

Source: [`database/vector_db.py`](https://github.com/BasedHardware/omi/blob/main/backend/database/vector_db.py).

Current code uses Pinecone when configured and distinguishes conversation, memory, screen-activity, action-item, and transcript-chunk namespaces. Conversation summary vectors and transcript-chunk vectors serve different purposes.

`upsert_transcript_chunk_vectors` and `search_transcript_chunks` support semantic retrieval over raw transcript chunks. The module explicitly notes that summary-only embeddings miss exact dates, names, numbers, and one-off mentions. Chunk records point back to authoritative transcript storage through conversation/chunk identifiers.

The retained knowledge-ledger documentation describes keyword/vector results as candidate IDs, followed by authoritative hydration and policy filtering. This is an important privacy and consistency boundary: a stale index hit is not authorization to return deleted or restricted content.

## Ledger semantics and deployment caveats

Source: [`docs/memory/knowledge_ledger.md`](https://github.com/BasedHardware/omi/blob/main/backend/docs/memory/knowledge_ledger.md).

The document describes stable write identities, idempotency, revision/hash checks, supersession in an apply commit, evidence, outbox sequencing, validity closure, and deletion taking precedence over historical preservation. The physical authority is canonical `memory_items` and supporting control/journal/evidence structures—not a separate universal MemoryDB.

It also says JIT migration and on-demand conversation-retrieval paths were retired on 2026-10-18; retained kinds/contracts do not establish an active runtime tool surface. Some contracts and migration fixtures are explicitly subject to deployment gates. Do not turn this into a claim that every documented ledger behavior is operational in production.

## Privacy and portability

[Official open-source/cloud boundary](https://docs.omi.me/doc/get_started/open-source-and-omi-cloud.md) distinguishes MIT-licensed source from the hosted default experience and says production self-hosting is not supported/documented. Cloud providers and backend services still matter even when client and server code are public.

The historical storage documentation describes field-level enhanced encryption for transcript/memory text. This is not proof that all summaries, indexes, metadata, or derived records are end-to-end encrypted. A separate security audit would be needed before making stronger claims.

## Relevance to YAP — recommendations, not observed YAP behavior

Borrow evidence-linked canonical records, explicit lifecycle/validity, revision-bound projections, source-aware deletion, and authoritative checks after retrieval. Avoid adopting Omi's full migration/compatibility complexity as a starting requirement. Its architecture supports the case for a temporal assertion layer plus multiple projections, rather than a graph as the only source of truth.

Unverified: deployed feature flags/cohorts, runtime retrieval quality, actual security guarantees, self-host deployment completeness, and exact current extraction-model assignments.
