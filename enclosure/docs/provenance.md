# Provenance and reference rights

## Preserved origins

The package consolidates generated work originally kept in:

- `/Users/bot/Downloads/Recorder-Enclosures/`: historical scripts, source/generated native CAD, exports, previews and reports.
- `/Users/bot/Downloads/Pendant-*` collections: integrated slicer, domed-mounted, compact, sleek, smooth-pebble, inset-face, dome variations, whole-body atlas, offset-cut, offset-theme and jewelry outputs.
- `/Users/bot/Desktop/jewelry/`: seventeen supplied image references used for the jewelry interpretations.

These are provenance locations, **not required runtime paths**. Originals are preserved. Relocated source lookup uses `source/source-manifest.json` and package-relative paths. Historical reports/notes can retain original filenames/absolute paths as evidence; that is different from executing a dependency at that path.

## Manifests and storage

- [`../manifest.json`](../manifest.json) records staged artifact/reference files with original relative path, package path, byte size and SHA256, plus exclusions. It is the authority for the copied inventory rather than prose counts.
- [`../references/manifest.json`](../references/manifest.json) records the 24 supplied reference assets: seventeen jewelry photos, six XIAO inputs and raw ReSpeaker STEP, with origin and explicitly unknown redistribution status.
- [`../source/source-manifest.json`](../source/source-manifest.json) maps original generator/profile identifiers to relocated source paths and logical CAD aliases to packaged saved dependencies. Relocated sources have intentional edits; do not expect their checksums to equal original scripts.

Native CAD, STEP/STP and STL are Git LFS-managed; previews and reference images are ordinary Git files. LFS storage does not change ownership or grant redistribution rights. Preserve `cad/.gitkeep` and `stls/.gitkeep` as legacy placeholders rather than pretending they contain the indexed families.

## Rights and interpretation limits

References were included as **user-approved project references**. Their redistribution rights have **not been independently established**, and this package grants **no new license** for them. Do not infer that a photo/model is public domain or repository-licensed merely because it is packaged here. Preserve filenames, origin fields and restrictions; investigate ownership/license before publishing or reusing outside the authorized project context.

Jewelry photos support visual analysis only: shape, apparent surfaces and relative proportions. They do not certify physical size, material, manufacturing technique, supplier identity or electrical functionality. The inset-face study similarly does not establish production Omi dimensions. The raw ReSpeaker enclosure CAD is an external reference, not evidence that this recorder matches its mechanical/electrical system.

Generated designs are hardware-constrained interpretations, not literal thin/open jewelry reproductions. Backed recesses deliberately replace impossible through-open centers. Broadening, truncated points, fewer/larger detail features and altered attachment eyes must remain documented. No copied brand/logo or fake functional circuitry is needed to communicate the inspiration.

Colours in native views preview pigment/nonconductive finish; they do not specify metal construction, precious stones, conductive traces, coating certification or an extra electronic component. Actual conductive/metal finishes require separate isolation/RF/thermal evaluation.

## Historical evidence is not silently rewritten

Keep original `START-HERE.txt`, `DESIGN-NOTES.txt`, reports and screenshots with their family. Later shared docs clarify relocation and current limitations without altering the fact that earlier designs had incomplete retention, provisional hardware or narrower tests. A preserved report may predate source refactoring; attach new generation evidence separately. Jewelry 01's metadata-report recovery remains explicit rather than rewritten as a clean rebuild.
