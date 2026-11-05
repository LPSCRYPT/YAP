from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Asymmetric stone wedge in an open-bottom, raised structural frame."""
import runpy

GEOMETRY = runpy.run_path(source_path('ThemeEnvelopeGeometry.py'))


def make_envelope(style):
    import FreeCAD as App
    import Part
    V = App.Vector
    outer, cavity = GEOMETRY['make_envelope'](style)
    p = style['footprint']
    inner = GEOMETRY['inset'](p, 2.0)

    def prism(points, z, height):
        wire = Part.makePolygon([V(x, y, z) for x, y in points] + [V(*points[0], z)])
        return Part.Face(wire).extrude(V(0, 0, height))

    # Keep the diagonal lower edge open, while the two side rails converge
    # around the narrow upper end. Every rail intersects the body below its bevel.
    rails = []
    for i in range(1, len(p)):
        j = (i + 1) % len(p)
        rails.append(prism([p[i], p[j], inner[j], inner[i]], 19.4, 3.7))
    outer = outer.multiFuse(rails).removeSplitter()
    # The source's open upper triangle becomes an honest blind recess, with
    # 1.6 mm minimum roof backing above the retained electronics.
    cavity = cavity.common(Part.makeBox(140, 140, 20.1, V(-70, -70, 0)))
    window = prism([(-6.0, 15.5), (6.0, 15.5), (0.0, 24.5)], 21.7, 3.0)
    return outer.cut(window).removeSplitter(), cavity


def face_color(style, part_name, face):
    if part_name != 'WholeBodyShell':
        return None
    box = face.BoundBox
    if box.ZLength < 0.00001:
        if abs(box.ZMin - 23.1) < 0.00001:
            return tuple(style['accent_color'])
        if abs(box.ZMin - 21.7) < 0.00001:
            return (0.17, 0.20, 0.19)
    return None
