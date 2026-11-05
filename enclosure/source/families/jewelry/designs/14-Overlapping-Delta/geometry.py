from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Integral overlapping triangular roofs on a closed clipped-delta enclosure."""
import runpy

_GEOMETRY = runpy.run_path(source_path('ThemeEnvelopeGeometry.py'))


def make_envelope(style):
    import FreeCAD as App
    import Part

    def prism(points, z, height):
        vertices = [App.Vector(x, y, z) for x, y in points]
        return Part.Face(Part.makePolygon(vertices + vertices[:1])).extrude(App.Vector(0, 0, height))

    outer, cavity = _GEOMETRY['make_envelope'](style)
    lower = [[-21, 16], [0, -23], [21, 16]]
    lower_ring = prism(lower, 21.8, 0.9).cut(prism(_GEOMETRY['inset'](lower, 1.45), 21.7, 1.1))
    upper = [[-17, 19], [1, -9], [19, 19]]
    upper_roof = prism(upper, 21.8, 2.2)
    upper_recess = prism(_GEOMETRY['inset'](upper, 1.55), 23.6, 0.6)
    outer = outer.fuse(lower_ring).fuse(upper_roof).cut(upper_recess).removeSplitter()
    return outer, cavity


def face_color(style, part_name, face):
    if part_name != 'WholeBodyShell':
        return None
    bounds = face.BoundBox
    if bounds.ZMin >= 23.99 or (abs(bounds.ZMin - 22.7) < 1e-5 and bounds.ZLength < 1e-5):
        return style['accent_color']
    return None
