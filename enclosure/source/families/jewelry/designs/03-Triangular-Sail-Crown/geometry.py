from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Hardware-covering lower sail with a true triangular lofted crown."""
import math
import runpy


def make_envelope(style):
    import FreeCAD as App
    import Part
    from itertools import combinations
    inset = runpy.run_path(source_path('ThemeEnvelopeGeometry.py'))['inset']
    lower = style['footprint']
    triangle = [[-23, 20], [23, -26], [23, 20]]
    points = [App.Vector(x, y, z) for z in [0, style['shoulder']] for x, y in lower]
    points += [App.Vector(x, y, style['top']) for x, y in triangle]
    # A planar convex hull avoids twisted ruled patches at the triangular tip.
    planes = {}
    for a, b, c in combinations(points, 3):
        normal = (b-a).cross(c-a)
        if normal.Length < 1e-8:
            continue
        normal.normalize()
        distances = [normal.dot(p-a) for p in points]
        if max(distances) <= 1e-7:
            pass
        elif min(distances) >= -1e-7:
            normal = -normal
        else:
            continue
        height = normal.dot(a)
        key = tuple(round(v, 7) for v in [normal.x, normal.y, normal.z, height])
        planes[key] = (normal, height)
    faces = []
    for normal, height in planes.values():
        vertices = [p for p in points if abs(normal.dot(p)-height) < 1e-7]
        centre = sum(vertices, App.Vector()) / len(vertices)
        u = vertices[0]-centre
        u.normalize()
        v = normal.cross(u)
        projected = sorted((u.dot(p-centre), v.dot(p-centre), i) for i, p in enumerate(vertices))
        def cross(a, b, c):
            return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
        bottom = []
        for p in projected:
            while len(bottom) > 1 and cross(bottom[-2], bottom[-1], p) <= 1e-8:
                bottom.pop()
            bottom.append(p)
        upper = []
        for p in reversed(projected):
            while len(upper) > 1 and cross(upper[-2], upper[-1], p) <= 1e-8:
                upper.pop()
            upper.append(p)
        boundary = [vertices[p[2]] for p in bottom[:-1]+upper[:-1]]
        faces.append(Part.Face(Part.makePolygon(boundary+boundary[:1])))
    outer = Part.makeSolid(Part.makeShell(faces)).removeSplitter()
    inner = [App.Vector(x,y,1.4) for x,y in inset(lower,1.4)]
    cavity = Part.Face(Part.makePolygon(inner+inner[:1])).extrude(App.Vector(0,0,17.8))
    return outer, cavity


def face_color(style, part_name, face):
    if part_name == 'WholeBodyShell' and face.BoundBox.ZLength < 1e-5 and abs(face.BoundBox.ZMin - style['top']) < 1e-5:
        return tuple(style['accent_color'])
    return None
