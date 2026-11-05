from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Deterministic whole-body silhouettes; dimensions are normalized to unit inradius."""

import math


def normalize_footprint(points):
    """Scale CCW polygon edges, rather than just vertices, outside the unit disk."""
    edge_distances = [
        (a[0] * b[1] - a[1] * b[0])
        / math.hypot(b[0] - a[0], b[1] - a[1])
        for a, b in zip(points, points[1:] + points[:1])
    ]
    scale = (1.0 + 1e-10) / min(edge_distances)
    return [[scale * x, scale * y] for x, y in points]


def superellipse(exponent=1.55, aspect=1.0, count=64):
    """Convex soft diamond with four tapered tips and gently bowed flanks."""
    points = []
    for i in range(count):
        angle = 2.0 * math.pi * i / count
        c, s = math.cos(angle), math.sin(angle)
        points.append([
            math.copysign(abs(c) ** (2.0 / exponent), c),
            aspect * math.copysign(abs(s) ** (2.0 / exponent), s),
        ])
    return normalize_footprint(points)


def harmonic_footprint(harmonics, count=60):
    """Sample a support function h; h+h''>0 produces a strictly convex curve.

    Each harmonic is (frequency, amplitude, phase). The chosen styles have
    positive curvature radius everywhere, before polygon discretization.
    """
    points = []
    for i in range(count):
        angle = 2.0 * math.pi * i / count
        h = 1.0 + sum(
            amplitude * math.cos(frequency * angle + phase)
            for frequency, amplitude, phase in harmonics
        )
        derivative = sum(
            -frequency * amplitude * math.sin(frequency * angle + phase)
            for frequency, amplitude, phase in harmonics
        )
        c, s = math.cos(angle), math.sin(angle)
        points.append([h * c - derivative * s, h * s + derivative * c])
    return normalize_footprint(points)


def biconvex_lens(offset=0.15, count=64):
    """Intersect two offset circles, retaining two intentional pointed tips.

    Equal samples on each circular arc include each tip exactly once; the
    upper and lower tips distinguish this silhouette from an ellipse.
    """
    if count < 4 or count % 2:
        raise ValueError("Lens requires an even vertex count of at least four")
    radius = 1.0 + offset
    angle = math.acos(offset / radius)
    half = count // 2
    points = []
    for i in range(half):
        t = -angle + 2.0 * angle * i / half
        points.append([-offset + radius * math.cos(t), radius * math.sin(t)])
    for i in range(half):
        t = math.pi - angle + 2.0 * angle * i / half
        points.append([offset + radius * math.cos(t), radius * math.sin(t)])
    return normalize_footprint(points)


STYLES = [
    {
        "id": "09",
        "name": "Soft Diamond",
        "family": "superellipse",
        "description": (
            "Exponent-1.55 soft diamond with four tapered tips and bowed "
            "flanks; high shoulder and shallow, narrow roof taper."
        ),
        "points": superellipse(),
        "top_scale": 0.94,
        "shoulder_z": 19.8,
        "top_z": 21.2,
        "ruled": False,
        "color": (0.72, 0.76, 0.81),
    },
    {
        "id": "10",
        "name": "Soft Delta",
        "family": "rounded-triangle",
        "description": (
            "Three-fold support-function body with a softly triangular whole "
            "outline; low shoulder and deep, inward-sloping roof."
        ),
        "points": harmonic_footprint([(3, 0.085, math.pi / 2.0)]),
        "top_scale": 0.86,
        "shoulder_z": 18.9,
        "top_z": 22.6,
        "ruled": False,
        "color": (0.73, 0.80, 0.72),
    },
    {
        "id": "11",
        "name": "Soft Pentagon",
        "family": "five-fold-harmonic",
        "description": (
            "Fifth-harmonic support-function body with five soft tips and "
            "five bowed flanks; medium-height, gently drawn inward roof."
        ),
        "points": harmonic_footprint([(5, 0.038, -math.pi / 2.0)]),
        "top_scale": 0.90,
        "shoulder_z": 19.25,
        "top_z": 22.2,
        "ruled": False,
        "color": (0.79, 0.70, 0.65),
    },
    {
        "id": "12",
        "name": "Biconvex Lens",
        "family": "two-arc-lens",
        "description": (
            "Two circular arcs meet in intentional upper and lower tips, "
            "giving a lens-shaped body; high shoulder and strongly inset roof."
        ),
        "points": biconvex_lens(),
        "top_scale": 0.82,
        "shoulder_z": 19.6,
        "top_z": 23.0,
        "ruled": False,
        "color": (0.64, 0.74, 0.80),
    },
]
