# Graphiti — temporal graph framework reference

Researched: 2026-11-03.

Source: [official repository README](https://github.com/getzep/graphiti). This note summarizes documentation; no installation, model run, source-level algorithm audit, or benchmark was performed. Graphiti was added as an adjacent reference, not as another pendant project.

## Documented model

- **Episodes:** source data ingested into the framework, providing provenance for derived knowledge.
- **Entities:** people, products, concepts, and other typed identities, with evolving summaries.
- **Facts/relationships:** entity relationships with validity windows and links to source episodes.
- **Custom types:** developer-defined entity/edge schemas, including Pydantic-based definitions.

The project describes incremental construction, temporal fact invalidation with retained history, and hybrid retrieval combining semantic similarity, keyword search, and graph traversal. It explicitly advertises bitemporal tracking. These are framework capabilities described by the maintainers, not measured YAP behavior.

## Integration boundary

Graphiti is a self-hosted graph-construction/query framework. The application supplies the database, model provider, embedder, ingestion service, tenancy, access controls, and operational policies. It should not be mistaken for a complete secure personal-recorder backend.

The inspected README lists Neo4j, FalkorDB, and Amazon Neptune integrations. Kuzu is marked deprecated; do not select it based on older recommendations without checking current support.

OpenAI is the documented default inference/embedding path. Local providers through OpenAI-compatible endpoints are documented, but choosing a local endpoint does not establish extraction quality or structured-output compatibility. The README warns that weaker structured-output support, particularly with smaller models, can cause schema errors and ingestion failures.

## Why it is relevant

Graphiti is a candidate implementation behind YAP's projection/retrieval port. Its episode/entity/fact split closely matches evidence-backed temporal knowledge. Its public interfaces are worth comparing with a simpler relational assertion store before committing to a graph database.

## Risks and evaluation questions

1. Can every generated relation retain exact YAP transcript-revision and segment evidence references, not just a large episode ID?
2. How are speculation, negation, reported speech, uncertain dates, and conflicting sources represented?
3. Does automatic invalidation incorrectly close concurrent facts, such as multiple jobs or residences?
4. Can user corrections be distinguished from fresh model interpretations and preserved across re-extraction?
5. How do source deletion, access revocation, and graph/vector cleanup propagate?
6. What data leaves the deployment under the selected model and embedding configuration?
7. What are ingestion cost, latency, and retrieval quality on real pendant transcripts with ASR errors?
8. Which temporal queries are natively supported, and which need a YAP-side ledger?

## Recommendation

Evaluate it as an optional adapter after defining YAP-owned artifact and assertion contracts. Do not expose a framework's internal node/edge schema directly as the mobile app contract. Compare against PostgreSQL entity/assertion tables plus full-text/vector retrieval on the same question set. Framework adoption is not yet a decision.
