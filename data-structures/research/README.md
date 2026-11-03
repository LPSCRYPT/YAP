# Data structures and processing research

Research date: **2026-11-03**.

This directory preserves the source-backed investigation informing YAP's data structures, transcription post-processing, temporal knowledge modeling, retrieval, and privacy boundaries. These notes are **research, not implementation specifications or final technology selections**.

## Project notes

| Note | Focus |
| --- | --- |
| [OpenPendant](openpendant.md) | SQLite clips/segments, daily recap artifacts, hosted Mem0/OpenAI integration |
| [Omi](omi.md) | Canonical memory and evidence, validity/revisions, graph assertions, transcript/vector retrieval |
| [Plaud NotePin](plaud.md) | Public recording/transcript/note interfaces, memory policy, cloud processing boundaries |
| [Limitless](limitless.md) | Lifelog schema, hybrid retrieval, export, product-status and privacy-policy changes |
| [memrii](memrii.md) | Local audio archive, capture metadata, clock uncertainty, authorized export contracts |
| [Boswell](boswell.md) | Local transcript/extracted artifacts, speaker identity, rebuildable keyword/vector indexes |
| [AudioMoth / MicroMoth](audiomoth-micromoth.md) | WAV capture/provenance and the boundary between recording and speech intelligence |
| [Graphiti](graphiti.md) | Adjacent temporal graph framework; candidate adapter, not a pendant product |
| [YAP synthesis and open questions](yap-data-model-synthesis.md) | Proposed evidence/assertion/projection separation, temporal semantics, processing stages, and evaluation scenarios |
| [Data Plan UX and policy](data-plan-ux-and-policy.md) | First-class controls for processing placement, explicit transfers, storage, audio expiry, and policy enforcement |

## Evidence standard

- **Inspected source:** concrete schemas, transformations, storage calls, or retrieval code were read. This establishes what that code expresses, not whether it is deployed or works reliably.
- **Documentation/product claims:** official API documentation, help pages, policies, and README descriptions were reviewed. Commercial internals remain unknown unless those sources disclose them.
- **Recommendation/inference:** lessons proposed for YAP are labeled as such and must not be mistaken for functionality already built.
- **Unknown/unverified:** no authenticated commercial API calls, hardware experiments, deployments, security audits, model evaluations, tests, or benchmarks were performed for this investigation.

Source URLs are embedded in each project note. Most link to moving branches or live documentation. Recheck before basing an implementation or privacy claim on them. Observed repository revisions during research:

| Repository | Branch | Observed revision |
| --- | --- | --- |
| Omi | `main` | `d673bb46deb51ae137411323e0ecf1b509fcc2f3` |
| memrii | `main` | `a57ae266ef89c84e6efbcd738b87aff4efe5b228` |
| Boswell | `main` | `44c763452b1995e78b70fe33508e63eb7ed66563` |
| OpenPendant | `master` | Revision not pinned in this investigation |

These observed revisions are provenance markers; source reads were not an atomic checkout. Commercial documentation and Graphiti README observations are date-scoped, not commit-pinned.

## Corrections worth preserving

1. Current Omi source is richer than the earlier conversations/memories/summary-vector overview: it includes canonical evidence-backed memory, graph structures, temporal validity fields, and transcript-chunk vectors. Do not propagate the older summary-only indexing claim.
2. memrii's fork ancestry does not mean it uses Omi's cloud or memory architecture. Its active design intentionally removes the upstream transcription/memory backend.
3. Calling Mem0 from OpenPendant does not prove graph extraction. The inspected recap-add call explicitly uses `infer:false`.
4. Timestamps on documents or utterances do not establish bitemporal fact semantics.
5. Limitless stopped new Pendant sales, but the official announcement promises continuing-customer support throughout 2026, with separate regional shutdowns. Do not equate this with a verified global shutdown.
6. Local storage, self-hostable source, cloud-sync-off, local processing, and no-egress privacy are different properties.
7. Plaud's October 2026 policy has different effective dates for new and existing accounts. Preserve those dates rather than generalizing one policy across all users.
8. AudioMoth is a scientific capture system, not an implemented speech/memory stack.

## How to extend these notes

For each new finding, record the research date, exact source, relevant symbol/schema/API, evidence level, and implications or unknowns. Keep source observations separate from design proposals. Record corrections explicitly instead of silently replacing earlier conclusions. If a future experiment is run, document its input, environment, observed output, and limits; do not promote a README performance claim into a verified benchmark.

The current working recommendation is **versioned source artifacts + evidence-backed interpretations + replaceable projections**. A temporal knowledge graph is a promising initial projection, not a required universal data store. See the synthesis for details and unresolved choices.
