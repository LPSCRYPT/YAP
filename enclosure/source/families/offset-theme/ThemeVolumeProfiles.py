from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Offset Cut whole-body profiles in physical millimetres, CCW viewed from +Z.

Roof-plane triples are (intercept, slope_x, slope_y); the outer roof is
min(intercept + slope_x*x + slope_y*y). Split-level heights are absolute Z,
except seam_height, which is the thickness of the recessed waist band.
"""

import math


def rounded_rectangle(width, height, radius, shift_x=0.0, shift_y=0.0):
    """Return a CCW polygon with six samples, including ends, per corner."""
    points = []
    for cx, cy, start in (
        (width / 2 - radius, -height / 2 + radius, -90),
        (width / 2 - radius, height / 2 - radius, 0),
        (-width / 2 + radius, height / 2 - radius, 90),
        (-width / 2 + radius, -height / 2 + radius, 180),
    ):
        for sample in range(6):
            angle = math.radians(start + 18 * sample)
            points.append([
                cx + shift_x + radius * math.cos(angle),
                cy + shift_y + radius * math.sin(angle),
            ])
    return points


STYLES = [
    {
        'id': '01',
        'name': 'Offset Wedge',
        'description': (
            'A sheared four-sided body with one uninterrupted inclined roof; '
            'the full side elevation rises across the enclosure rather than '
            'using a bevel or an inset face.'
        ),
        'source': 'Sleek_Round',
        'footprint': [
            [-25.0, -26.5], [25.0, -22.5],
            [25.0, 26.5], [-25.0, 22.5],
        ],
        'kind': 'roof_planes',
        'roof_planes': [[23.8, 0.10, 0.025]],
    },
    {
        'id': '02',
        'name': 'Split Level',
        'description': (
            'Two rounded volumes separated by a shallow recessed waist: '
            'a broad lower body and a smaller upper body offset right and '
            'down, with a rounded upper shoulder.'
        ),
        'source': 'Sleek_Square',
        'footprint': rounded_rectangle(50.0, 50.0, 7.0),
        'kind': 'split_level',
        'upper_footprint': rounded_rectangle(46.0, 48.8, 7.0, 1.0, -0.2),
        'upper_center': [1.0, -0.2],
        'lower_height': 8.0,
        'seam_height': 1.2,
        'seam_inset': 0.6,
        'upper_height': 21.8,
    },
    {
        'id': '04',
        'name': 'Folded Shell',
        'description': (
            'An asymmetric six-sided body with two broad opposing roof '
            'planes meeting along the off-centre diagonal x + 0.4*y = 2; '
            'a real ridge spanning the shell, not a perimeter bevel.'
        ),
        'source': 'Sleek_Round',
        'footprint': [
            [-25.0, -20.0], [-12.0, -28.0], [25.0, -24.0],
            [25.0, 20.0], [-12.0, 28.0], [-25.0, 14.0],
        ],
        'kind': 'roof_planes',
        'roof_planes': [[26.08, 0.16, 0.064], [26.72, -0.16, -0.064]],
    },
]
