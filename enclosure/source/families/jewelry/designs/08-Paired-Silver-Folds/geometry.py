from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Unequal physically raised faceted slabs, joined by a backed diagonal valley."""
import math
import runpy


def make_envelope(style):
    import FreeCAD as App
    import Part
    V = App.Vector
    outer, cavity = runpy.run_path(source_path('ThemeEnvelopeGeometry.py'))['make_envelope'](style)
    cavity = cavity.common(Part.makeBox(140, 140, 19.8, V(-70, -70, 0)))
    rim = [[x * style['top_scale'], y * style['top_scale']] for x, y in style['footprint']]
    half_valley = 0.7 * math.hypot(1, 0.35)

    def clip(points, sign):
        result = []
        for a, b in zip(points, points[1:] + points[:1]):
            fa = sign * (a[1] + 0.35 * a[0] + 6) - half_valley
            fb = sign * (b[1] + 0.35 * b[0] + 6) - half_valley
            if fa >= 0:
                result.append(a)
            if (fa >= 0) != (fb >= 0):
                fraction = fa / (fa - fb)
                result.append([a[0] + fraction * (b[0] - a[0]), a[1] + fraction * (b[1] - a[1])])
        return result

    def below(shape, intercept, sx, sy):
        corners = [V(x, y, intercept + sx * x + sy * y) for x, y in [(-80, -80), (80, -80), (80, 80), (-80, 80)]]
        cutter = Part.Face(Part.makePolygon(corners + [corners[0]])).extrude(V(0, 0, 100))
        return shape.cut(cutter)

    edge_planes = []
    for a, b in zip(rim, rim[1:] + rim[:1]):
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        sx, sy = -0.7 * dy / length, 0.7 * dx / length
        edge_planes.append((21.4 - sx * a[0] - sy * a[1], sx, sy))
    crowns = {1: [(24.5, 0.09, -0.06), (24.5, -0.07, 0.08)],
              -1: [(24.0, -0.10, -0.06), (24.8, 0.08, 0.04)]}
    for sign in (1, -1):
        polygon = clip(rim, sign)
        vertices = [V(x, y, 20.9) for x, y in polygon]
        slab = Part.Face(Part.makePolygon(vertices + [vertices[0]])).extrude(V(0, 0, 6))
        for plane in crowns[sign] + edge_planes:
            slab = below(slab, *plane)
        outer = outer.fuse(slab)
    return outer.removeSplitter(), cavity.removeSplitter()


def face_color(style, part_name, face):
    if part_name != 'WholeBodyShell':
        return None
    center = face.CenterOfMass
    if center.z > 21.5 and center.y + 0.35 * center.x + 6 < -0.7:
        return style['accent_color']
    return None
