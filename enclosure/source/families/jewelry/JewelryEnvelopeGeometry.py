from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Image-specific physical enclosure treatments layered on checked body envelopes."""
import math,runpy
BASE=runpy.run_path(source_path('ThemeEnvelopeGeometry.py'))['make_envelope']

def make_envelope(style):
    if style.get('custom_module'):
        return runpy.run_path(style['custom_module'])['make_envelope'](style)
    import FreeCAD as App,Part
    V=App.Vector
    outer,cavity=BASE(style)
    if style.get('treatment')=='circuit_channels':
        top=style['top'];depth=.3;width=.55
        cavity=cavity.common(Part.makeBox(140,140,top-2,V(-70,-70,0)))
        paths=[[[-6,-8],[6,-8],[6,8],[-6,8],[-6,-8]]]
        pads=[]
        for sign in [-1,1]:
            for x in [-4.5,-1.5,1.5,4.5]:
                spread=5 if x>0 else -5
                path=[[x,sign*8],[x,sign*11],[x+spread,sign*16],[x+spread,sign*19]]
                paths.append(path);pads.append(path[-1])
            for y in [-5,-1.7,1.7,5]:
                spread=4 if y>0 else -4
                path=[[sign*6,y],[sign*11,y],[sign*16,y+spread],[sign*19,y+spread]]
                paths.append(path);pads.append(path[-1])
        cuts=[]
        for path in paths:
            for a,b in zip(path,path[1:]):
                dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy)
                nx,ny=-dy/length*width/2,dx/length*width/2
                vs=[V(a[0]+nx,a[1]+ny,top-depth),V(b[0]+nx,b[1]+ny,top-depth),V(b[0]-nx,b[1]-ny,top-depth),V(a[0]-nx,a[1]-ny,top-depth)]
                cuts.append(Part.Face(Part.makePolygon(vs+[vs[0]])).extrude(V(0,0,depth+.2)))
            for x,y in path:cuts.append(Part.makeCylinder(width/2,depth+.2,V(x,y,top-depth)))
        for x,y in pads:cuts.append(Part.makeCylinder(.65,depth+.2,V(x,y,top-depth)))
        cutter=cuts[0].multiFuse(cuts[1:]).removeSplitter()
        outer=outer.cut(cutter).removeSplitter()
    return outer,cavity
