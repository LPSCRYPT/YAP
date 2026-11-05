from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Physical-mm, counter-clockwise whole-body profiles for the Offset Cut theme."""

import math


def _arc(radius, centre_y, start, end, segments):
    return [
        [
            radius * math.cos(start + (end - start) * i / segments),
            centre_y + radius * math.sin(start + (end - start) * i / segments),
        ]
        for i in range(segments + 1)
    ]


def _diagonal_clip(points, limit):
    """Clip a CCW polygon to x + y <= limit, preserving exact cut intersections."""
    result = []
    previous = points[-1]
    previous_distance = previous[0] + previous[1] - limit
    for current in points:
        current_distance = current[0] + current[1] - limit
        if (previous_distance <= 0) != (current_distance <= 0):
            fraction = previous_distance / (previous_distance - current_distance)
            result.append([
                previous[0] + fraction * (current[0] - previous[0]),
                previous[1] + fraction * (current[1] - previous[1]),
            ])
        if current_distance <= 0:
            result.append(list(current))
        previous = current
        previous_distance = current_distance
    return result


# Two genuine semicircles, joined by 8 mm vertical flanks; not an ellipse.
_capsule = _arc(24.8, 4.0, 0.0, math.pi, 24)
_capsule += _arc(24.8, -4.0, math.pi, 2.0 * math.pi, 24)

# Broad upper shoulders and unequal lower diagonals meet at an offset tip.
_shield = [
    [4.0, -29.0],
    [19.0, -22.0],
    [26.0, -4.0],
    [26.0, 15.0],
    [14.0, 25.5],
    [-14.0, 25.5],
    [-23.0, 19.0],
    [-26.0, 9.0],
    [-26.0, -8.0],
    [-18.0, -22.0],
]

# Only the left half is round; the right side remains three broad planar cuts.
_hybrid = [
    [0.0, -25.0],
    [10.0, -25.0],
    [25.0, -12.0],
    [25.0, 14.0],
    [10.0, 25.0],
    [0.0, 25.0],
]
_hybrid += _arc(25.0, 0.0, math.pi / 2.0, 3.0 * math.pi / 2.0, 24)[1:-1]


STYLES = [
    dict(
        id='03',
        name='Diagonal Capsule',
        description=(
            'Elongated stadium body with circular ends, short straight flanks, '
            'and one full-height upper-right diagonal slice; an inset shifted '
            'roof continues the cut. The square carrier must be outline-trimmed.'
        ),
        source='Sleek_Square',
        footprint=_diagonal_clip(_capsule, 35.3),
        kind='profile_loft',
        shoulder=20.1,
        top=22.6,
        top_scale=0.91,
        top_shift=[0.4, -0.3],
    ),
    dict(
        id='05',
        name='Asymmetric Shield',
        description=(
            'Broad upper shoulders taper through unequal lower diagonals to '
            'a tip offset 4 mm right; the dominant upper-right diagonal and '
            'shifted inset roof form a directional shield, not a clipped box.'
        ),
        source='Sleek_Round',
        footprint=_shield,
        kind='profile_loft',
        shoulder=20.1,
        top=23.4,
        top_scale=0.89,
        top_shift=[0.5, -0.3],
    ),
    dict(
        id='06',
        name='Soft Hard Hybrid',
        description=(
            'A continuous half-round left body meets a flat right flank and '
            'two long diagonal facets; its shallow shifted roof bevel keeps '
            'the soft-versus-planar contrast visible throughout the body.'
        ),
        source='Sleek_Round',
        footprint=_hybrid,
        kind='profile_loft',
        shoulder=20.1,
        top=22.2,
        top_scale=0.93,
        top_shift=[0.6, 0.0],
    ),
]
