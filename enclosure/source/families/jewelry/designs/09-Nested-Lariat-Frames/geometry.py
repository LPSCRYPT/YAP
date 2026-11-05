from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Nested raised skew-rectangular frames above an opaque structural well."""
import runpy


def make_envelope(style):
    import FreeCAD as App
    import Part
    V = App.Vector
    outer, cavity = runpy.run_path(source_path('ThemeEnvelopeGeometry.py'))['make_envelope'](style)
    cavity = cavity.common(Part.makeBox(140, 140, 19.9, V(-70, -70, 0)))

    def rectangle(hx, hy, dx, dy, z, height):
        points = [(dx + x + 0.035 * y, dy + y) for x, y in [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]]
        vertices = [V(x, y, z) for x, y in points]
        return Part.Face(Part.makePolygon(vertices + [vertices[0]])).extrude(V(0, 0, height))

    for hx, hy, dx, dy, top in [(23.35, 27.3, 0.0, 0.0, 22.4),
                                (20.45, 24.4, 0.35, -0.25, 23.2),
                                (17.55, 21.5, 0.70, -0.50, 24.0)]:
        rail = rectangle(hx, hy, dx, dy, 21.1, top - 21.1)
        opening = rectangle(hx - 1.3, hy - 1.3, dx, dy, 21.0, top - 20.9)
        outer = outer.fuse(rail.cut(opening))
    return outer.removeSplitter(), cavity.removeSplitter()


def face_color(style, part_name, face):
    if part_name != 'WholeBodyShell':
        return None
    bounds = face.BoundBox
    if bounds.ZLength < 1e-5 and abs(bounds.ZMin - style['top']) < 1e-5:
        return style['accent_color']
    return None
