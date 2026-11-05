"""Run inside GUI-enabled FreeCAD; no RPC or pre-existing document required."""
from pathlib import Path
import runpy
import sys

SOURCE = Path(__file__).resolve().parents[1]
shared = str(SOURCE / 'shared')
if shared not in sys.path:
    sys.path.insert(0, shared)
from enclosure_runtime import configure, manifest, source_path

FAMILY_MACROS = {
    'early-recorder-studies': ['BuildRecorderCases.FCMacro'],
    'measured-and-fitted': ['BuildMeasuredVariants.FCMacro'],
    'mounting': ['BuildModularMountPrototype.FCMacro'],
    'integrated-slicer': ['BuildIntegratedSlicerSets.FCMacro'],
    'domed-mounted': ['BuildDomedMounted.FCMacro'],
    'compact-bodies': ['BuildCompactBodies.FCMacro'],
    'sleek': ['BuildSleekPendants.FCMacro', 'AddSleekClip.FCMacro', 'ViewSleekPendants.FCMacro'],
    'smooth-pebble': ['BuildSmoothPebble.FCMacro'],
    'inset-face': ['BuildInsetFacePendant.FCMacro'],
    'dome-variations': ['BuildDomeVariations.FCMacro'],
    'whole-body-atlas': ['BuildWholeBodyAtlas.FCMacro'],
    'offset-cut': ['BuildOffsetCutStudy.FCMacro'],
    'offset-theme': ['BuildOffsetThemeConcepts.FCMacro'],
    'jewelry': ['BuildJewelryStudies.FCMacro'],
}
# These historical edit-in-place macros require their pre-edit generators, not
# the final curated snapshots (which already contain the added features).
PREREQUISITES = {
    'AddWearableMounts.FCMacro': ['BuildMeasuredVariants.FCMacro'],
    'CenterLEDAndViewMounts.FCMacro': ['BuildMeasuredVariants.FCMacro', 'AddWearableMounts.FCMacro'],
    'AddSleekClip.FCMacro': ['BuildSleekPendants.FCMacro'],
}


def build(family=None, *, design=None, output, macro=None, macro_globals=None):
    """Build a family/default or one inventoried macro into isolated output.

    For jewelry, design is a two-digit id (required). For offset families it is
    an optional 1-based id; absent means build every variant and comparison.
    macro_globals supplies original macro parameters, e.g. CIRCULAR_CASE_SPECS.
    Each call starts a separate run; use a new/empty directory every time.
    """
    import FreeCAD as App
    import FreeCADGui as Gui
    if not App.GuiUp:
        raise RuntimeError('A GUI-enabled FreeCAD process is required, not FreeCADCmd')
    if macro is None and family not in FAMILY_MACROS:
        raise ValueError('Unknown family: ' + str(family))
    if macro is not None:
        entry = manifest()['sources'].get(macro)
        if entry is None or entry['kind'] != 'macro':
            raise ValueError('Unknown inventoried macro: ' + str(macro))
        family = entry['path'].split('/')[1]
        sequence = PREREQUISITES.get(macro, []) + [macro]
    else:
        sequence = FAMILY_MACROS[family]
    if family == 'jewelry' and (macro is None or macro == 'BuildJewelryStudies.FCMacro'):
        if design is None:
            raise ValueError('Jewelry builds require design="01" .. "17"')
        profile = source_path('Jewelry-%02d.json' % int(design))
    root = configure(output)
    result = None
    for filename in sequence:
        namespace = runpy.run_path(source_path(filename), init_globals=dict(macro_globals or {}))
        if filename == 'BuildJewelryStudies.FCMacro':
            result = namespace['build_file'](profile)
        elif filename in ('BuildOffsetCutStudy.FCMacro', 'BuildOffsetThemeConcepts.FCMacro'):
            indices = range(len(namespace['STYLES'])) if design is None else [int(design) - 1]
            for index in indices:
                if not 0 <= index < len(namespace['STYLES']):
                    raise ValueError('Design index outside this family')
                result = namespace['build'](index)
            if design is None:
                namespace['compare']()
        elif filename == 'CompareJewelryStudies.FCMacro':
            namespace['compare']()
    Gui.getMainWindow().statusBar().clearMessage()
    print('YAP_BUILD_COMPLETE ' + str(root), flush=True)
    return {'output': str(root), 'family': family, 'design': design, 'report': result}
