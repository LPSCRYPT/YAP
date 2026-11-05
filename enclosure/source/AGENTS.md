# Enclosure source maintenance

## Scope and provenance

This directory owns the portable generators, not the curated original exports in `../builds/`. The migration inventories all 52 original `.FCMacro`/`.py` files and all 17 Jewelry JSON profiles from the original `Recorder-Enclosures` collection in `source-manifest.json`. Original source filenames are stable lookup keys; `path` is the relocated file relative to this directory. Original files outside this package were not modified. Geometry and historical reports are not evidence of physical fit, RF, acoustic, thermal, fatigue, or print validation.

The manifest records original source/document dependency expressions, the concrete packaged document lookup table, and extracted shared implementations. `shared/whole_body_assembly.py` replaces the atlas/offset/theme/jewelry runtime AST/string-rewriting layers with an explicit parameterized function. `shared/smooth_envelope.py` replaces AST extraction from the smooth-pebble builder. Remaining `runpy` calls load real profile/geometry modules by registered relative paths; they do not rewrite source text.

## Runtime requirements

Use GUI-enabled FreeCAD with `FreeCADGui`, `Part`, `Mesh`, `MeshPart`, `PySide.QtGui` and `pivy`. `FreeCADCmd` is not supported: historical builders really use GUI documents, materials, cameras and images. No RPC server, running Sleek document, shell working directory, or workstation-specific paths are required. Keep this source directory beside the packaged `builds/` and `references/` directories. The initial recorder generator needs `references/components/XIAO-ESP32-S3-Board-Only.FCStd`, object `Mainboard`.

`shared/enclosure_runtime.py` copies required native source documents into `<output>/.inputs/` before opening them. Logical source identifiers such as `Sleek_Round` map to returned FreeCAD document objects, not guessed filenames, labels, or internal `Name` strings. Generated documents are registered the same way. Existing unrelated GUI tabs are not borrowed or closed by `build()`. Each invocation uses a **new or empty directory outside `enclosure/`**. Original packaged artifacts are never build destinations. Families load packaged dependency snapshots; this is not a transitive rebuild of every historical experiment.

## Exact commands

In a fresh FreeCAD GUI Python console, replace `/ABS/checkout` with the checkout location:

```python
import runpy
build = runpy.run_path('/ABS/checkout/enclosure/source/tools/build.py')['build']
build('jewelry', design='16', output='/tmp/yap-jewelry16-smoke')
```

Representative historical rebuild in a separate new/empty output directory:

```python
build('smooth-pebble', output='/tmp/yap-pebble-smoke')
```

Run the GUI launcher in a **dedicated normal GUI process**. The macOS FreeCAD 1.0.2 installation used for package verification cannot create an OpenGL context with `QT_QPA_PLATFORM=offscreen` and crashed before building; do not use that setting here.

```sh
FREECAD_USER_HOME=/tmp/yap-jewelry-home YAP_BUILD_FAMILY=jewelry YAP_BUILD_DESIGN=16 YAP_BUILD_OUTPUT=/tmp/yap-jewelry16-smoke YAP_BUILD_QUIT=1 /Applications/FreeCAD.app/Contents/MacOS/FreeCAD --user-cfg /tmp/yap-jewelry-user.cfg --system-cfg /tmp/yap-jewelry-system.cfg /ABS/checkout/enclosure/source/tools/Rebuild.FCMacro
FREECAD_USER_HOME=/tmp/yap-pebble-home YAP_BUILD_FAMILY=smooth-pebble YAP_BUILD_OUTPUT=/tmp/yap-pebble-smoke YAP_BUILD_QUIT=1 /Applications/FreeCAD.app/Contents/MacOS/FreeCAD --user-cfg /tmp/yap-pebble-user.cfg --system-cfg /tmp/yap-pebble-system.cfg /ABS/checkout/enclosure/source/tools/Rebuild.FCMacro
```

Offscreen support is platform-dependent, not a substitute for the real GUI APIs. `YAP_BUILD_QUIT=1` closes documents and exits **that process** after success; never use this flag in the user's live session. The launcher prints `YAP_BUILD_COMPLETE <output>` or `YAP_BUILD_FAILED` with a traceback. A family writes outputs beneath `<output>/<family>/`; Jewelry 16 writes `jewelry/16-Octagonal-Signet/` with its native assembly, STEP exports, eight STL parts and checks. Camera capture is separately available through the jewelry builder's `save_view(16)` after GUI settling; no image success is inferred from merely building.

Inventory/digest verification, independent of FreeCAD:

```sh
python3 /ABS/checkout/enclosure/source/tools/verify_package.py
```

