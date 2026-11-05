from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Integral faceted octagonal inset above the structural signet shoulder."""
import runpy

_BASE = runpy.run_path(source_path('ThemeEnvelopeGeometry.py'))['make_envelope']


def make_envelope(style):
    import FreeCAD as App
    import Part

    outer, cavity = _BASE(style)
    wires = []
    for scale, z in ((0.88, 22.0), (0.84, 23.4)):
        points = [App.Vector(x * scale, y * scale, z) for x, y in style['footprint']]
        wires.append(Part.makePolygon(points + points[:1]))
    island = Part.makeLoft(wires, True, True)
    return outer.fuse(island).removeSplitter(), cavity


def face_color(style, part_name, face):
    if part_name == 'WholeBodyShell' and face.BoundBox.ZMin >= 22.4 - 1e-5 and face.BoundBox.ZMax > 22.4 + 1e-5:
        return style['accent_color']
    return None
