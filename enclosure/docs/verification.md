# Verification evidence, acceptance and repairs

## Four different evidence levels

1. **Preserved historical evidence:** original `verification.json`, `collection.json`, mesh/geometry reports, screenshots and `START-HERE.txt` describe their original generation runs. Some earlier reports check only selected shells/intersections. Do not relabel them as the full modern suite.
2. **Package integrity:** `../manifest.json` records original relative paths, SHA256, sizes and exclusions; `../references/manifest.json` records input origins and rights status. Hash/inventory checks establish copied-file identity, not CAD validity or rebuild reproducibility.
3. **Fresh-session source evidence:** only an explicitly recorded package smoke/rebuild run can establish that relocated code and its selected dependencies load/build in a clean FreeCAD session. One representative design does not verify all families. Loading a saved file is not source regeneration; loading a builder without calling it is not a completed build.
4. **Physical validation:** prints, real components, retention/load/fatigue, electrical isolation, RF, acoustics, optics, charging/thermal and wear/finish testing. None is established by the archived CAD reports.

## Relocated package smoke evidence

Executed from `/tmp/yap-enclosure-publish`, not the original Downloads tree, using FreeCAD 1.0.2R39319 on macOS arm64. Dedicated normal GUI processes used separate temporary user/system config files and `YAP_BUILD_QUIT=1`; the existing user session was not used. Full measured reports are in [rebuild-evidence.json](rebuild-evidence.json).

| Exercised pathway | Observed result |
| --- | --- |
| Package verifier | All 846 artifact digests and 69 inventoried sources passed; dependency/profile links, syntax and portable-path checks passed. |
| Jewelry 16, Octagonal Signet | Fresh build completed; 8 checked mesh exports, empty issues, dimensions 49.8 × 49.8 × 23.4 mm. Bounds and facet counts match the curated STLs; maximum absolute mesh-volume difference is 5.61e-8 mm³. Not every STL is byte-identical. |
| Smooth pebble | Fresh build completed; 8 checked mesh exports, empty issues, recorded minimum unperforated wall 1.5219903 mm. |
| Offset theme 02, Split Level | Fresh build completed; 8 checked mesh exports, empty issues, dimensions 50 × 50 × 21.8 mm. |
| Whole-body atlas batch | Designs 01–08 completed with empty issues and closed reimported meshes. The process reached its 600-second deadline during design 09. This is partial evidence, not a completed twelve-design regeneration. |
| Qt offscreen attempt | Failed with exit139 because this installation cannot create an OpenGL context with the offscreen plugin. The supported smoke invocations use the normal GUI renderer instead. |

Commands use `source/tools/Rebuild.FCMacro` with the family/design/output environment variables documented in `source/AGENTS.md`. Do not overwrite these preserved reports when checking a newer revision. The unexercised historical entrypoints and remaining designs retain their historical evidence only; no physical validation is implied.

## Modern geometry acceptance criteria

The atlas/offset/theme/jewelry lineage checks the following, with family-specific additions:

- Each printable part is valid and a single connected solid (`isValid`, solid count); detailed `Shape.check(True)` on principal Boolean shell/base geometry.
- Pairwise printed-part interference, component/nonprinted hardware intersections and motor/speaker wire reservations; typical forbidden-volume threshold **0.001 mm³**. Keep units and numerical tolerance explicit.
- Component containment **separately** from no-intersection: a component outside an undersized enclosure may have zero collision. LED has special roof/guide placement; do not generalize that exception to other components.
- Shell extraction sampled at Z displacements **0.2, 1, 3, 6, 10, 15, 22, 30** against the retained assembly. These eight positions are not continuous collision detection.
- Clip release sampled at distances **0, 0.5, 1, 4, 12, 25, 40**. Unchanged inherited latch geometry may rely on earlier seated/released mechanism checks; do not call a translation proxy a flexure stress analysis.
- Before export, `Mesh.isSolid()`, no detected nonmanifolds and no detected self-intersections; after STL write, reimport and test closed/manifold. Report fields may record only the reimport result, while generator source shows pre-export checks.
- Exported STL units/orientation/bed minimum, native/STEP assembly positions, correct part count and design-specific guide/closure pairing.
- Actual exterior inspection in front and angled views; compare same scale. Screenshots demonstrate appearance, not mechanical clearance.

**Intentional contact needs a narrowly explained exception.** Carrier screws engage plastic base pilots. The historical atlas-derived obstacle loop skips base-vs-hardware overlap tests for the hardware group, although the documented physical reason is carrier-screw thread engagement. This is a broader implementation exemption than a per-screw whitelist; do not claim it independently proves every base/hardware clearance. Other unintentional overlaps must not be hidden behind that exception.