This checks every original artifact digest, all manifest source/document paths, jewelry geometry/image links, Python syntax, and absence of workstation-specific runtime paths. It does not execute CAD geometry. See `../docs/verification.md` for actual relocated smoke evidence; preserve the distinction between original validation and new integration evidence.

## Family defaults and historical entrypoints

| Family | Default operation |
| --- | --- |
| early-recorder-studies | BuildRecorderCases |
| measured-and-fitted | BuildMeasuredVariants |
| mounting | BuildModularMountPrototype |
| integrated-slicer | BuildIntegratedSlicerSets |
| domed-mounted | BuildDomedMounted |
| compact-bodies | BuildCompactBodies |
| sleek | BuildSleekPendants, AddSleekClip, ViewSleekPendants |
| smooth-pebble | BuildSmoothPebble |
| inset-face | BuildInsetFacePendant |
| dome-variations | BuildDomeVariations |
| whole-body-atlas | All atlas profiles and comparison; uses packaged fit-scales.json |
| offset-cut | All four profiles and comparison, or one 1-based design id |
| offset-theme | All six profiles and comparison, or one 1-based design id |
| jewelry | One explicitly supplied two-digit design id |

A family default is a runnable representative, not a claim to regenerate every historical file. Run another inventoried macro explicitly:

```python
build(macro='BuildFittedCases.FCMacro', output='/tmp/yap-fitted')
build(macro='BuildCircularCases.FCMacro', output='/tmp/yap-circular')
build('offset-theme', design='02', output='/tmp/yap-theme02')
```

Use `macro_globals={...}` for the original macro's explicit parameter overrides such as `CIRCULAR_CASE_SPECS`; do not patch source text. `YAP_BUILD_MACRO` is the launcher equivalent for a named macro. The runtime does not invent missing historical parameter overrides.

The historical add-on macros modify documents in place. Their entrypoint prerequisites are intentional: AddWearableMounts rebuilds measured variants first; CenterLEDAndViewMounts rebuilds measured variants then adds wearable mounts; AddSleekClip rebuilds the sleek bodies first. These avoid adding features twice to already-finished packaged snapshots. Their subsequent `save()` calls affect only generated/private files. Comparisons otherwise load packaged source documents as necessary; the jewelry collection comparison consumes the packaged 17-design `collection.json`.

## Add or change a jewelry design

1. Own one `families/jewelry/designs/<two-digit-id>-<Descriptive-Name>/` directory. Read the actual reference image; do not infer geometry from its filename. Preserve image filename, observations, interpretation and finish limitations. Images belong in `references/jewelry/`; rights are unknown unless separately established, not licensed by this package.
2. Keep `profile.json` and `geometry.py` together. `custom_module` is exactly `geometry.py`, resolved relative to the profile. `source_image` is enclosure-relative, e.g. `references/jewelry/<original filename>.jpg`. Preserve the original filename in `reference_provenance`; never introduce an absolute runtime path.
3. Follow an existing profile's schema: id, name, source (`Sleek_Round` or `Sleek_Square`), convex CCW physical-mm footprint, envelope kind and parameters, color, reference_analysis, interpretation and finish_notes. Points are actual mm, not normalized. `build_file()` supplies normalized atlas points and scale 25.
4. Expose `make_envelope(style) -> (outer, cavity)` from geometry.py. Reuse `ThemeEnvelopeGeometry.py` via `source_path()` or import it directly after entrypoint setup. Never recurse through the jewelry wrapper. Import CAD modules inside geometry functions where practical. Optional `face_color(style, part_name, face)` returns RGB or None and must correspond to real physical surfaces, not fake hardware.
5. Preserve the actual retained hardware: top at 18.7 mm, nominal 1.4 mm wall/roof, compact footprint, shell extraction, flat removable rear, eyelet, centered LED guide, USB/button/acoustic ports, carrier fasteners and optional slide-on clip. Do not reduce the cavity by hiding/removing reference components. Make grooves with adequate backing, meaningful whole-body geometry, and printable connected solids.
6. Register the new profile and geometry in `source-manifest.json`; new profile key `Jewelry-NN.json` enables `build('jewelry', design='NN', ...)`. Keep `sources` entries and dependency metadata accurate. Add a packaged document alias only when a corresponding finished assembly actually exists. Extending the collection comparison also requires updating its expected collection membership and published collection metadata.
7. Rebuild into a new isolated output. Parent/integration owner must inspect CAD, compare expected dimensions/parts, review native Boolean and mesh checks, and inspect renders before replacing curated artifacts. Do not claim historical work was revalidated merely because source paths or syntax pass.
