# Geometry architecture

## Source and artifact layers

`source/families/<family>/` holds family macros and profile data, `source/shared/` holds relocated shared support, and `source/tools/` provides controlled entrypoints. Saved inputs/outputs live in `builds/<family>/`; component/reference input belongs in `references/`. Consult [rebuilding](rebuilding.md) for actual dependency loading rather than relying on historical live tabs.

The late-generation architecture intentionally reuses the retained **Sleek_Round / Sleek_Square** source assemblies. Required source objects include `FlatRearBase`, `LowerCarrier`, `UpperCarrier`, `TopRetainer`, `ClipReceiverAdapter`, `SlideOnClip`, `ComponentReferences` and `RequiredHardware`. These are logical source identities: a loader must bind the document it opens, not infer a FreeCAD internal document name from a filename such as `Assembly.FCStd`.

- `source/shared/whole_body_assembly.py` exposes `build_assembly(style, SRC, ROOT, R, document_pattern, make_envelope=None)` and owns common assembly construction, closure placement, carrier trimming, ports, checks and exports. It was extracted from the original atlas generator.
- `BuildWholeBodyAtlas.FCMacro` orchestrates the twelve profiles from `WholeBodyMinimal.py`, `WholeBodyCyber.py`, `WholeBodyParametric.py`, using preserved `fit-scales.json`.
- `BuildOffsetCutStudy.FCMacro` uses `OffsetCutProfiles.py` and the shared assembly function; Atlas 08 supplies the original comparison reference.
- `BuildOffsetThemeConcepts.FCMacro` passes the standard theme `make_envelope(style)` to the shared assembly function. `ThemeVolumeProfiles.py` and `ThemeSilhouetteProfiles.py` supply six styles and their round/square source choice. Guide geometry intersects the actual outer envelope rather than ending at maximum roof height.
- `BuildJewelryStudies.FCMacro` loads each design's `profile.json` and `geometry.py`, then passes its envelope function to the same assembly path. Finish hooks colour actual surfaces; comparison generation is separate from a single-design build. `JewelryEnvelopeGeometry.py` retains the standard backed circuit treatment.
- `smooth_envelope.py` shares the continuous meridian factory across smooth-pebble/inset-face/dome variations without executing another family's document/export macro.

Historically offset/theme/jewelry generators reused atlas code through runtime AST/string transformations. **The packaged sources replace that fragile structure dependency with explicit shared function parameters.** Do not reintroduce AST slicing, hardcoded live tabs or duplicate the assembly/check logic. `source/source-manifest.json` maps original source identifiers to their relocated paths; `enclosure_runtime.py` resolves them and privately loads saved inputs.

## Envelope contract

A style's `footprint` is a **counterclockwise convex polygon in physical millimeters**, not a normalized image outline. Legacy ray/closure helpers receive `points = footprint / 25` with scale `R = 25`. The conventional `make_envelope(style)` returns `(outer, cavity)` as actual FreeCAD `Part` solid geometry. Decorations belong in outer geometry or real cuts, not only face colour. Cavity must remain usable for the retained components and withdrawal paths.

`ThemeEnvelopeGeometry.py` implements:

- **`roof_planes`:** extruded footprint capped by the minimum of supplied planes `Z = intercept + slopeX·X + slopeY·Y`. Cavity roof intercept is reduced by `1.4 * sqrt(1 + slopeX² + slopeY²)`, accounting for normal thickness on a slope rather than merely moving in XY.
- **`split_level`:** lower footprint, inset waist and shifted upper footprint. Inner transition begins earlier; upper cavity offset is 1.6 rather than simply copying the outer step at 1.4. The waist is a continuous shell feature, not an assembly seam.
- **`profile_loft`:** full-depth lower footprint through Z≈6, slight upper shrink to the shoulder, then scaled/optionally shifted roof sections. A single roof step gives a bevel; multiple steps approximate a rounded shoulder. The polygonal/ruled construction can show deliberate small facets.

