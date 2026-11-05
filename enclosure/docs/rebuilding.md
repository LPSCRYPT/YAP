# Rebuilding from relocated sources

The implementation-side contract and platform-specific launcher examples are in [`source/AGENTS.md`](../source/AGENTS.md).

## Prerequisites and safety

Use **GUI-enabled FreeCAD** with `FreeCADGui`, `Part`, `Mesh`, `MeshPart`, `PySide` and the GUI's Coin/pivy support available. `FreeCADCmd` is not a supported substitute: generators use views, materials and GUI event processing. A Python interpreter with no FreeCAD installation can inspect JSON/source, but cannot generate the solids.

Obtain complete Git LFS contents before opening CAD: `.FCStd`, STEP/STP and STL are LFS-managed; an unhydrated pointer is not a CAD input. Preview/reference images are ordinary Git files. Check the package and reference manifests for expected sizes/hashes. Merely having source scripts without the packaged saved dependencies is insufficient.

The integration owner can run `python3 /ABS/checkout/enclosure/source/tools/verify_package.py` after all changes land. It checks artifact inventory digests/sizes, source/document/profile/image links, source syntax and portable paths; it does **not** execute CAD checks. This instruction is not a record of an executed verification.

Use a clean/dedicated session for reproducibility. Never operate on a shared live FreeCAD GUI without its integration owner's coordination. **No concurrent FreeCAD RPC calls or competing builds.** The portable entrypoints do not need XML-RPC or the original `localhost:9875` service. An authorized isolated offscreen GUI smoke is possible only where the chosen FreeCAD/Qt installation supports it; it is still GUI-enabled, not a promise of headless compatibility on every platform.

Every build requires a **new or empty output directory outside `enclosure/`**. The runtime rejects output inside the packaged tree and nonempty destinations. It copies saved CAD dependencies to `<output>/.inputs/` before opening them, protecting archived inputs from historical `save()` calls. Outputs go under `<output>/<family>/`; no original Downloads/Desktop paths are required for computation. Original provenance strings can remain in notes/reports without being executable dependencies.

## Supported Python-console entrypoint

In FreeCAD's Python console, replace `/ABS/checkout` with your checkout path:

```python
import runpy
build = runpy.run_path('/ABS/checkout/enclosure/source/tools/build.py')['build']
build('jewelry', design='16', output='/tmp/yap-jewelry16-rebuild')
```

A historical-family representative:

```python
build('smooth-pebble', output='/tmp/yap-pebble-rebuild')
```

The selected jewelry design is required (`'01'` through `'17'`). For `offset-cut` or `offset-theme`, `design` is a **1-based** ID; omit it to build all variants and their comparison. Their lower-level internal `build(index)` functions are zero-based, so do not confuse them with this public entrypoint. Other family defaults may build all designs covered by their designated macro; `design` is not a universal single-variant selector.

Each call configures a separate output run and clears the runtime alias map. Dependencies are loaded from packaged snapshots unless generated earlier within the same entrypoint sequence; running one family in another output directory does not automatically make its outputs inputs to a subsequent call. A fresh FreeCAD process is the clearest way to demonstrate no hidden session dependency.

## Environment-driven macro

Launch `source/tools/Rebuild.FCMacro` with the GUI's normal macro-launch mechanism. Set:

| Variable | Meaning |
| --- | --- |
| `YAP_BUILD_FAMILY` | Family ID from the table below. |
| `YAP_BUILD_DESIGN` | Optional selection as above; required for jewelry generation. |
| `YAP_BUILD_OUTPUT` | Required new/empty output directory outside package. |
| `YAP_BUILD_MACRO` | Optional inventoried original macro identifier instead of family default. |
| `YAP_BUILD_QUIT=1` | Dedicated-process automation only: close documents/exit after success, exit with failure on exception. Do not use in a user's working GUI. |

The launcher emits `YAP_BUILD_COMPLETE <output>` only after entrypoint completion, or `YAP_BUILD_FAILED` with traceback. Inspect the report/output, not just a process launch. The integration owner records actual commands/environment and results for package smoke evidence; examples here are instructions, **not claims of an executed test**.

## Family defaults and saved dependency graph

The package is an archive plus reproducible generators, **not a from-raw-component transitive build system**. The runtime's authoritative alias-to-file mapping is `source/source-manifest.json`. Later families intentionally reuse saved predecessors. `enclosure_runtime.document(alias)` binds the actual opened document object; repeated filenames such as `Assembly.FCStd` must not become live-tab name assumptions.

