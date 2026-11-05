from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Four restrained whole-body pendant profiles; coordinates are dimensionless."""

from math import cos, hypot, pi, sin, sqrt


def normalize(points):
    """Scale a CCW convex polygon so every edge clears the unit disk."""
    clearance = min(
        (a[0] * b[1] - a[1] * b[0]) / hypot(b[0] - a[0], b[1] - a[1])
        for a, b in zip(points, points[1:] + points[:1])
    )
    factor = (1.0 + 1e-9) / clearance
    return [[x * factor, y * factor] for x, y in points]


def oval(count=64):
    """Quiet, slightly upright oval with no local outline features."""
    return normalize([
        [cos(2 * pi * i / count), 1.065 * sin(2 * pi * i / count)]
        for i in range(count)
    ])


def cushion(count=64):
    """Four broad sides joined by continuously curved cushion corners."""
    points = []
    for i in range(count):
        angle = 2 * pi * i / count
        c, s = cos(angle), sin(angle)
        radius = (abs(c) ** 3.8 + abs(s) ** 3.8) ** (-1 / 3.8)
        points.append([radius * c, 1.035 * radius * s])
    return normalize(points)


def soft_hexagon(arc_count=10):
    """Six long flats and six circular corners, without sharp vertices."""
    corner_radius = 0.22
    vertex_radius = (1.0 - corner_radius) * 2 / sqrt(3)
    points = []
    for vertex in range(6):
        angle = vertex * pi / 3
        cx, cy = vertex_radius * cos(angle), vertex_radius * sin(angle)
        for sample in range(arc_count):
            normal = angle - pi / 6 + (pi / 3) * sample / (arc_count - 1)
            points.append([
                cx + corner_radius * cos(normal),
                cy + corner_radius * sin(normal),
            ])
    return normalize(points)


def asymmetric_pebble(count=64):
    """Convex support-function pebble with three unequal, softly flowing lobes."""
    points = []
    for i in range(count):
        angle = 2 * pi * i / count
        support = 1.0 + 0.05 * cos(3 * angle) + 0.02 * sin(2 * angle)
        derivative = -0.15 * sin(3 * angle) + 0.04 * cos(2 * angle)
        points.append([
            support * cos(angle) - derivative * sin(angle),
            support * sin(angle) + derivative * cos(angle),
        ])
    return normalize(points)


STYLES = [
    {
        "id": "01",
        "name": "Quiet Oval",
        "family": "minimal",
        "description": "Slightly upright oval body with a low, broad, softly tapered shoulder.",
        "points": oval(),
        "top_scale": 0.88,
        "shoulder_z": 18.9,
        "top_z": 21.2,
        "ruled": False,
        "color": (0.77, 0.80, 0.82),
    },
    {
        "id": "02",
        "name": "Cushion Square",
        "family": "minimal",
        "description": "Compact four-sided cushion with rounded corners and a shallow, restrained roof taper.",
        "points": cushion(),
        "top_scale": 0.95,
        "shoulder_z": 20.0,
        "top_z": 21.3,
        "ruled": False,
        "color": (0.83, 0.81, 0.76),
    },
    {
        "id": "03",
        "name": "Soft Hexagon",
        "family": "minimal",
        "description": "Six clearly readable flats softened by round corners and a medium-width sloping shoulder.",
        "points": soft_hexagon(),
        "top_scale": 0.91,
        "shoulder_z": 19.5,
        "top_z": 22.1,
        "ruled": True,  # Preserve sampled arcs and flats without spline overshoot.
        "color": (0.68, 0.74, 0.75),
    },
    {
        "id": "04",
        "name": "River Pebble",
        "family": "minimal",
        "description": "Asymmetric rounded-triangular pebble with unequal flowing arcs and a deeper inward roof roll.",
        "points": asymmetric_pebble(),
        "top_scale": 0.83,
        "shoulder_z": 19.1,
        "top_z": 22.8,
        "ruled": False,
        "color": (0.75, 0.76, 0.69),
    },
]
