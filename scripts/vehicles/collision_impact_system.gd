class_name CollisionImpactSystem
extends Node
## collision_impact_system.gd — Modulul: consecințe la coliziune.
##
## Se atașează ca nod copil al vehiculului (CarController) — vezi
## car_base.tscn, unde e deja instanțiat și legat automat prin
## collision_impact_path. CarController îi transmite impulsurile de
## coliziune ale șasiului din propriul _integrate_forces() (singurul loc
## care poate citi PhysicsDirectBodyState3D — e un callback al
## RigidBody3D-ului însuși, nu poate fi primit direct de un nod copil).
##
## Design: la fel ca VehicleDamage/SurfaceGripSystem, componenta doar
## interpretează consecințele (pană la roată, semnal pentru economie/
## poliție) — nu scrie fizică, doar reacționează la ce raportează
## CarController.

signal impact(impulse_strength: float, local_position: Vector3)
signal severe_impact(impulse_strength: float, local_position: Vector3)

## Praguri de magnitudine a impulsului (unități native Godot — forță ×
## timpul de contact; nu sunt m/s). Calibrate empiric: sub minor, ignorăm
## (frecări/atingeri ușoare); peste severe, declanșăm pană automată.
@export var minor_impact_threshold: float = 400.0
@export var severe_impact_threshold: float = 1200.0

var _vehicle_damage: VehicleDamage = null


func _ready() -> void:
	var vehicle: CarController = get_parent() as CarController
	if vehicle == null:
		push_warning("CollisionImpactSystem: trebuie să fie copil al unui CarController.")
		return
	if vehicle.vehicle_damage_path != NodePath():
		_vehicle_damage = vehicle.get_node_or_null(vehicle.vehicle_damage_path) as VehicleDamage


## Apelată de CarController._integrate_forces() cu impulsul cel mai mare
## detectat pe șasiu în acest pas de fizică.
func report_impact(impulse_strength: float, local_position: Vector3) -> void:
	if impulse_strength < minor_impact_threshold:
		return

	impact.emit(impulse_strength, local_position)

	if impulse_strength >= severe_impact_threshold:
		severe_impact.emit(impulse_strength, local_position)
		_apply_severe_consequences(local_position)


func _apply_severe_consequences(local_position: Vector3) -> void:
	if _vehicle_damage == null:
		return
	# Pana lovește roata cea mai apropiată de punctul de impact — un
	# impact frontal-dreapta pancturează roata din față-dreapta, etc.
	var wheel_index: int = _closest_wheel_index(local_position)
	_vehicle_damage.puncture_tire(wheel_index, 0.6)


func _closest_wheel_index(local_position: Vector3) -> int:
	# Ordinea corespunde exact cu VehicleDamage.tire_pressures: 0=FL, 1=FR,
	# 2=RL, 3=RR. Poziții reale în car_base.tscn: FL/FR la z=-1.4, RL/RR la
	# z=+1.4 — indiferent de eticheta "față/spate" (mașina se deplasează pe
	# +Z local, deci axa RL/RR e cea care conduce efectiv; vezi nota
	# empirică din chase_camera.gd).
	var is_right: bool = local_position.x >= 0.0
	var is_rl_rr_axle: bool = local_position.z >= 0.0
	if is_rl_rr_axle:
		return 3 if is_right else 2
	return 1 if is_right else 0
