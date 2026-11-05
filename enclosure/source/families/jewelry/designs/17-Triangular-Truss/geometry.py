from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Inclined triangular chassis with backed side pockets and a faceted crown."""
import runpy

_GEOMETRY = runpy.run_path(source_path('ThemeEnvelopeGeometry.py'))


def make_envelope(style):
    import FreeCAD as App
    import Part

    def wire(points, z):
        vertices = [App.Vector(x, y, z) for x, y in points]
        return Part.makePolygon(vertices + vertices[:1])

    def sloping_prism(points, below_roof, height):
        vertices = [App.Vector(x, y, 22.8 + 0.055 * y - below_roof) for x, y in points]
        return Part.Face(Part.makePolygon(vertices + vertices[:1])).extrude(App.Vector(0, 0, height))

    outer, cavity = _GEOMETRY['make_envelope'](style)
    left_pockets = [
        [[-24, 16], [-20, 1], [-13.5, 1], [-21.2, 16]],
        [[-9, -20], [-3, -23], [-12.5, -3], [-19, -3]],
    ]
    pockets = left_pockets + [[[-x, y] for x, y in reversed(points)] for points in left_pockets]
    for points in pockets:
        outer = outer.cut(sloping_prism(points, 0.9, 10))
        backing = _GEOMETRY['inset'](points, -0.8)
        cavity = cavity.cut(sloping_prism(backing, 2.4, 10))
    triangle = [[-21.5, 21], [0, -22], [21.5, 21]]
    table = [[x * 0.08, 3 + (y - 3) * 0.08] for x, y in triangle]
    crown = Part.makeLoft([wire(triangle, 21), wire(triangle, 24.35), wire(table, 25.2)], True, True)
    outer = outer.fuse(crown).removeSplitter()
    return outer, cavity.removeSplitter()


def face_color(style, part_name, face):
    if part_name == 'WholeBodyShell' and face.BoundBox.ZMin >= 24.35 - 1e-5:
        return style['accent_color']
    if part_name == 'WholeBodyShell':
        center = face.CenterOfMass
        if abs(center.z - (21.9 + 0.055 * center.y)) < 1e-5:
            return (0.22, 0.24, 0.25)
    return None
