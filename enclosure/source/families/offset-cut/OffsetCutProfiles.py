from enclosure_runtime import output_dir, source_path, artifact_path, document, new_document
"""Four whole-body refinements; no separate front inlays."""
import math

def normalize(points):
    distance=min((a[0]*b[1]-a[1]*b[0])/math.hypot(b[0]-a[0],b[1]-a[1]) for a,b in zip(points,points[1:]+points[:1]))
    return [[x/distance*1.000001,y/distance*1.000001] for x,y in points]

def soften(points,trim=0.12):
    result=[]
    for i,p in enumerate(points):
        previous=points[i-1];following=points[(i+1)%len(points)]
        lp=math.dist(previous,p);ln=math.dist(following,p)
        amount=min(trim,lp*.4,ln*.4)
        a=[p[j]+(previous[j]-p[j])*amount/lp for j in range(2)]
        b=[p[j]+(following[j]-p[j])*amount/ln for j in range(2)]
        for k in range(5):
            t=k/4
            result.append([(1-t)**2*a[j]+2*t*(1-t)*p[j]+t*t*b[j] for j in range(2)])
    return normalize(result)

compact=[(-.78,-1),(.58,-1),(1,-.58),(1,.75),(.75,1),(-.45,1),(-1,.45),(-1,-.78)]
slash=[(-.88,-1.04),(.44,-1.04),(1.08,-.40),(1.08,.86),(.90,1.04),(-.32,1.04),(-1.08,.28),(-1.08,-.84)]
taper=[(-.75,-1.04),(.45,-1.04),(.95,-.54),(1.08,.75),(.80,1.04),(-.40,1.04),(-1.08,.36),(-.94,-.83)]
STYLES=[]
for ident,name,points,top_scale,top,description in [
    ('01','Offset Compact',normalize(compact),.93,21.3,'Tight square footprint, unequal diagonal corners and a narrow chamfer; compact restrained version.'),
    ('02','Offset Slash',normalize(slash),.80,22.6,'Dominant upper-left diagonal, narrow opposite clips and a broad deep-cut roof bevel.'),
    ('03','Offset Taper',normalize(taper),.89,21.8,'Upper shoulders widen over a narrower base outline, retaining the asymmetric diagonal cut.'),
    ('04','Offset Soft',soften(compact,.18),.87,21.8,'Asymmetric clipped outline with physically softened perimeter corners and a rounded shoulder transition.'),
]:
    STYLES.append(dict(id=ident,name=name,points=points,top_scale=top_scale,top_z=top,shoulder_z=20.1,description=description,family='minimal' if ident=='04' else 'cyberpunk',ruled=True,color=(.30,.36,.41)))
