from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Oblique double-point shield with a raised oval bezel and domed core."""
import math
import runpy

BASE = runpy.run_path(source_path('ThemeEnvelopeGeometry.py'))['make_envelope']


def make_envelope(style):
    import FreeCAD as App
    import Part
    V = App.Vector
    outer, cavity = BASE(style)
    cavity = cavity.common(Part.makeBox(140, 140, 19.2, V(-70, -70, 0)))
    # The apparent split tips are roof slots, not openings into the electronics.
    # Continuous backing remains 1.4 mm thick under their floors.
    for y in [-33.0, 18.5]:
        outer = outer.cut(Part.makeBox(2.8, 14.5, 8.0, V(-1.4, y, 20.6)))

    def oval(rx, ry, z):
        points = [V(rx * math.cos(2 * math.pi * i / 64),
                    ry * math.sin(2 * math.pi * i / 64), z) for i in range(64)]
        return Part.makePolygon(points + [points[0]])

    # A real oval bezel grows out of the shield, with a solid domed crown.
    # It is not a separate stone or an unretained insert.
    bezel = Part.Face(oval(16.8, 22.0, 20.0)).extrude(V(0, 0, 2.2))
    sections = [oval(15.4, 20.6, 21.8)]
    for i in range(9):
        angle = (math.pi / 2 - 0.045) * i / 8
        sections.append(oval(15.4 * math.cos(angle), 20.6 * math.cos(angle),
                             22.2 + 2.6 * math.sin(angle)))
    dome = Part.makeLoft(sections, True, True)
    return outer.multiFuse([bezel, dome]).removeSplitter(), cavity


def face_color(style, part_name, face):
    if part_name != 'WholeBodyShell':
        return None
    box = face.BoundBox
    if box.ZMax > 22.20001 and box.ZMin >= 22.19999:
        return (0.055, 0.065, 0.075)
    if box.ZLength < 0.00001 and abs(box.ZMin - 22.2) < 0.00001:
        return tuple(style['accent_color'])
    if box.ZLength < 0.00001 and abs(box.ZMin - 20.6) < 0.00001:
        return (0.055, 0.06, 0.065)
    return None
