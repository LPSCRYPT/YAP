# Generated collection rules

These family directories contain preserved generated artifacts, not the editable source of truth. Read `../README.md`, `../docs/family-history.md`, the chosen family's `START-HERE.txt` and its individual reports/notes. Some early families have no START-HERE; use their source and report scope rather than inventing verification.

- Preserve all historical families/statuses. Do not overwrite one design to make room for a later direction, delete rejected studies, or relabel archived geometry as freshly verified.
- Edit source in `../source/`; run the packaged entrypoint into a new/empty directory outside the package when authorized. Only the integration owner intentionally promotes checked regenerated outputs and updates manifests.
- Never build in these curated directories or remove their reports as a checkpoint workaround. Historical `verification.json` is evidence, not permission to skip new checks.
- Keep each variant's matching parts together. Base/hood closures, carrier trim, light-guide tops, eyes and inset geometry differ. Millimeter STLs are separately bed-normalized, not assembly coordinates; native/STEP are installed geometry, not print layouts. Never globally scale to force a smaller fit.
- Preserve native CAD, STEP, every printable part, reports, previews and design notes as an associated set. Comparison documents can be exterior-only and are not substitutes for full assemblies.
- A native editable solid is not necessarily a parametric feature-history model. Do not claim recompute-driven editability from a hidden profile string alone.
- Report historical checks separately from copied-file/hash integrity, new source smoke and physical testing. No prints/strength/fatigue/RF/acoustic/thermal validation follows from these files.
- For shared FreeCAD sessions, one integration owner and one operation at a time; never concurrent RPC/build calls.

CAD/STEP/STL use Git LFS. Ensure content is hydrated before opening/validating; a pointer text file is not a CAD model. Preserve provenance and exclusions in the package manifest. Original external assets are not modified by package regeneration.
