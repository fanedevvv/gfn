class_name PolicePatrol
extends CharacterBody3D
## police_patrol.gd — Modulul Lume Activă: patrulă de poliție.
##
## Se atașează pe: rădăcina scenei "PolicePatrol" (CharacterBody3D) — vezi
## police_patrol.tscn. Mișcare cinematică (move_and_slide, fără fizică
## completă de vehicul), la fel ca TrafficCar — un sedan de poliție "de
## fundal" nu are nevoie de simulare completă.
##
## Două stări:
##   PATROL  — urmărește un Path3D (rută de patrulare), viteză normală.
##             Fără rută legată, stă pe loc până intră în URMĂRIRE.
##   PURSUIT — declanșată când WantedSystem.is_wanted() e true ȘI un
##             vehicul din grupul "player_vehicle" intră în raza de
##             detecție; conduce direct spre el. Renunță dacă jucătorul
##             nu mai e căutat SAU s-a îndepărtat prea mult.
##
## Noduri copil necesare (vezi police_patrol.tscn):
##   CollisionShape3D, BodyMesh (MeshInstance3D placeholder)

const GRAVITY: float = 9.8

enum State { PATROL, PURSUIT }

@export var patrol_speed: float = 8.0
@export var pursuit_speed: float = 16.0
@export var turn_speed: float = 4.0
@export var detection_range_m: float = 35.0
@export var pursuit_give_up_range_m: float = 80.0
@export var lookahead_distance_m: float = 12.0

@export_group("Rută de patrulare")
## Un Path3D opțional, desenat în editor. Fără el, patrula stă pe loc în
## PATROL (poate fi setat și din cod cu set_patrol_route()).
@export var patrol_route_path: NodePath

var state: State = State.PATROL

var _patrol_route: Path3D = null
var _pursuit_target: Node3D = null


func _ready() -> void:
	add_to_group("police_vehicle")

	if patrol_route_path != NodePath():
		_patrol_route = get_node_or_null(patrol_route_path) as Path3D


## Legare programatică a rutei de patrulare (util când ruta e construită
## din cod, nu desenată în editor — vezi open_world.gd).
func set_patrol_route(route: Path3D) -> void:
	_patrol_route = route


func _physics_process(delta: float) -> void:
	_update_state()

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	var target_position: Vector3 = _get_current_target()
	_move_toward_target(target_position, delta)

	move_and_slide()


# ---------------------------------------------------------------------------
# STARE — PATROL <-> PURSUIT, condusă de WantedSystem
# ---------------------------------------------------------------------------

func _update_state() -> void:
	match state:
		State.PATROL:
			var player: Node3D = _find_player_in_range(detection_range_m)
			if player != null and WantedSystem.is_wanted():
				state = State.PURSUIT
				_pursuit_target = player
		State.PURSUIT:
			if _pursuit_target == null or not is_instance_valid(_pursuit_target):
				state = State.PATROL
				return
			if not WantedSystem.is_wanted():
				state = State.PATROL
				_pursuit_target = null
				return
			if global_position.distance_to(_pursuit_target.global_position) > pursuit_give_up_range_m:
				state = State.PATROL
				_pursuit_target = null


func _find_player_in_range(range_m: float) -> Node3D:
	for player in get_tree().get_nodes_in_group("player_vehicle"):
		if player is Node3D and global_position.distance_to(player.global_position) <= range_m:
			return player
	return null


# ---------------------------------------------------------------------------
# MIȘCARE — direct spre țintă (fără NavigationAgent3D; teren deschis)
# ---------------------------------------------------------------------------

func _get_current_target() -> Vector3:
	if state == State.PURSUIT:
		return _pursuit_target.global_position

	if _patrol_route == null or _patrol_route.curve == null or _patrol_route.curve.get_baked_length() <= 0.0:
		return global_position  # nicio rută legată -> stă pe loc

	var curve: Curve3D = _patrol_route.curve
	var local_position: Vector3 = _patrol_route.to_local(global_position)
	var closest_offset: float = curve.get_closest_offset(local_position)
	var lookahead_offset: float = fmod(closest_offset + lookahead_distance_m, curve.get_baked_length())
	return _patrol_route.to_global(curve.sample_baked(lookahead_offset))


func _move_toward_target(target_position: Vector3, delta: float) -> void:
	var direction: Vector3 = target_position - global_position
	direction.y = 0.0

	if direction.length_squared() < 0.25:
		velocity.x = 0.0
		velocity.z = 0.0
		return

	direction = direction.normalized()
	var speed: float = pursuit_speed if state == State.PURSUIT else patrol_speed
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	var target_basis: Basis = global_transform.looking_at(global_position + direction, Vector3.UP).basis
	basis = basis.slerp(target_basis, clamp(turn_speed * delta, 0.0, 1.0))
