from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Six interlocked border rails and a backed central slot on a hexagonal body."""
import math
import runpy


def make_envelope(style):
    import FreeCAD as App
    import Part
    helpers = runpy.run_path(source_path('ThemeEnvelopeGeometry.py'))
    outer, cavity = helpers['make_envelope'](style)
    V = App.Vector
    top = style['top']
    cavity = cavity.common(Part.makeBox(140, 140, top - 2.2, V(-70, -70, 0)))
    roof = [[x * style['top_scale'], y * style['top_scale']] for x, y in style['footprint']]
    rail = helpers['inset'](roof, 4.1)
    cuts = []

    def channel(a, b, width, depth):
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        nx, ny = -dy * width / (2 * length), dx * width / (2 * length)
        vertices = [V(a[0] + nx, a[1] + ny, top - depth),
                    V(b[0] + nx, b[1] + ny, top - depth),
                    V(b[0] - nx, b[1] - ny, top - depth),
                    V(a[0] - nx, a[1] - ny, top - depth)]
        cuts.append(Part.Face(Part.makePolygon(vertices + [vertices[0]])).extrude(V(0, 0, depth + 0.2)))

    for i, a in enumerate(rail):
        b = rail[(i + 1) % 6]
        channel(a, b, 1.0, 0.4)
        end = [roof[i][0] * 0.82 + roof[(i + 1) % 6][0] * 0.18,
               roof[i][1] * 0.82 + roof[(i + 1) % 6][1] * 0.18]
        channel(a, end, 1.0, 0.4)
    channel((0, -10.0), (0, -4.5), 2.4, 0.65)
    cutter = cuts[0].multiFuse(cuts[1:]).removeSplitter()
    outer = outer.cut(cutter).removeSplitter()
    return outer, cavity


def face_color(style, part_name, face):
    if part_name != 'WholeBodyShell':
        return None
    bounds = face.BoundBox
    if bounds.ZLength < 1e-5 and any(abs(bounds.ZMin - (style['top'] - depth)) < 1e-5 for depth in (0.4, 0.65)):
        return style['accent_color']
    return None
