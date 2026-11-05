from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Broad interlocking pixel terraces and side blocks for the shard reference."""
import runpy

BASE = runpy.run_path(source_path('ThemeEnvelopeGeometry.py'))['make_envelope']


def make_envelope(style):
    import FreeCAD as App
    import Part
    outer, cavity = BASE(style)
    V = App.Vector

    def terrace(points, bottom, top):
        wire = Part.makePolygon([V(x, y, bottom) for x, y in points] + [V(*points[0], bottom)])
        return Part.Face(wire).extrude(V(0, 0, top - bottom))

    # These connected orthogonal islands are physical, broad relief rather than
    # a printed pixel graphic. Each penetrates the continuous backing roof.
    upper_left = [(-18, -14), (-12, -14), (-12, -20), (-7, -20),
                  (-7, -12), (-3, -12), (-3, -5), (-7, -5),
                  (-7, 3), (-3, 3), (-3, 13), (-8, 13),
                  (-8, 22), (-13, 22), (-13, 16), (-18, 16)]
    lower_right = [(2, -24), (8, -24), (8, -18), (13, -18),
                   (13, -10), (19, -10), (19, 0), (15, 0),
                   (15, 8), (20, 8), (20, 15), (11, 15),
                   (11, 20), (6, 20), (6, 11), (2, 11),
                   (2, 5), (6, 5), (6, -4), (2, -4)]
    middle = [(-6, -17), (-1, -17), (-1, -10), (3, -10),
              (3, -5), (-1, -5), (-1, -3), (-6, -3)]
    parts = [terrace(upper_left, 20.0, 22.5),
             terrace(lower_right, 20.0, 23.4),
             terrace(middle, 20.0, 22.0)]
    # Side-running blocks change the three-dimensional body outline, not just
    # the face. Their inner edges penetrate the structural envelope by 2 mm.
    for x, y, width, length, top in [(-26.0, -9, 3.0, 8, 21.8),
                                    (-25.6, 5, 2.8, 7, 22.0),
                                    (23.0, -5, 3.0, 8, 22.2),
                                    (22.5, 10, 2.8, 5, 21.9)]:
        parts.append(Part.makeBox(width, length, top - 8.0, V(x, y, 8.0)))
    outer = outer.multiFuse(parts).removeSplitter()
    return outer, cavity


def face_color(style, part_name, face):
    if part_name != 'WholeBodyShell':
        return None
    box = face.BoundBox
    if box.ZLength < 0.00001:
        if abs(box.ZMin - 23.4) < 0.00001:
            return tuple(style['accent_color'])
        if abs(box.ZMin - 22.5) < 0.00001:
            return (0.38, 0.39, 0.40)
    return None
