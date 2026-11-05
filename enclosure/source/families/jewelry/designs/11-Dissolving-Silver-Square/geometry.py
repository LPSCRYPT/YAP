from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""A planar square plate with backed square apertures and corner pixels."""
import runpy

BASE = runpy.run_path(source_path('ThemeEnvelopeGeometry.py'))['make_envelope']


def make_envelope(style):
    import FreeCAD as App
    import Part
    V = App.Vector
    outer, cavity = BASE(style)
    # Blind recesses preserve a 1.5 mm roof beneath the 0.6 mm recess floor.
    cavity = cavity.common(Part.makeBox(140, 140, 19.2, V(-70, -70, 0)))
    for x, y, size in [(7.5, 14.5, 5.0), (14.5, 14.5, 5.0),
                       (14.5, 7.5, 5.0)]:
        outer = outer.cut(Part.makeBox(size, size, 2.0, V(x, y, 20.7)))
    # Broad, overlapping blocks form a load-connected corner cluster. They
    # reach down the sidewall rather than merely sitting on the front face.
    pixels = [Part.makeBox(6.0, 7.0, 14.0, V(20.5, 19.5, 8.0)),
              Part.makeBox(4.5, 4.5, 14.0, V(25.0, 24.5, 8.0)),
              Part.makeBox(4.5, 4.5, 14.0, V(18.5, 24.5, 8.0))]
    return outer.multiFuse(pixels).removeSplitter(), cavity


def face_color(style, part_name, face):
    if part_name != 'WholeBodyShell':
        return None
    box = face.BoundBox
    if box.ZLength < 0.00001 and abs(box.ZMin - 20.7) < 0.00001:
        return tuple(style['accent_color'])
    return None
