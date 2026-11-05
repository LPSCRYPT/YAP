"""Shared whole-body assembly, collision checks, withdrawal checks and exports.

Extracted from the original atlas generator; explicit parameters replace the
former offset/theme/jewelry runtime AST and string transformations.
"""
import FreeCAD as App, FreeCADGui as Gui, Part, Mesh, MeshPart, math, json, os
from PySide import QtGui
from enclosure_runtime import document, new_document
from ThemeEnvelopeGeometry import inset as physical_inset

def carrier_trim(style):
    points=style["upper_footprint"] if style["kind"]=="split_level" else [[x*.99,y*.99] for x,y in style["footprint"]]
    points=physical_inset(points,1.7)
    vectors=[App.Vector(x,y,0) for x,y in points]
    return Part.Face(Part.makePolygon(vectors+[vectors[0]])).extrude(App.Vector(0,0,20))

def build_assembly(style, SRC, ROOT, R, document_pattern, make_envelope=None):
    V = App.Vector
    reports = []
    CLOSURE_OBSTACLES = Part.makeCompound([o.Shape for o in SRC.ComponentReferences.Group] + [o.Shape for o in SRC.RequiredHardware.Group])

    def box(x, y, z, w, l, h):
        return Part.makeBox(w, l, h, V(x, y, z))

    def cyl(x, y, z, r, h):
        return Part.makeCylinder(r, h, V(x, y, z))

    def moved(s, x=0, y=0, z=0):
        s = s.copy()
        s.translate(V(x, y, z))
        return s

    def inset(points, amount):
        lines = []
        for a, b in zip(points, points[1:] + points[:1]):
            dx = b[0] - a[0]
            dy = b[1] - a[1]
            length = math.hypot(dx, dy)
            nx = -dy / length
            ny = dx / length
            lines.append((a[0] + amount * nx, a[1] + amount * ny, dx, dy))
        result = []
        for p, q in zip(lines[-1:] + lines[:-1], lines):
            ax, ay, dx, dy = p
            bx, by, ex, ey = q
            den = dx * ey - dy * ex
            if abs(den) < 1e-10:
                result.append([bx, by])
                continue
            t = ((bx - ax) * ey - (by - ay) * ex) / den
            result.append([ax + t * dx, ay + t * dy])
        return result

    def wire(points, z, smooth):
        vs = [V(x, y, z) for x, y in points]
        if smooth:
            c = Part.BSplineCurve()
            c.interpolate(Points=vs, PeriodicFlag=True)
            return Part.Wire([c.toShape()])
        return Part.makePolygon(vs + [vs[0]])

    def section(points, z, factor=1, offset=0, smooth=False):
        p = [[x * R * factor, y * R * factor] for x, y in points]
        if offset:
            p = inset(p, offset)
        return wire(p, z, smooth)

    def ray(points, angle):
        dx = math.cos(angle)
        dy = math.sin(angle)
        hits = []
        for a, b in zip(points, points[1:] + points[:1]):
            ex = b[0] - a[0]
            ey = b[1] - a[1]
            den = dx * ey - dy * ex
            if abs(den) < 1e-09:
                continue
            t = (a[0] * ey - a[1] * ex) / den
            u = (a[0] * dy - a[1] * dx) / den
            if t > 0 and -1e-08 <= u <= 1 + 1e-08:
                hits.append(t)
        assert hits, 'ray misses contour'
        return min(hits) * R
    number = int(style['id'])
    name = style['name']
    points = style['points']
    smooth = not style['ruled']
    folder = '%02d-%s' % (number, name.replace(' ', '-'))
    out = ROOT + '/' + folder
    os.makedirs(out, exist_ok=True)
    if make_envelope is not None:
        outer, cavity = make_envelope(style)
        top = outer.BoundBox.ZMax
        outer_sections = [section(points, 0, smooth=False)]
    else:
        shoulder = max(20.1, float(style['shoulder_z']))
        top = max(shoulder + 1.2, float(style['top_z']))
        assert shoulder - 1.4 >= 18.7 - 1e-08
        outer_sections = [section(points, 0, smooth=smooth), section(points, 6, smooth=smooth), section(points, shoulder, 0.99, smooth=smooth)]
        inner_sections = [section(points, 1.4, 1, 1.4, smooth), section(points, 6, 1, 1.4, smooth), section(points, shoulder - 1.4, 0.99, 1.4, smooth)]
        roof_steps = 1 if style['family'] == 'cyberpunk' else 5
        for step in range(1, roof_steps + 1):
            QtGui.QApplication.processEvents()
            angle = math.pi * step / (2 * roof_steps)
            z = shoulder + (top - shoulder) * math.sin(angle)
            factor = float(style['top_scale']) + (0.99 - float(style['top_scale'])) * math.cos(angle)
            outer_sections.append(section(points, z, factor, smooth=smooth))
            inner_sections.append(section(points, z - 1.4, factor, 1.4, smooth))
        outer = Part.makeLoft(outer_sections, True, True)
        cavity = Part.makeLoft(inner_sections, True, True)
    assert outer.isValid() and cavity.isValid(), (name, 'envelopes')
    hood = outer.cut(cavity).common(box(-70, -70, 1.4, 140, 140, 40))
    base = outer.common(box(-70, -70, 0, 140, 140, 1.4))
    eye_y = 26.5 if style.get('source') == 'Sleek_Square' else 27
    base_features = SRC.FlatRearBase.Shape.common(cyl(0, 0, 1.4, 23.5, 7)).cut(cyl(0, eye_y, 1.4, 4.5, 8))
    base = base.fuse(base_features)
    closure = []
    for angle in [20, 145, 280]:
        QtGui.QApplication.processEvents()
        for delta in [0, 10, -10, 20, -20, 30, -30]:
            QtGui.QApplication.processEvents()
            a = math.radians(angle + delta)
            r = ray(points, a) - 2
            x, y = (r * math.cos(a), r * math.sin(a))
            if cyl(x, y, 1.4, 1.9, 20).common(CLOSURE_OBSTACLES).Volume < 0.001:
                break
        else:
            raise ValueError((name, 'no clear closure withdrawal column', angle))
        closure.append((x, y))
        hood = hood.fuse(cyl(x, y, 1.4, 1.6, 5.4).common(outer)).cut(cyl(x, y, 1.3, 0.65, 5.2))
        base = base.cut(cyl(x, y, 1.4, 1.85, 1.3)).cut(cyl(x, y, -0.1, 0.9, 1.6)).cut(Part.makeCone(1.6, 0.9, 0.7, V(x, y, 0)))
    for x in [-14, 14]:
        QtGui.QApplication.processEvents()
        base = base.cut(cyl(x, -15, -0.1, 1.6, 3.3))
    eye_x = style.get('eye_x', 0)
    ey = style.get('eye_y', ray(points, math.pi / 2) + 2.2)
    base = base.fuse(cyl(eye_x, ey, 0, 4, 2.5).cut(cyl(eye_x, ey, -0.1, 1.8, 2.7)))
    hood = hood.cut(cyl(eye_x, ey, 1.4, 4.2, 1.3))
    hood = hood.cut(box(-6, -65, 7.9, 12, 46, 5.2)).cut(Part.makeCylinder(1.5, 50, V(18, -5, 13), V(1, 0, 0)))
    for x in [-7.3, 7.3]:
        QtGui.QApplication.processEvents()
        hood = hood.cut(cyl(x, 14.3, 17, 0.6, 20))
    for x in [-2, 0, 2]:
        QtGui.QApplication.processEvents()
        for y in [2.5, 4.5, 6.5]:
            QtGui.QApplication.processEvents()
            hood = hood.cut(cyl(x, y, 17, 0.45, 20))
    hood = hood.cut(cyl(0, 0, 17, 1.1, 20)).removeSplitter()
    base = base.removeSplitter()
    d = new_document(document_pattern % number)
    d.Label = '%02d %s — %s' % (number, name, style['family'])
    color = tuple((float(v) for v in style['color']))

    def obj(n, s, c=color):
        o = d.addObject('Part::Feature', n)
        o.Shape = s
        o.ViewObject.ShapeColor = c
        o.ViewObject.DisplayMode = 'Shaded'
        return o
    printed = [obj('RearBase', base), obj('WholeBodyShell', hood)]
    for n in ['LowerCarrier', 'UpperCarrier', 'TopRetainer']:
        QtGui.QApplication.processEvents()
        s = SRC.getObject(n).Shape.copy()
        trim = carrier_trim(style) if make_envelope is not None else Part.Face(section(points, 0, 0.99, 1.7, smooth)).extrude(V(0, 0, 20))
        s = s.common(trim)
        for x, y in closure:
            QtGui.QApplication.processEvents()
            s = s.cut(cyl(x, y, 7, 1.9, 13))
        printed.append(obj(n, s.removeSplitter(), (0.23, 0.53, 0.48)))
    printed.append(obj('LightGuide', cyl(0, 0, 18.5, 0.8, top - 18.5).common(outer), (0.08, 0.55, 0.92)))
    for n in ['ClipReceiverAdapter', 'SlideOnClip']:
        QtGui.QApplication.processEvents()
        printed.append(obj(n, SRC.getObject(n).Shape.copy()))
    refs = d.addObject('App::DocumentObjectGroup', 'ComponentReferences')
    for original in SRC.ComponentReferences.Group:
        QtGui.QApplication.processEvents()
        refs.addObject(obj(original.Name, original.Shape.copy(), original.ViewObject.ShapeColor))
    hardware = d.addObject('App::DocumentObjectGroup', 'RequiredHardware')
    for original in SRC.RequiredHardware.Group:
        QtGui.QApplication.processEvents()
        hardware.addObject(obj(original.Name, original.Shape.copy(), original.ViewObject.ShapeColor))
    profile = obj('EditableFootprint', outer_sections[0])
    profile.ViewObject.Visibility = False
    profile.addProperty('App::PropertyString', 'ProfileDefinition')
    profile.ProfileDefinition = json.dumps(style)
    profile.addProperty('App::PropertyString', 'RegenerateWith')
    profile.RegenerateWith = 'Edit the source profile; rebuild through source/tools/build.py. Solid snapshots are not a PartDesign feature tree.'
    issues = []
    obstacles = [o.Shape for o in refs.Group] + [o.Shape for o in hardware.Group] + [box(16.05, -13.5, 1.9, 3, 4, 3), box(5, 3, 14.4, 4, 3, 3)]
    for o in printed:
        QtGui.QApplication.processEvents()
        if not o.Shape.isValid() or len(o.Shape.Solids) != 1:
            issues.append([o.Name, 'invalid/split', len(o.Shape.Solids)])
        for j, s in enumerate(obstacles):
            QtGui.QApplication.processEvents()
            if o.Name == 'RearBase' and len(refs.Group) <= j < len(refs.Group) + len(hardware.Group):
                continue
            v = o.Shape.common(s).Volume
            if v > 0.001:
                issues.append([o.Name, 'obstacle', j, v])
    for i, a in enumerate(printed):
        QtGui.QApplication.processEvents()
        for b in printed[i + 1:]:
            QtGui.QApplication.processEvents()
            v = a.Shape.common(b.Shape).Volume
            if v > 0.001:
                issues.append([a.Name, b.Name, v])
    for o in refs.Group:
        QtGui.QApplication.processEvents()
        if o.Name == 'LED':
            continue
        missing = o.Shape.cut(outer).Volume
        if missing > 0.001:
            issues.append([o.Name, 'outside', missing])
    assert not issues, (name, issues)
    hood.check(True)
    base.check(True)
    extraction_obstacles = Part.makeCompound([base] + [o.Shape for o in printed[2:5]] + obstacles)
    for dz in [0.2, 1, 3, 6, 10, 15, 22, 30]:
        QtGui.QApplication.processEvents()
        assert moved(hood, z=dz).common(extraction_obstacles).Volume < 0.001, (name, 'shell extraction', dz)
    for distance in [0, 0.5, 1, 4, 12, 25, 40]:
        QtGui.QApplication.processEvents()
        assert moved(SRC.SlideOnClip.Shape, y=-distance).common(base).Volume < 0.001, (name, 'clip release', distance)
    checks = []
    for i, o in enumerate(printed, 1):
        QtGui.QApplication.processEvents()
        s = o.Shape.copy()
        if i >= 7:
            s.rotate(V(), V(0, 1, 0), 90)
        bb = s.BoundBox
        s.translate(V(-bb.XMin, -bb.YMin, -bb.ZMin))
        m = MeshPart.meshFromShape(Shape=s, LinearDeflection=0.06, AngularDeflection=0.16, Relative=False)
        assert m.isSolid() and (not m.hasNonManifolds()) and (not m.hasSelfIntersections()), (name, o.Name, 'mesh')
        path = out + '/%02d-%s.stl' % (i, o.Name)
        m.write(path)
        check = Mesh.Mesh(path)
        assert check.isSolid() and (not check.hasNonManifolds()), path
        checks.append({'part': o.Name, 'closed_reimported_mesh': True, 'facets': check.CountFacets})
    for o in printed + list(refs.Group) + list(hardware.Group):
        QtGui.QApplication.processEvents()
        o.ViewObject.Visibility = o.Name in ['RearBase', 'WholeBodyShell', 'LightGuide']
    d.recompute()
    d.saveAs(out + '/Assembly.FCStd')
    Part.export(printed[:6], out + '/Necklace-Assembly.step')
    Part.export(printed[6:], out + '/Optional-Clip.step')
    bb = outer.BoundBox
    report = {'id': number, 'name': name, 'family': style['family'], 'description': style['description'], 'body_mm': [round(bb.XLength, 2), round(bb.YLength, 2), round(top, 2)], 'with_bail_length_mm': round(max(bb.YMax, ey + 4) - min(bb.YMin, ey - 4), 2), 'clip_thickness_mm': round(top + 12, 2), 'outer_volume_mm3': round(outer.Volume, 1), 'issues': issues, 'component_containment_checked': True, 'shell_extraction_samples': 8, 'clip_release_samples': 7, 'parts': checks, 'closure_centres_mm': closure}
    report['revision'] = 2
    report['profile_scale_mm'] = R
    reports.append(report)
    with open(out + '/verification.json', 'w') as f:
        json.dump(report, f, indent=2)
    with open(ROOT + '/progress.json', 'w') as f:
        json.dump(reports, f, indent=2)
    print('VERIFIED', folder, report['body_mm'], flush=True)
    return report
