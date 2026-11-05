from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Oblique graphite shard: three real roof planes and subdued facet finishes."""
import runpy


def make_envelope(style):
    base = runpy.run_path(source_path('ThemeEnvelopeGeometry.py'))['make_envelope']
    return base(style)


def face_color(style, part_name, face):
    if part_name != 'WholeBodyShell':
        return None
    normal = face.normalAt(0, 0)
    if normal.z < 0.9:
        return None
    slope_x = -normal.x / normal.z
    if slope_x > 0.12:
        return (0.22, 0.235, 0.30)
    if slope_x < -0.12:
        return (0.115, 0.125, 0.16)
    return (0.16, 0.175, 0.22)
