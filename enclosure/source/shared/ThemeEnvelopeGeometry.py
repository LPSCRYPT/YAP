from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Whole-body envelopes: inclined/folded roofs, offset tiers and shaped lofts."""
import math

def inset(points, amount):
    lines=[]
    for a,b in zip(points,points[1:]+points[:1]):
        dx,dy=b[0]-a[0],b[1]-a[1];length=math.hypot(dx,dy)
        lines.append((a[0]-amount*dy/length,a[1]+amount*dx/length,dx,dy))
    result=[]
    for p,q in zip(lines[-1:]+lines[:-1],lines):
        ax,ay,dx,dy=p;bx,by,ex,ey=q;den=dx*ey-dy*ex
        if abs(den)<1e-10:result.append([bx,by]);continue
        t=((bx-ax)*ey-(by-ay)*ex)/den
        result.append([ax+t*dx,ay+t*dy])
    return result

def make_envelope(style):
    import FreeCAD as App, Part
    V=App.Vector
    def wire(points,z):return Part.makePolygon([V(x,y,z) for x,y in points]+[V(*points[0],z)])
    def prism(points,z,h):return Part.Face(wire(points,z)).extrude(V(0,0,h))
    def scale(points,factor,centre=(0,0)):
        return [[centre[0]+(x-centre[0])*factor,centre[1]+(y-centre[1])*factor] for x,y in points]
    def loft(sections):return Part.makeLoft([wire(points,z) for points,z in sections],True,True)
    p=style['footprint'];kind=style['kind']
    if kind=='roof_planes':
        outer=prism(p,0,50);cavity=prism(inset(p,1.4),1.4,50)
        for intercept,sx,sy in style['roof_planes']:
            def above(c):
                corners=[(-80,-80),(80,-80),(80,80),(-80,80)]
                vs=[V(x,y,c+sx*x+sy*y) for x,y in corners]
                return Part.Face(Part.makePolygon(vs+[vs[0]])).extrude(V(0,0,100))
            outer=outer.cut(above(intercept))
            cavity=cavity.cut(above(intercept-1.4*math.sqrt(1+sx*sx+sy*sy)))
        return outer.removeSplitter(),cavity.removeSplitter()
    if kind=='split_level':
        upper=style['upper_footprint'];height=style['lower_height'];seam=style['seam_height'];depth=style['seam_inset'];top=style['upper_height']
        centre=style.get('upper_center',[1,-.5]);shoulder=20.1
        outer_sections=[(p,0),(p,height-.2),(inset(p,depth),height),(inset(p,depth),height+seam),(upper,height+seam+.2),(upper,shoulder)]
        inner_sections=[(inset(p,1.4),1.4),(inset(p,1.4),height-1.8),(inset(upper,1.6),height-.2),(inset(upper,1.6),shoulder-1.4)]
        for i in range(1,5):
            a=math.pi*i/8;factor=.94+.06*math.cos(a);z=shoulder+(top-shoulder)*math.sin(a)
            roof=scale(upper,factor,centre)
            outer_sections.append((roof,z));inner_sections.append((inset(roof,1.6),z-1.4))
        return loft(outer_sections),loft(inner_sections)
    if kind=='profile_loft':
        shoulder=style['shoulder'];top=style['top'];ratio=style['top_scale'];shift=style.get('top_shift',[0,0])
        outer_sections=[(p,0),(p,6),(scale(p,.99),shoulder)]
        inner_sections=[(inset(p,1.4),1.4),(inset(p,1.4),6),(inset(scale(p,.99),1.4),shoulder-1.4)]
        steps=style.get('roof_steps',1)
        for i in range(1,steps+1):
            a=math.pi*i/(2*steps);factor=ratio+(.99-ratio)*math.cos(a);z=shoulder+(top-shoulder)*math.sin(a)
            roof=[[x*factor+shift[0]*math.sin(a),y*factor+shift[1]*math.sin(a)] for x,y in p]
            outer_sections.append((roof,z));inner_sections.append((inset(roof,1.4),z-1.4))
        return loft(outer_sections),loft(inner_sections)
    raise ValueError('Unknown envelope kind: '+kind)
