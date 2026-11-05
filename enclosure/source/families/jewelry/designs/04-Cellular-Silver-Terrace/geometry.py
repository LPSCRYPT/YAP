from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Terraced square enclosure with a backed, rounded organic-cell relief."""
import runpy


def make_envelope(style):
    import FreeCAD as App
    import Part
    base = runpy.run_path(source_path('ThemeEnvelopeGeometry.py'))['make_envelope']
    outer, cavity = base(style)
    cavity = cavity.common(Part.makeBox(140, 140, 19.0, App.Vector(-70, -70, 0)))

    def rounded_face(points, z, fraction=0.20):
        vertices = []
        for index, point in enumerate(points):
            previous, following = points[index-1], points[(index+1)%len(points)]
            a = [point[j]+fraction*(previous[j]-point[j]) for j in range(2)]
            b = [point[j]+fraction*(following[j]-point[j]) for j in range(2)]
            # Fine planar segments make the pocket-wall Booleans more robust.
            for step in range(9):
                t = step/8
                xy = [(1-t)**2*a[j]+2*t*(1-t)*point[j]+t*t*b[j] for j in range(2)]
                vertices.append(App.Vector(xy[0],xy[1],z))
        return Part.Face(Part.makePolygon(vertices+vertices[:1]))

    island = rounded_face([[-17, -17.5], [17, -17.5], [17, 17.5], [-17, 17.5]], 21.55, 0.08).extrude(App.Vector(0, 0, 1.05))
    outer = outer.fuse(island)
    cells = [
        [[-14, -14], [-4, -14], [-6, -8], [-13, -5]],
        [[-14, -2], [-7, -5], [-4, -1], [-6, 6], [-14, 9]],
        [[-14, 12], [-10, 10], [-10, 15], [-14, 15]],
        [[-7, 10], [-4, 10], [-1, 15], [-4.5, 15]],
        [[2, -14], [14, -14], [14, -9], [7, -6], [2, -9]],
        [[-2, -6], [3, -5], [4, -2], [-1, -2]],
        [[8, -3], [14, -6], [14, 4], [7, 8], [5, 4], [5, 1]],
        [[7, 10], [14, 7], [14, 15], [10, 15]],
        [[-1, 10], [2, 10], [4.5, 15], [1, 15]]
    ]
    cutters = [rounded_face(points, 20.4).extrude(App.Vector(0, 0, 3.0)) for points in cells]
    outer = outer.cut(Part.makeCompound(cutters)).removeSplitter()
    return outer, cavity


def face_color(style, part_name, face):
    if part_name != 'WholeBodyShell':
        return None
    bounds = face.BoundBox
    if bounds.ZLength < 1e-5 and abs(bounds.ZMin - 20.4) < 1e-5:
        return (0.28, 0.29, 0.275)
    if bounds.ZMin > 21.81:
        return tuple(style['accent_color'])
    return None
