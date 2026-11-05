from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Tapered wedge with seven backed angular pockets following its inclined roof."""
import runpy


ROOF_INTERCEPT = 23.1
ROOF_SLOPE_Y = 0.055
POCKET_DEPTH = 0.65


def make_envelope(style):
    import FreeCAD as App
    import Part
    base = runpy.run_path(source_path('ThemeEnvelopeGeometry.py'))['make_envelope']
    outer, cavity = base(style)

    def inclined_face(points, offset):
        vertices = [App.Vector(x, y, ROOF_INTERCEPT + ROOF_SLOPE_Y * y + offset) for x, y in points]
        return Part.Face(Part.makePolygon(vertices + vertices[:1]))

    above_ceiling = inclined_face([[-70, -70], [70, -70], [70, 70], [-70, 70]], -2.2).extrude(App.Vector(0, 0, 100))
    cavity = cavity.cut(above_ceiling).removeSplitter()
    cells = [
        [[-7, 18], [9, 25], [15, 21], [12, 17], [-5, 16.5]],
        [[-5, 11.5], [11, 11.5], [12, 8.5], [6, 8], [-4, 9]],
        [[6, 6], [13, 8], [13, 1], [8, -1], [5, 2]],
        [[4, -4], [10, -2], [12, -7], [7, -10], [2, -8]],
        [[4, -13], [9, -11], [11, -16], [7, -18], [3, -16]],
        [[6, -21], [10, -20], [10, -24], [7, -25], [5, -23]],
        [[6.5, -26.2], [9.8, -25.9], [10.0, -27.7], [7.0, -28.0]]
    ]
    cuts = [inclined_face(points, -POCKET_DEPTH).extrude(App.Vector(0, 0, 3)) for points in cells]
    return outer.cut(Part.makeCompound(cuts)).removeSplitter(), cavity


def face_color(style, part_name, face):
    if part_name != 'WholeBodyShell':
        return None
    vertices = face.Vertexes
    if len(vertices) >= 3 and all(abs(vertex.Point.z - (ROOF_INTERCEPT + ROOF_SLOPE_Y * vertex.Point.y - POCKET_DEPTH)) < 1e-5 for vertex in vertices):
        return tuple(style['accent_color'])
    return None
