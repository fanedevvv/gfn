class_name TerrainSurface
extends StaticBody3D
## terrain_surface.gd — Modulul: aderență dinamică pe tip de suprafață.
##
## Se atașează pe orice teren fizic (drum, pietriș, noroi, zăpadă) ÎN LOCUL
## unui StaticBody3D simplu — SurfaceGripSystem (pe mașină) citește direct
## acest nod din VehicleWheel3D.get_contact_body(), fără layer de coliziune
## dedicat sau raycast suplimentar: fizica vehiculului calculează oricum
## contactul roată-teren, doar îl interpretăm.

enum SurfaceId { ASPHALT, GRAVEL, MUD, SNOW }

@export var surface_id: SurfaceId = SurfaceId.ASPHALT

## Înmulțește fricțiunea de bază a roții (wheel_friction_slip). ~1.0 =
## asfalt uscat, <1.0 = alunecos (pietriș, zăpadă, noroi).
@export var grip_multiplier: float = 1.0

## Frânare naturală suplimentară (0-1), aplicată ca penalizare asupra
## eficienței motorului — simulează efortul de a te mișca prin teren moale.
## 0 pentru asfalt/pietriș, >0 pentru noroi/zăpadă adâncă.
@export var rolling_resistance: float = 0.0
