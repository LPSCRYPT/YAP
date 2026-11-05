# Enclosure work contract

Read `README.md` and the relevant `docs/` sections before editing. Keep all enclosure work under this directory. Do not change the repository-root README or unrelated Android/user changes as part of enclosure maintenance.

## Ownership and preservation

- Preserve original external inputs and archived historical outputs. Do not silently replace a prior family with a later design or promote its verification status.
- Sources belong in `source/families/<family>/`, shared code in `source/shared/`, tools in `source/tools/`, outputs in `builds/<family>/`. Keep provenance explicit for third-party CAD/images; redistribution rights are unknown unless documented otherwise.
- Do not treat build outputs as source. Update generators/profiles for durable geometry changes, then deliberately regenerate the affected design and its dependent artifacts when authorized.
- Maintain family links and hardware/assembly/verification notes when their contract changes. Do not duplicate the whole shared architecture in each family.

## FreeCAD execution

**One integration owner and one serialized FreeCAD operation at a time. Never issue simultaneous XML-RPC operations, start a second GUI instance to bypass contention, or run competing CAD builders.** During the original integration the shared GUI RPC endpoint was `http://localhost:9875`; that is a session endpoint, not a portable package prerequisite. Only the designated integration owner may use an existing shared endpoint. Independent profile research/editing may be parallel; CAD integration may not.

Sources must resolve paths relative to the relocated package and open required saved source documents in a clean session. Never rely on somebody's live `Sleek_Round`, `Sleek_Square` or `Atlas_08` tabs. Use the packaged entrypoint rather than copying historical console fragments with absolute Downloads paths. Do not run builds/tests/formatters in a delegated source/doc task unless explicitly assigned; the integration owner verifies after all edits land.

## Design invariants

- Follow `docs/hardware-and-assembly.md`; distinguish measured/confirmed dimensions from provisional modules and modeled placement. Do not fabricate a real switch, SD mechanism or supplier part.
- Latest designs need genuinely distinct whole-body silhouette and three-dimensional form, not cosmetic-only variations. Explain why thin/open reference jewelry becomes a broader closed-backed recorder.
- Keep the stack independently retained, battery uncompressed, LED centered, rear flat in necklace mode, shell serviceable, necklace eye connected and optional clip removable. Preserve ports, fastener clearances and wire reservations.
- Never scale the finished assembly/STLs to force a smaller appearance. Trim only unneeded carrier perimeter, not seats/restraints/components. Square carriers have rounded corners; do not treat their bounding rectangle as fully occupied or force all cavities round.
- Native solid snapshots are editable geometry, not a promised PartDesign feature tree. Hidden profile metadata does not create automatic recompute dependencies.

## Evidence and handoff

Read `docs/verification.md`. Keep containment distinct from collision tests. Do not suppress Boolean exceptions or bypass checks to obtain an export. Distinguish historical checks, fresh-session package smoke, full regeneration and physical validation. Report only executed checks and their limitations. A report/checkpoint existing on disk is not a test run, and a clean issues list is not manufacturing approval.
