extends CharacterBody3D
## silt_ai.gd — Modulul 2: AI-ul "The Silt" (entitate oarbă, ghidată de sunet)
##
## Se atașează pe: rădăcina scenei "Silt" (CharacterBody3D).
## Noduri copil necesare (vezi silt.tscn):
##   CollisionShape3D (CapsuleShape3D)
##   MeshInstance3D (placeholder — se înlocuiește cu model/animații reale)
##   NavigationAgent3D
##
## Dependință: necesită un NavigationRegion3D cu navmesh copt în nivel
## (vine în Modulul 3). Fără el, NavigationAgent3D nu poate calcula drumuri.
##
## Contract cu Modulul 1: Player-ul trebuie să fie în grupul "player"
## (add_to_group("player") — deja adăugat în player.gd) ca să poată fi
## detectat prin coliziune în starea HUNTING.

const GRAVITY: float = 9.8

enum State { PATROL, INVESTIGATING, HUNTING }

## Emis de fiecare dată când entitatea își schimbă starea — util pentru
## debug, audio stingers sau HUD de tensiune (Modulul 4).
signal state_changed(new_state: State)

## Emis când, în starea HUNTING, entitatea intră în coliziune cu jucătorul.
signal player_caught(player: Node3D)

@export_group("Movement")
@export var patrol_speed: float = 1.2
@export var investigate_speed: float = 2.0
@export var hunt_speed: float = 4.5
@export var turn_speed: float = 6.0

@export_group("Patrol")
## Noduri Marker3D plasate manual în nivel (galeriile). Dacă rămâne gol,
## entitatea va patrula puncte aleatoare în jurul poziției de spawn —
## util pentru testare înainte ca nivelurile din Modulul 3 să existe.
@export var patrol_point_paths: Array[NodePath] = []
@export var patrol_fallback_radius: float = 10.0
@export var patrol_wait_time_min: float = 2.0
@export var patrol_wait_time_max: float = 5.0

@export_group("Hearing / Suspicion")
@export var suspicion_gain_base: float = 25.0
@export var suspicion_decay_rate: float = 6.0
@export var max_suspicion: float = 100.0
@export var investigate_threshold: float = 20.0
@export var hunt_threshold: float = 70.0
@export var investigate_give_up_time: float = 12.0

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

var current_state: State = State.PATROL

var _suspicion: float = 0.0
var _time_since_heard_sound: float = 0.0
var _last_heard_position: Vector3 = Vector3.ZERO

var _patrol_points: Array[Node3D] = []
var _current_patrol_point: Node3D = null
var _patrol_wait_timer: float = 0.0
var _spawn_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	_spawn_position = global_position

	for path in patrol_point_paths:
		var node := get_node_or_null(path)
		if node is Node3D:
			_patrol_points.append(node)

	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.8

	SoundManager.noise_emitted.connect(_on_noise_emitted)

	# NavigationServer3D sincronizează harta abia după primul frame de fizică;
	# dacă cerem un target mai devreme, pathfinding-ul poate eșua silențios.
	await get_tree().physics_frame
	_enter_state(State.PATROL)


func _physics_process(delta: float) -> void:
	_update_suspicion(delta)
	_apply_gravity(delta)

	match current_state:
		State.PATROL:
			_process_patrol(delta)
		State.INVESTIGATING:
			_move_toward_nav_target(investigate_speed, delta)
		State.HUNTING:
			_move_toward_nav_target(hunt_speed, delta)

	move_and_slide()
	_check_player_collision()


# ---------------------------------------------------------------------------
# AUZ — reacție la SoundManager.noise_emitted
# ---------------------------------------------------------------------------

