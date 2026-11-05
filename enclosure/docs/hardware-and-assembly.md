# Hardware contract and assembly

This contract describes the retained **Sleek and later** two-level architecture. Earlier families have different dimensions, retention and screws; their archived instructions remain authoritative for those artifacts. All dimensions below are millimeters. Modeled placement is not an independent measurement of the real part.

## Inputs: confirmed versus provisional

| Item | Evidence/contract | Remaining uncertainty |
| --- | --- | --- |
| Protected wrapped battery | Confirmed envelope **24.5 × 24.5 × 5**; modeled at Z 1.9–6.9. | Actual wiring/connector routing, tolerance and safe charging/thermal behavior. Nominal 0.4 upper clearance is not swelling accommodation. |
| XIAO ESP32-S3 | Board-only source geometry: 38 solids, approximately **22.48 × 17.78 × 4.46**. Modeled X ±8.89, Y −20.5…1.98, Z 8.2…12.66. | Real installation, solder joints, antenna routing and component tolerances still require fit inspection. This is source-CAD geometry, not proof of a physical assembly test. |
| Microphone PCBs | Two Ø14 envelopes retained from the layout; centers (±7.3, 14.3), nominal seat outer radius 7.9. | Thickness **3 assumed**; count is an inherited layout, not a requirement to use two microphones. Inlet direction/pads are unconfirmed; direct wires assumed, tall headers do not fit. |
| Speaker | Ø10 × 3 input envelope, center (0, 4.5), Z 14.4–17.4. | Actual rigid rim, leads, acoustic response and sealing need confirmation/testing. |
| Vibration motor | Ø10 envelope; one-sided **4 mm lead allowance confirmed**. Center (17.55, −4.5), outer seat radius 5.8. | Thickness **3 assumed**; restraint/pad and lead fit untested. |
| SD holder | Provisional **18 × 24 × 3**, rotated to 24 × 18 × 3; X ±12, Y −20…−2, Z 14.2–17.2. | Part not received when designed. Eight pins do not establish package, ejection travel, connector or card access. |
| Amplifier | Provisional 18 × 18 × 3; X ±9, Y 2.4…20.4, Z 8.2…11.2. | Actual board, components, connections. |
| Motor driver | Provisional 8 × 8 × 3; X −19.3…−11.3, Y 0…8. | Actual board and wiring. |
| Antenna | Provisional 8 × 16 × 1; X −20.8…−12.8, Y −5…11, Z 1.9–2.9. | RF keepout/efficiency, mounting and cable bend. |
| Battery connector | Provisional 6 × 8 × 4; X 12.8…18.8, Y 6…14, Z 1.9–5.9. | Actual connector, mating/removal space and leads. |
| LED | Modeled centered (0,0), Z 17.5–18.5; light guide starts at 18.5. | Actual optical coupling and brightness. Guide top is design-specific, clipped to sloping roofs. |
| Button | Provisional switch envelope and actuator opening. | Actual switch/actuator is not implemented or supplied as a functioning button mechanism. |

The retained hardware/fastener top is Z **18.7**. Round carrier radius is approximately 23.2. Square upper carriers are **40.6 × 42.6 rounded rectangles, R6.3**, not solid rectangular corners; original square cavity is 41.2 × 43.2, R6.6. The round microphone seats are clipped to radius 23.2; round motor holder to radius 23.4, square holder to X 23.1. These details matter when fitting asymmetric outlines. Source geometry and actual retention features, not only component bounding boxes, constrain trimming.

## Required nonprinted parts: modern two-level families

- Three **M2 × 14 countersunk carrier screws** into plastic pilots. Modeled head envelope approximately Ø4 × 1.2; carrier screw centers (−14,−15), (14,−15), (18,4). Confirm real heads and a suitable plastic-compatible thread. Raised heads or longer screws are not interchangeable.
- Three **M1.6 × 6 countersunk hood screws**, 1.3 plastic pilots; closure locations differ by design. No closure nuts/inserts are modeled. Avoid overtightening.
- Thin electrically insulating board bands, up to **3 wide and approximately 0.15 thick**. Driver band runs along Y; XIAO/amplifier bands along X. Ordinary thick cable ties do not fit. Use a secure insulating overlap without bearing on fragile chips or solder joints.
- Nominal **0.3 working-thickness insulating pads** at microphone/speaker rigid rims, motor and connector; **0.5** at SD bridge. These are modeled working gaps, not a qualified foam/preload specification. Never load the speaker diaphragm or SD eject mechanism.
- Removable insulating adhesive for the antenna. Electrical isolation, RF effects and adhesive aging remain untested.
- A translucent light guide or suitable optical rod matched to the chosen design; printed metallic-looking parts are not optical substitutes.
- A breakaway necklace cord. Standard later eye bore is nominal **3.6**; inset-face/dome variations use a **3.2 transverse bail**. Follow individual design notes for exceptions; no eye/bail load rating exists.

