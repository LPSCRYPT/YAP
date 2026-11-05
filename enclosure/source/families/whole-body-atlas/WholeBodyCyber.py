from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Restrained faceted whole-body profiles, normalized around a unit disk."""

from math import hypot


def normalized_polygon(vertices):
    """Uniformly scale a CCW convex polygon to circumscribe the unit disk."""
    edge_distances = [
        (a[0] * b[1] - a[1] * b[0]) / hypot(b[0] - a[0], b[1] - a[1])
        for a, b in zip(vertices, vertices[1:] + vertices[:1])
    ]
    scale = 1.000001 / min(edge_distances)
    return [[x * scale, y * scale] for x, y in vertices]


def clipped_slab():
    """Broad rectilinear sides with four deliberate, equal corner clips."""
    return normalized_polygon([
        (-0.800, -1.000), (0.800, -1.000),
        (1.075, -0.725), (1.075, 0.725),
        (0.800, 1.000), (-0.800, 1.000),
        (-1.075, 0.725), (-1.075, -0.725),
    ])


def blunt_shield():
    """Upright shoulders taper through two facets into a broad flat toe."""
    return normalized_polygon([
        (-0.240, -1.080), (0.240, -1.080),
        (0.820, -0.700), (1.040, -0.100),
        (1.040, 0.650), (0.700, 1.020),
        (-0.700, 1.020), (-1.040, 0.650),
        (-1.040, -0.100), (-0.820, -0.700),
    ])


def reverse_keystone():
    """Long splayed sides widen toward a clipped, broad upper shoulder."""
    return normalized_polygon([
        (-0.650, -1.040), (0.650, -1.040),
        (0.880, -0.820), (1.120, 0.720),
        (0.880, 1.040), (-0.880, 1.040),
        (-1.120, 0.720), (-0.880, -0.820),
    ])


def offset_cut():
    """Unequal opposing diagonal cuts create an asymmetric chisel outline."""
    return normalized_polygon([
        (-0.780, -1.020), (0.500, -1.020),
        (1.080, -0.440), (1.080, 0.620),
        (0.700, 1.020), (-0.320, 1.020),
        (-1.030, 0.310), (-1.030, -0.750),
    ])


STYLES = [
    {
        "id": "05",
        "name": "Clipped Slab",
        "family": "cyberpunk",
        "description": "Wide clipped rectangular body with eight planar sides and a short, decisive roof chamfer; no face ornament.",
        "points": clipped_slab(),
        "top_scale": 0.91,
        "shoulder_z": 19.9,
        "top_z": 21.1,
        "ruled": True,
        "color": (0.25, 0.28, 0.31),
    },
    {
        "id": "06",
        "name": "Blunt Shield",
        "family": "cyberpunk",
        "description": "Ten-sided shield body with broad upper shoulders, two-stage lower taper, and a flat wearable toe; a deep inward roof fold reinforces the shield silhouette.",
        "points": blunt_shield(),
        "top_scale": 0.85,
        "shoulder_z": 19.0,
        "top_z": 22.8,
        "ruled": True,
        "color": (0.30, 0.33, 0.32),
    },
    {
        "id": "07",
        "name": "Reverse Keystone",
        "family": "cyberpunk",
        "description": "Clipped keystone body whose long flanks splay toward a broad upper edge; a shallow lateral inset and taller roof bevel retain its architectural silhouette.",
        "points": reverse_keystone(),
        "top_scale": 0.96,
        "shoulder_z": 20.0,
        "top_z": 22.5,
        "ruled": True,
        "color": (0.39, 0.40, 0.42),
    },
    {
        "id": "08",
        "name": "Offset Cut",
        "family": "cyberpunk",
        "description": "Asymmetric eight-sided body with a long upper-left slash, shorter opposing lower-right cut, and unequal remaining corner clips; low shoulders lead into a substantial planar roof taper.",
        "points": offset_cut(),
        "top_scale": 0.88,
        "shoulder_z": 18.9,
        "top_z": 22.1,
        "ruled": True,
        "color": (0.24, 0.29, 0.34),
    },
]