func _on_noise_emitted(origin: Vector3, radius: float, intensity: float) -> void:
	var distance: float = global_position.distance_to(origin)
	if distance > radius:
		return  # sunetul nu ajunge până aici

	_last_heard_position = origin
	_time_since_heard_sound = 0.0

	# Cu cât sursa e mai aproape de raza ei maximă de auz, cu atât câștigul
	# de suspiciune e mai mare — un sunet chiar lângă entitate e alarmant
	# instant; unul la marginea razei abia se observă.
	var proximity_factor: float = clamp(1.0 - (distance / radius), 0.0, 1.0)
	var gain: float = intensity * suspicion_gain_base * (0.5 + proximity_factor)
	_suspicion = min(max_suspicion, _suspicion + gain)

	if _suspicion >= hunt_threshold:
		if current_state != State.HUNTING:
			_enter_state(State.HUNTING)
		else:
			nav_agent.target_position = _last_heard_position
	elif _suspicion >= investigate_threshold:
		if current_state == State.PATROL:
			_enter_state(State.INVESTIGATING)
		elif current_state == State.INVESTIGATING:
			nav_agent.target_position = _last_heard_position


func _update_suspicion(delta: float) -> void:
	_time_since_heard_sound += delta
	_suspicion = max(0.0, _suspicion - suspicion_decay_rate * delta)

	match current_state:
		State.HUNTING:
			if _suspicion < hunt_threshold:
				_enter_state(State.INVESTIGATING)
		State.INVESTIGATING:
			if _suspicion < investigate_threshold or _time_since_heard_sound > investigate_give_up_time:
				_enter_state(State.PATROL)


# ---------------------------------------------------------------------------
# MAȘINA DE STĂRI
# ---------------------------------------------------------------------------

func _enter_state(new_state: State) -> void:
	current_state = new_state

	match new_state:
		State.PATROL:
			_pick_new_patrol_target()
		State.INVESTIGATING, State.HUNTING:
			nav_agent.target_position = _last_heard_position

	state_changed.emit(new_state)


# ---------------------------------------------------------------------------
# MIȘCARE
# ---------------------------------------------------------------------------

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0


func _process_patrol(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		velocity.x = 0.0
		velocity.z = 0.0
		_patrol_wait_timer -= delta
		if _patrol_wait_timer <= 0.0:
			_pick_new_patrol_target()
		return

	_move_toward_nav_target(patrol_speed, delta)


func _move_toward_nav_target(speed: float, delta: float) -> void:
	if nav_agent.is_navigation_finished():
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var next_point: Vector3 = nav_agent.get_next_path_position()
	var direction: Vector3 = next_point - global_position
	direction.y = 0.0

	if direction.length_squared() < 0.0001:
		return

	direction = direction.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	_face_direction(direction, delta)


func _face_direction(direction: Vector3, delta: float) -> void:
	var target_basis: Basis = global_transform.looking_at(global_position + direction, Vector3.UP).basis
	basis = basis.slerp(target_basis, clamp(turn_speed * delta, 0.0, 1.0))


func _pick_new_patrol_target() -> void:
	var target_point: Vector3

	if not _patrol_points.is_empty():
		var candidates: Array[Node3D] = _patrol_points.filter(func(p: Node3D) -> bool: return p != _current_patrol_point)
		if candidates.is_empty():
			candidates = _patrol_points
		_current_patrol_point = candidates[randi() % candidates.size()]
		target_point = _current_patrol_point.global_position
	else:
		target_point = _pick_random_nav_point(_spawn_position, patrol_fallback_radius)

	nav_agent.target_position = target_point
	_patrol_wait_timer = randf_range(patrol_wait_time_min, patrol_wait_time_max)


func _pick_random_nav_point(center: Vector3, radius: float) -> Vector3:
	var random_offset := Vector3(randf_range(-radius, radius), 0.0, randf_range(-radius, radius))
	var map_rid: RID = nav_agent.get_navigation_map()
	return NavigationServer3D.map_get_closest_point(map_rid, center + random_offset)


# ---------------------------------------------------------------------------
# CONTACT CU JUCĂTORUL
# ---------------------------------------------------------------------------

func _check_player_collision() -> void:
	if current_state != State.HUNTING:
		return

	for i in get_slide_collision_count():
		var collision: KinematicCollision3D = get_slide_collision(i)
		var collider: Object = collision.get_collider()
		if collider is Node3D and collider.is_in_group("player"):
			player_caught.emit(collider)
			return