Nominal base/wall/roof starts at **1.4**. Retained fasteners top out at **18.7**; conventional loft shoulder is at least **20.1** with top at least **21.3**. These are design constraints, not universal proof of minimum manufactured wall. For more expressive custom roofs, inspect actual cavity clearance and slope thickness rather than relying on one nominal number.

### Jewelry profile/plugin contract

Each packaged jewelry design has `source/families/jewelry/designs/<NN-name>/profile.json` and `geometry.py`. The source manifest maps original identifiers such as `Jewelry-NN.json` and `JewelryCustomNN.py` to their packaged locations. Profile records include `id`, descriptive `name`, source (`Sleek_Round` or `Sleek_Square`), image provenance, `reference_analysis`, `interpretation`, `finish_notes`, physical footprint, envelope parameters and float RGB colour. The loader resolves the profile-relative custom module; optional accent colour, eye position and view angle support specific geometry.

Every packaged design geometry module exposes `make_envelope(style) -> (outer, cavity)`; optional `face_color(style, part_name, face) -> RGB or None` paints existing physical surfaces. Reuse the base theme helper when needed; never recurse through the jewelry dispatcher. The Circuit Cabochon wrapper deliberately removes `custom_module` before delegating its standard circuit treatment to avoid recursion. Keep FreeCAD/Part imports inside geometry functions where the existing module convention permits ordinary profile inspection without FreeCAD.

Physical grooves require backing: the circuit example thickens its roof region by clipping cavity ceiling to `top - 2` before cutting 0.3-deep channels. Other pockets/raised islands must similarly leave connected, printable solids and avoid the actual guide/acoustic/USB/button openings. Most new ornaments should use robust features around 1 mm or larger; historical Circuit Cabochon's 0.55-wide channels are explicitly a fine-print/post-finish exception, not a general resolution guarantee.

Outer additions must intersect the body robustly and stay a single solid; closed-backed recesses must be described honestly rather than portrayed as through-open jewelry. A corner eye must connect to the rear body with real overlap and not obstruct hardware or hood removal. A custom finish hook is not permission to create cosmetic-only variants.

## Shared assembly operations

1. Form outer/cavity envelopes, shell above the 1.4 rear plate, and a rear outline matching the full-body footprint.
2. Reuse retained source base features while removing obsolete original-eye material. Maintain the lower perimeter where closure pillars attach.
3. Search nearby perimeter angles for three closure columns clear of actual component/hardware solids. Construct pilots and rear countersinks. A seated fit alone does not establish vertical withdrawal clearance.
4. Add connected rear eye, USB/actuator/acoustic openings and centered guide opening.
5. Copy and trim only unused carrier perimeter to the new profile; cut closure reliefs while preserving component retention. Source square carriers have genuinely rounded corners; do not force a circular cavity or preserve nonexistent full-box corner occupancy.
6. Copy reference components and nonprinted hardware; generate guide with its top intersected against actual roof; copy optional receiver/clip.
7. Check solids, containment, interference, motion samples and meshes; save native/STEP/STL/report artifacts and comparison views as appropriate.

## Editability and coordinates

Most generated objects are `Part::Feature` solid snapshots. Hidden `EditableFootprint`/`ProfileDefinition` or `ContinuousMeridian` objects help inspect source parameters/curves; editing such metadata does **not** automatically rebuild downstream solids. For repeatable changes, edit profile/module source and intentionally rebuild/recheck dependencies. “Native CAD” does not mean a full sketch/constraint/PartDesign history.

STLs are individually translated to the bed and clip pieces may be rotated for printing. Native and STEP use installed assembly coordinates. Comparison documents copy exterior shapes at equal scale; they are not the full component assembly. Copy and translate the **shape** before assignment: overwriting an object's placement can discard primitive-native offsets and misplace a guide. Compare every design in front and oblique views; rendered colour cannot establish shape clearance.
