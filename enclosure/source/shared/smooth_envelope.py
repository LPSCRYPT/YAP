"""Shared C2 smooth-envelope factory, extracted without executing a builder."""
import FreeCAD as App, Part, math
V=App.Vector
TOP=25.0
def envelope(inset=0):
 side=[V(25.5-inset,0,0),V(27.5-inset,0,6),V(27.5-inset,0,14-inset),V(26-inset,0,18.8-inset)]
 elevated=[]
 for i in range(6):
  p=V()
  for j in range(max(0,i-2),min(3,i)+1):p+=side[j]*(math.comb(3,j)*math.comb(2,i-j)/math.comb(5,i))
  elevated.append(p)
 first=(side[3]-side[2])*3;second=(side[3]-side[2]*2+side[1])*6
 front=[side[3],side[3]+first/5]
 front.append(second/20+front[1]*2-front[0])
 front += [V(16-inset,0,TOP-inset),V(8-inset/2,0,TOP-inset),V(0,0,TOP-inset)]
 curve=Part.BSplineCurve();curve.buildFromPolesMultsKnots(elevated+front[1:],[6,5,6],[0,1,2],False,5)
 assert curve.removeKnot(2,3,1e-8),'C2 profile join'
 wire=Part.Wire([curve.toShape(),Part.makeLine(front[-1],V()),Part.makeLine(V(),side[0])])
 s=Part.Face(wire).revolve(V(),V(0,0,1),360)
 assert s.isValid() and len(s.Solids)==1,'envelope validity'
 s.check(True)
 return s,curve
