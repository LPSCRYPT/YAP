from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""A deep backed square well and integral right-offset smaller bezel."""
import runpy

_BASE = runpy.run_path(source_path('ThemeEnvelopeGeometry.py'))['make_envelope']


def make_envelope(style):
    import FreeCAD as App
    import Part

    def clipped_rectangle(cx, cy, width, height, clip, z, depth):
        x0, x1 = cx - width / 2, cx + width / 2
        y0, y1 = cy - height / 2, cy + height / 2
        points = [(x0 + clip, y0), (x1 - clip, y0), (x1, y0 + clip),
                  (x1, y1 - clip), (x1 - clip, y1), (x0 + clip, y1),
                  (x0, y1 - clip), (x0, y0 + clip)]
        vertices = [App.Vector(x, y, z) for x, y in points]
        return Part.Face(Part.makePolygon(vertices + vertices[:1])).extrude(App.Vector(0, 0, depth))

    outer, cavity = _BASE(style)
    # Straight pocket edges avoid curved Boolean-corner tessellation failures.
    well = clipped_rectangle(0, -1, 28, 26, 2, 21, 5)
    backing = clipped_rectangle(0, -1, 30, 28, 3, 19.5, 10)
    cavity = cavity.cut(backing).removeSplitter()
    outer = outer.cut(well)
    bezel = clipped_rectangle(8.1, -5, 12, 12, 1.8, 20.8, 1.8)
    opening = clipped_rectangle(8.1, -5, 9, 9, 0.7, 20.7, 2.1)
    outer = outer.fuse(bezel.cut(opening)).removeSplitter()
    return outer, cavity


def face_color(style, part_name, face):
    if part_name == 'WholeBodyShell':
        bounds = face.BoundBox
        if abs(bounds.ZMin - 21) < 1e-5 and bounds.ZLength < 1e-5:
            return style['accent_color']
    return None
