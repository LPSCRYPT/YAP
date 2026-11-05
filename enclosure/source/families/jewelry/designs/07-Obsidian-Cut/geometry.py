from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Asymmetric polyhedral roof with robust parallel scores on one cut face."""
import math
import runpy


def make_envelope(style):
    import FreeCAD as App
    import Part
    outer, cavity = runpy.run_path(source_path('ThemeEnvelopeGeometry.py'))['make_envelope'](style)
    V = App.Vector
    for intercept, sx, sy in style['roof_planes']:
        level = intercept - 1.8 * math.sqrt(1 + sx * sx + sy * sy)
        corners = [V(x, y, level + sx * x + sy * y) for x, y in [(-80, -80), (80, -80), (80, 80), (-80, 80)]]
        above = Part.Face(Part.makePolygon(corners + [corners[0]])).extrude(V(0, 0, 100))
        cavity = cavity.cut(above)
    intercept, sx, sy = style['roof_planes'][2]
    cuts = []
    for y in [-8, -4, 0, 4, 8]:
        a, b = (17.0, y), (23.0, y + 3.0)
        length = math.hypot(b[0] - a[0], b[1] - a[1])
        nx, ny = -(b[1] - a[1]) / (2 * length), (b[0] - a[0]) / (2 * length)
        xy = [(a[0] + nx, a[1] + ny), (b[0] + nx, b[1] + ny),
              (b[0] - nx, b[1] - ny), (a[0] - nx, a[1] - ny)]
        vertices = [V(x, yy, intercept + sx * x + sy * yy - 0.35) for x, yy in xy]
        cuts.append(Part.Face(Part.makePolygon(vertices + [vertices[0]])).extrude(V(0, 0, 0.6)))
    outer = outer.cut(Part.makeCompound(cuts)).removeSplitter()
    return outer, cavity.removeSplitter()


def face_color(style, part_name, face):
    if part_name != 'WholeBodyShell':
        return None
    center = face.CenterOfMass
    intercept, sx, sy = style['roof_planes'][2]
    if 16 < center.x < 24 and abs(center.z - (intercept + sx * center.x + sy * center.y - 0.35)) < 1e-5:
        return style['accent_color']
    return None
