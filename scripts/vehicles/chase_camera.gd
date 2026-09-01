class_name ChaseCamera
extends Node3D
## chase_camera.gd — cameră de urmărire (third-person) pentru vehicule.
##
## Se atașează pe: rădăcina scenei "ChaseCamera" (Node3D) — vezi
## chase_camera.tscn. NU e copil al mașinii în arborele de scenă — dacă ar
## fi, ar moșteni tot ruliul/tangajul suspensiei (cameră de vomat).
## Urmărește ținta din script: poziția + doar direcția orizontală (yaw) a
## mașinii, ignorând complet înclinarea caroseriei.
##
## Noduri copil necesare (vezi chase_camera.tscn):
##   SpringArm3D (rotit 180° față de acest pivot — brațul "împinge" copiii
##                de-a lungul propriului -Z; rotit 180°, asta înseamnă în
##                spatele mașinii, nu în față. Lungimea se scurtează automat
##                dacă un perete intră între cameră și mașină.)
##     └── Camera3D (rotit încă 180° față de braț — anulează rotația
##                   brațului, ca să privească înainte, în direcția de
##                   mers, nu înapoi spre coada mașinii)
##
## Legare: apelează set_target(vehicle) din scena de joc — camera nu se
## leagă automat de nimic, la fel ca HUD-ul și Garage UI-ul.

@export var follow_distance: float = 7.0
@export var follow_height: float = 2.5
@export var position_smoothing: float = 6.0  ## cât de repede ajunge poziția din urmă
@export var yaw_smoothing: float = 4.0         ## cât de repede se aliniază la direcția mașinii

@onready var spring_arm: SpringArm3D = $SpringArm3D

var _target: Node3D = null
var _current_yaw: float = 0.0


func _ready() -> void:
	top_level = true  # poziția/rotația sunt mereu în spațiu global, indiferent unde e plasat nodul în arbore
	spring_arm.spring_length = follow_distance


func set_target(target: Node3D) -> void:
	_target = target
	if _target == null:
		return
	_current_yaw = _target_yaw()
	global_position = _desired_position()
	rotation = Vector3(0.0, _current_yaw, 0.0)


func clear_target() -> void:
	_target = null


func _physics_process(delta: float) -> void:
	if _target == null:
		return

	global_position = global_position.lerp(_desired_position(), clamp(position_smoothing * delta, 0.0, 1.0))
	_current_yaw = lerp_angle(_current_yaw, _target_yaw(), clamp(yaw_smoothing * delta, 0.0, 1.0))
	rotation = Vector3(0.0, _current_yaw, 0.0)


func _desired_position() -> Vector3:
	return _target.global_position + Vector3.UP * follow_height


func _target_yaw() -> float:
	var z_axis: Vector3 = _target.global_transform.basis.z
	return atan2(z_axis.x, z_axis.z)