| Family | Default entry macro(s) | Principal saved inputs / relationship |
| --- | --- | --- |
| `early-recorder-studies` | `BuildRecorderCases.FCMacro` | XIAO board-only CAD in `references/components/`; circular/other studies are additional inventoried macros, not all run by this default. |
| `measured-and-fitted` | `BuildMeasuredVariants.FCMacro` | Earlier recorder/component geometry; fitted/internal-layout studies remain separately selectable macros. |
| `mounting` | `BuildModularMountPrototype.FCMacro` | Standalone mount mechanism default; wearable-base and centered-LED steps are separately selectable. |
| `integrated-slicer` | `BuildIntegratedSlicerSets.FCMacro` | Measured variants and modular-mount prototype snapshots. |
| `domed-mounted` | `BuildDomedMounted.FCMacro` | Integrated side-button case, measured side-button wire reservations, mount prototype. |
| `compact-bodies` | `BuildCompactBodies.FCMacro` | Domed-mounted components and mount prototype. |
| `sleek` | `BuildSleekPendants.FCMacro`, `AddSleekClip.FCMacro`, `ViewSleekPendants.FCMacro` | Two-level generation followed by clip and comparison steps in one run. |
| `smooth-pebble` | `BuildSmoothPebble.FCMacro` | Saved sleek retained assembly and shared smooth-envelope implementation. |
| `inset-face` | `BuildInsetFacePendant.FCMacro` | Saved smooth-pebble; shared smooth-envelope factory, not execution of its export macro. |
| `dome-variations` | `BuildDomeVariations.FCMacro` | Saved inset-face plus smooth-pebble mounting, shared smooth envelope. |
| `whole-body-atlas` | `BuildWholeBodyAtlas.FCMacro` | Saved sleek round; profile modules and preserved atlas `fit-scales.json`. |
| `offset-cut` | `BuildOffsetCutStudy.FCMacro` | Saved sleek round and Atlas 08 comparison original; explicit shared assembly function. |
| `offset-theme` | `BuildOffsetThemeConcepts.FCMacro` | Saved sleek round/square selected by style; shared assembly and envelope modules. |
| `jewelry` | `BuildJewelryStudies.FCMacro` | Saved sleek round/square selected by each `designs/<NN-name>/profile.json`; local `geometry.py` plus shared assembly/envelopes. |

Changing a predecessor's component geometry therefore requires intentionally propagating a newly checked dependency into the downstream source mapping/package, not merely rebuilding a downstream family against unchanged snapshots. Never overwrite curated history accidentally. Keep old and new generation evidence distinguishable.

### Other historical macros and parameters

Use the manifest's original macro identifier:

```python
build(macro='BuildFittedCases.FCMacro', output='/tmp/yap-fitted-rebuild')
```

`macro_globals={...}` supplies an existing macro's documented inputs (for example `CIRCULAR_CASE_SPECS`), rather than editing the generator to hardcode a one-off variant. Read the selected macro's accepted shape/units first; not every historical capacity/comparison is regenerated by a family default.

Edit-in-place prerequisite sequences are explicit in `build.py`: `AddWearableMounts.FCMacro` first regenerates measured variants; `CenterLEDAndViewMounts.FCMacro` first regenerates measured variants then wearable mounts; standalone `AddSleekClip.FCMacro` first generates sleek bodies. This avoids appending those features to already-final archived snapshots. A view/comparison macro may inspect saved dependencies without rebuilding their geometry; report that as viewing, not generation.

`CompareJewelryStudies.FCMacro` reads the packaged 17-design `collection.json` and saved assemblies in a clean session, writing a separate comparison output. That is a comparison rebuild from archived geometry, not a regeneration of all seventeen designs.

## Source changes and reproducibility

- Modify the family profile or geometry module, not only a generated native solid. Jewelry profiles/geometry are paired per design; `source/source-manifest.json` maps historical names to those paths.
- Shared `whole_body_assembly.py` replaces historical runtime AST/string extraction. `smooth_envelope.py` replaces executing/slicing another generator solely to obtain its envelope function. See [architecture](geometry-architecture.md).
- New output roots intentionally avoid the historical revision/checkpoint shortcut. Do not treat an old `verification.json` as proof new source ran, and do not delete the archive's report to force regeneration.
- Rebuild one selected design at a time where supported. Let the integration owner perform post-edit verification after source/docs/artifact changes settle.
- Compare generated validity/interference/containment/motion/mesh reports and actual geometry, not just filenames or screenshots. CAD kernel/platform versions can alter topology/meshes; byte-identical exports are not promised.
- A single jewelry/smooth-pebble smoke demonstrates only those selected pathways. Full-family regeneration and physical testing are separate acceptance steps.