Inset-face additionally checks face forward retention/rear insertion and eight seam vents. Dome-inlay variants check real recess backing, insertion and rim ports. Smooth-pebble records unperforated curve-distance evidence; that does not certify every manufactured wall or hole edge.

## Physical acceptance still needed

Before adopting a wearable, verify the actual SD/switch/small modules, component/pad/header heights, wire bend/service access, battery clearance without compression, screw heads/tips and insert separation. Print calibrated fit samples; inspect support removal, holes, bands/pads and all assembly paths. Test clip/eye/latch force and fatigue, snag/breakaway behavior, charging/thermal behavior, electrical isolation, optical coupling, microphone/speaker response and coupling, RF performance, ingress and finish compatibility. Do not infer these from CAD, PETG suggestions or metallic-looking colours.

## Known failures and durable repairs

| Failure or misleading result | Required response / existing repair |
| --- | --- |
| Historical absolute paths or live `Sleek_*` dependency | Use packaged entrypoint/resolver and saved source artifacts. Bind returned documents by logical source aliases. A clean session must not require pre-opened user tabs. |
| Repeated source filename `Assembly.FCStd` produces wrong document/name | Do not assume `App.getDocument` can recover the intended source from a filename. Use the loader's document object/alias contract. |
| Old revision-2 checkpoint skips changed geometry | Use isolated fresh output for a deliberate rebuild; inspect checkpoint logic. Historical atlas checks report revision plus live document presence. Never delete archived evidence merely to make a smoke run appear new. Preserve old evidence and write newly checked outputs separately. |
| Long build appears frozen | Serialize one design per operation; service Qt events between operations. A single Boolean/mesh operation can still block. Do not launch a competing FreeCAD/RPC call. |
| Component lies outside a small shell with no reported collision | Add/retain containment checks against outer envelope; collision-only evidence is insufficient. |
| Sloped roof leaves thin wall or guide protrudes | Offset plane by normal thickness and intersect guide with actual roof, not global maximum height. Lofted/custom roofs still need local clearance review. |
| Closure hits electronics during hood lift | Search unobstructed vertical columns, move closure and corresponding reliefs; recheck extraction. Do not remove functional retention to hide the collision. |
| Local motor-seat collision in narrow asymmetrical jewelry | Preserve component/seat and broaden local outline/cavity as appropriate. Historical integration corrected designs 12, 14 and 17; this is why their final footprints differ from thin reference proportions. |
| Fragile curved pocket/channel Boolean | Use robust planar/chamfered pocket boundaries and connected backing. Preserve the intended physical relief; do not suppress an invalid Boolean or replace it with paint. Historical jewelry integration used this repair. |
| Engraving cuts through a nominal roof | Add backing before cutting. Circuit Cabochon clips the cavity ceiling to `top−2` before 0.3-depth channels. Recheck component clearance after thickening. |
| `NullShapeException` from disjoint `Shape.common` in older compact code | Distinguish expected empty intersection from invalid inputs using the relevant FreeCAD API/validity checks; never blanket-catch/suppress genuine Boolean failure or label an unexecuted check passed. |
| Comparison light guide misplaced | Copy/translate geometry before assignment rather than overwriting native primitive placement. Inspect actual assembly, not only comparison. |
| View colour/material update ineffective | Float RGB tuples; modern `ViewObject.ShapeAppearance = [material]` rather than relying on legacy `ShapeMaterial`. Specular zero/shininess zero were used to avoid blown-out comparison faces. Material display does not prove geometry or composition. |
| Screenshot captures stale camera | Let GUI camera settle before `saveImage`; original integration used a separate serialized RPC/view operation. Do not describe an uninspected view as inspected. |
| Jewelry 01 report missing metadata after export | Original `report_recovery` explicitly says geometry checks, STL reimports and STEP exports completed before a missing description key; report reconstructed without rebuilding. Preserve this history rather than claiming a new successful geometry run. |

## Integration discipline

Only the integration owner runs final package checks after source/docs/artifacts have landed. Do not run builds, tests, linters or formatters from parallel documentation/source tasks unless assigned. One FreeCAD process/one operation owner for a shared session; **no simultaneous RPC operations**. A new isolated GUI process for an authorized clean-session smoke is different from trying to bypass a busy shared instance; it must not connect to or mutate the existing user's live documents.