The battery sits on a raised flat support with rounded stops. **Never compress the pouch to close the enclosure, add foam that clamps it, or use a swollen battery.** Do not substitute longer screws or route wires across sharp edges/posts.

## Assembly and service: modern two-level families

1. Deburr, inspect and dry-fit printed interfaces before electronics. Check screw/insert fit on a print sample; do not force a binding clip or unsuitable screw.
2. Fit bottom-level antenna, motor and connector; place battery within its locators. Keep lead exits open and wires off the pouch, screw posts and closure paths.
3. Band XIAO/amplifier/driver to the lower carrier. Fit motor/connector pads and set the carrier on its posts.
4. Route insulated wires through carrier openings. Fit upper carrier, SD holder, microphones and speaker, with service slack for internal SD access.
5. Fit rim/SD pads and top retainer, then lightly secure the three carrier screws. **The hood is not the electronics clamp.**
6. Install LED and the design-matched light guide; lower hood vertically over the independently retained stack and secure its separate rear closure screws.
7. Fit the optional rear adapter/clip only when needed. For service, remove hood, then carrier screws and lift retainer/upper/lower carriers in order, disconnecting wires rather than pulling on them.

SD access is internal; no unconfirmed external ejection slot is promised. Always use parts from the same variant. Different closures, trimmed carriers, guide tops and eyes make cross-family mixing unsafe without rechecking.

### Optional clip: Sleek and descendants

The removable external receiver avoids the older recessed-track thickness penalty. Clip slides/latches tool-free; **returning to a fully flat rear requires removing the receiver's two screws**, without dismantling electronics. Module adds approximately **12** to body thickness. Receiver uses two M2 × 8 countersunk screws into flush M2 inserts at X ±14, Y −15; assumed insert envelope Ø3.2 × 3. Follow the actual insert manufacturer's pilot/heating guidance. Opposing carrier screws occupy the same posts with intentional axial separation.

Nominal allowances: approximately 0.305 minimum perpendicular flank clearance, 0.35 floor clearance, 0.4 per-side mouth clearance. Latch provides retention, not a forced rail fit. These are geometric allowances, not validated print tolerances or flexure life.

### Family-specific exceptions

- **Integrated slicer:** integrated receiver; choose one flush or clip insert, not both. Historical STEP intentionally shows both alternatives. Retention/wiring/acoustic seals unfinished.
- **Domed mounted:** integrated receiver and independent three-layer mounting; carrier screws nominal **M2 × 16**, not M2 × 14. Uses the family's own lid screws/pilots and eight-part set.
- **Compact bodies:** tall multi-carrier stack; report specifies **M2 × 25 carrier** and **M2 × 8 closure** screws. Do not apply the sleek screw lengths.
- **Inset face:** nine parts; insert face from inside hood. Flange catches front ledge; three retainer posts plus additional Ø2.4 pads of nominal 0.5 working thickness at (−18,−9), (18,−9), (0,20) capture it. Hold face when opening. Perimeter/flange radial clearance 0.3. Hood-mounted bail transfers necklace load through closure screws.
- **Dome variations:** nine parts; ring/spine/crescent inlay requires a thin compatible adhesive layer. Side allowance 0.25, floor allowance 0.15; do not add inset-face support posts/pads. Ports feed a common untuned cavity.

## Fabrication limits

Import matching STLs separately in millimeters at 100%; auto-arrange, do not scale the assembly. Bed normalization does not mean support-free. Inspect roofs, eyes, downward carrier restraints, small holes/band slots, rails and support-removal access in layer preview. PETG is a starting fit-test material, not an approved profile. No G-code is supplied.

Use nonconductive finishes unless electrical isolation and RF behavior are separately validated. Paint/glue must not block optical/acoustic ports, vents, pilots or sliding surfaces. No acoustic isolation ducts, tuned speaker cavity or waterproofing is established. See [verification limits](verification.md) before making a wearable.
