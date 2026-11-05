# Recorder enclosure collections

This directory packages the recorder enclosure design history, editable generation sources, native CAD, manufacturing exchanges, meshes, previews and recorded checks. These are **CAD fit prototypes**, not production-approved or physically validated wearables. Earlier studies remain historical studies; packaging them does not upgrade their status.

Start with a collection's saved comparison image or native assembly. **No regeneration is needed to inspect the finished files.** Native `.FCStd` models generally contain editable solid snapshots and reference geometry, not complete PartDesign feature histories. STL files are millimeter print parts; STEP/native assemblies retain installed coordinates and are not print-bed layouts.

## Download the actual CAD files

Native CAD, STEP and STL files use **Git LFS**. Install Git LFS, clone the repository, then run from its root:

```sh
git lfs install
git lfs pull
python3 enclosure/source/tools/verify_package.py
```

A small text file beginning `version https://git-lfs.github.com/spec/v1` is an unresolved LFS pointer, not a CAD model. Previews and documentation remain ordinary Git files. Avoid assuming a GitHub source ZIP contains resolved LFS assets.

## Family collections

| Collection | Design purpose and historical status |
| --- | --- |
| [Early recorder studies](builds/early-recorder-studies/) | Initial rectangular/circular battery and packaging alternatives; historical dimensions/assumptions, not the latest hardware contract. |
| [Measured and fitted](builds/measured-and-fitted/) | Flat/stacked packing and measured round/capsule layouts; shell/fit reports, not complete modern retention. |
| [Mounting](builds/mounting/) | Necklace/clip additions, centered indicator and independent removable-mount prototype; mount coupon is not a complete case. |
| [Integrated slicer sets](builds/integrated-slicer/) | Three integrated receiver cases with alternative flush/clip inserts; internal retention and button remained unfinished. |
| [Domed mounted](builds/domed-mounted/) | Round dome with independent component carriers and removable rear inserts. |
| [Compact bodies](builds/compact-bodies/) | 44/46/48 mm bodies traded footprint for a tall multi-level stack; preserved, not preferred sleek direction. |
| [Sleek](builds/sleek/) | Two-level 50 mm round and 49 mm stepped-square architecture; source of later retained hardware. |
| [Smooth pebble](builds/smooth-pebble/) | Continuous revolved curved hood with flat removable rear. |
| [Inset face](builds/inset-face/) | Photo-inspired separate inset face with concealed seam vents; acoustic proposal, not a tuned system. |
| [Dome variations](builds/dome-variations/) | Orbit, Meridian and Crescent physical recessed inlays; retained as front-treatment studies. |
| [Whole-body atlas](builds/whole-body-atlas/) | Twelve full-outline/volume alternatives in minimal, cyberpunk and parametric groups. |
| [Offset cut](builds/offset-cut/) | Four full-body refinements plus the original comparison; judged too similar for the later design brief. |
| [Offset theme](builds/offset-theme/) | Six distinct volume/silhouette architectures, including inclined and folded roofs. |
| [Jewelry inspired](builds/jewelry/) | Seventeen image-specific whole-body interpretations with individual design notes and historical check records. |

The most recent design direction is **distinct whole-body form**, not recolouring, a face badge, or tiny chamfer changes. Compactness is bounded by the retained components; do not shrink STLs to mimic thin jewelry.

## Read before editing or fabrication

- [Family history and design index](docs/family-history.md): what changed, what was rejected, and the 17 jewelry interpretations.
- [Hardware contract and assembly](docs/hardware-and-assembly.md): confirmed inputs versus assumptions, nonprinted restraints, fasteners and service access.
- [Geometry architecture](docs/geometry-architecture.md): source relationships, envelope contracts and retained geometry.
- [Rebuild guide](docs/rebuilding.md): relocated source entrypoints, prerequisites and clean-session behavior.
- [Verification and failure repairs](docs/verification.md): evidence boundaries, required checks and known implementation pitfalls.
- [Provenance](docs/provenance.md): originals, reference rights and interpretation limits.

`source/families/` contains family-specific generators/profiles; `source/shared/` contains shared support; `source/tools/` contains packaging/rebuild tooling. `builds/<family>/` contains preserved generated collections. `references/` contains input references with provenance rather than an implied license grant. Legacy `cad/` and `stls/` placeholders are not the collection index.

Use every printed part from **one design folder**. Matching bases, shell closure positions, trimmed carriers and light guides vary. Most modern families have six necklace-mode parts plus two optional clip parts; inset-face/dome-inlay families have nine total. Read the family's retained `START-HERE.txt` for exceptions. Historical documents may mention original absolute paths or live FreeCAD tabs; use this package's rebuild guide instead for relocated execution.

## Evidence boundary

Archived `verification.json`, `collection.json` and other reports describe the original generation runs. They are not proof that relocated sources have been regenerated, nor proof of physical fit. Package manifests and any fresh-session smoke evidence supplied with this package are separate records; only their explicitly exercised scope is covered. This overview makes no package smoke-success claim.

No physical print/fit, strength, clip fatigue, battery charging/thermal, acoustic, optical, RF, waterproofing or finish-durability validation is established by the preserved CAD reports. The actual SD module, several small modules and switch/actuator remain unresolved. PETG is only a suggested fit-test material; no validated printer profile or G-code is supplied.
