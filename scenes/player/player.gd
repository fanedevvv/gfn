extends CharacterBody3D
## player.gd — Modulul 1: Player Controller 3D
##
## Se atașează pe: rădăcina scenei "Player" (CharacterBody3D).
## Noduri copil necesare (vezi player.tscn pentru ierarhia completă):
##   Head (Node3D)
##     └─ Camera3D
##          ├─ Flashlight (SpotLight3D)
##          └─ InteractionRay (RayCast3D)
##   CollisionShape3D (CapsuleShape3D)
##   FootstepPlayer (AudioStreamPlayer3D)
##   CrankAudioPlayer (AudioStreamPlayer3D)
##
## Input Map necesar (Project Settings -> Input Map), sugestii de taste:
##   move_forward (W), move_back (S), move_left (A), move_right (D)
##   sprint (Shift), crouch (Ctrl)
##   interact (E)
##   toggle_flashlight (F)
##   recharge_flashlight (R, hold)
##   ui_cancel (Esc, există implicit)

const GRAVITY: float = 9.8

enum MoveState { IDLE, WALK, SPRINT, CROUCH }

@export_group("Movement")
@export var walk_speed: float = 3.0
@export var sprint_speed: float = 5.5
@export var crouch_speed: float = 1.5
@export var acceleration: float = 8.0
@export var friction: float = 10.0
@export var crouch_transition_speed: float = 8.0

@export_group("Camera")
@export var mouse_sensitivity: float = 0.0025
@export var pitch_min_deg: float = -80.0
@export var pitch_max_deg: float = 80.0
@export var head_height_standing: float = 1.6
@export var head_height_crouch: float = 1.0
@export var head_bob_walk_frequency: float = 9.0
@export var head_bob_sprint_frequency: float = 14.0
@export var head_bob_amplitude: float = 0.045

@export_group("Flashlight")
@export var flashlight_max_battery: float = 100.0
@export var flashlight_drain_per_second: float = 1.8
@export var flashlight_crank_charge_rate: float = 14.0
@export var flashlight_crank_noise_interval: float = 0.2

@export_group("Noise")
@export var noise_radius_walk: float = 5.0
@export var noise_radius_sprint: float = 11.0
@export var noise_radius_crouch: float = 1.5
@export var noise_radius_crank: float = 16.0
@export var footstep_interval_walk: float = 0.55
@export var footstep_interval_sprint: float = 0.35
@export var footstep_interval_crouch: float = 0.85

@export_group("Interaction")
@export var interaction_distance: float = 2.5

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Camera3D/Flashlight
@onready var interaction_ray: RayCast3D = $Head/Camera3D/InteractionRay
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var footstep_player: AudioStreamPlayer3D = $FootstepPlayer
@onready var crank_audio_player: AudioStreamPlayer3D = $CrankAudioPlayer

var _current_move_state: MoveState = MoveState.IDLE
var _camera_pitch: float = 0.0
var _bob_time: float = 0.0
var _footstep_timer: float = 0.0
var _crank_noise_timer: float = 0.0
var _standing_capsule_height: float = 1.8

var is_crouching: bool = false
var flashlight_on: bool = false
var flashlight_battery: float = 100.0
var is_charging_flashlight: bool = false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	flashlight_battery = flashlight_max_battery
	flashlight.visible = false
	interaction_ray.target_position = Vector3(0.0, 0.0, -interaction_distance)

	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule:
		_standing_capsule_height = capsule.height


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_handle_mouse_look(event)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("interact"):
		_try_interact()
	elif event.is_action_pressed("toggle_flashlight"):
		_toggle_flashlight()


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_update_crouch(delta)
	_handle_movement(delta)
	_update_head_bob(delta)
	move_and_slide()


func _process(delta: float) -> void:
	_handle_flashlight_battery(delta)
	_handle_flashlight_charging(delta)


# ---------------------------------------------------------------------------
# MIȘCARE
# ---------------------------------------------------------------------------

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0


func _handle_movement(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var is_moving: bool = direction.length() > 0.01

	_current_move_state = _resolve_move_state(is_moving)
	var target_speed: float = _speed_for_state(_current_move_state)
	var target_velocity: Vector3 = direction * target_speed

	# Accelerăm spre viteza țintă când există input, altfel frânăm spre 0.
	var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	var rate: float = acceleration if is_moving else friction
	horizontal_velocity = horizontal_velocity.move_toward(target_velocity, rate * delta)

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	if is_moving and is_on_floor():
		_emit_footstep_noise(delta)
	else:
		_footstep_timer = 0.0


func _resolve_move_state(is_moving: bool) -> MoveState:
	if not is_moving:
		return MoveState.IDLE
	if is_crouching:
		return MoveState.CROUCH
	if Input.is_action_pressed("sprint"):
		return MoveState.SPRINT
	return MoveState.WALK


func _speed_for_state(state: MoveState) -> float:
	match state:
		MoveState.SPRINT:
			return sprint_speed
		MoveState.CROUCH:
			return crouch_speed
		MoveState.WALK:
			return walk_speed
		_:
			return 0.0


func _update_crouch(delta: float) -> void:
	# Nu putem sta în picioare dacă tavanul e prea jos deasupra capului.
	is_crouching = Input.is_action_pressed("crouch")

	var target_head_y: float = head_height_crouch if is_crouching else head_height_standing
	head.position.y = lerp(head.position.y, target_head_y, crouch_transition_speed * delta)

	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule:
		var crouch_ratio: float = head_height_crouch / head_height_standing
		var target_height: float = _standing_capsule_height * (crouch_ratio if is_crouching else 1.0)
		capsule.height = lerp(capsule.height, target_height, crouch_transition_speed * delta)
		collision_shape.position.y = capsule.height * 0.5


# ---------------------------------------------------------------------------
# CAMERĂ / MOUSE LOOK / HEAD BOB
# ---------------------------------------------------------------------------

func _handle_mouse_look(event: InputEventMouseMotion) -> void:
	rotate_y(-event.relative.x * mouse_sensitivity)
	_camera_pitch = clamp(
		_camera_pitch - event.relative.y * mouse_sensitivity,
		deg_to_rad(pitch_min_deg),
		deg_to_rad(pitch_max_deg)
	)
	head.rotation.x = _camera_pitch


func _update_head_bob(delta: float) -> void:
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()

	if horizontal_speed > 0.1 and is_on_floor():
		var frequency: float = head_bob_sprint_frequency if _current_move_state == MoveState.SPRINT else head_bob_walk_frequency
		_bob_time += delta * frequency
		camera.position.y = sin(_bob_time) * head_bob_amplitude
	else:
		_bob_time = 0.0
		camera.position.y = lerp(camera.position.y, 0.0, 8.0 * delta)


# ---------------------------------------------------------------------------
# ZGOMOT — raportare către SoundManager (ascultat de AI în Modulul 2)
# ---------------------------------------------------------------------------

func _emit_footstep_noise(delta: float) -> void:
	_footstep_timer -= delta
	if _footstep_timer > 0.0:
		return

	var interval: float
	var radius: float
	var intensity: float

	match _current_move_state:
		MoveState.SPRINT:
			interval = footstep_interval_sprint
			radius = noise_radius_sprint
			intensity = 1.0
		MoveState.CROUCH:
			interval = footstep_interval_crouch
			radius = noise_radius_crouch
			intensity = 0.2
		_:
			interval = footstep_interval_walk
			radius = noise_radius_walk
			intensity = 0.5

	_footstep_timer = interval
	footstep_player.play()
	SoundManager.emit_noise(global_position, radius, intensity)


# ---------------------------------------------------------------------------
# LANTERNĂ — baterie + reîncărcare prin manivelă (zgomotoasă)
# ---------------------------------------------------------------------------

func _toggle_flashlight() -> void:
	if flashlight_battery <= 0.0:
		flashlight_on = false
		flashlight.visible = false
		return
	flashlight_on = not flashlight_on
	flashlight.visible = flashlight_on


func _handle_flashlight_battery(delta: float) -> void:
	if flashlight_on and not is_charging_flashlight:
		flashlight_battery = max(0.0, flashlight_battery - flashlight_drain_per_second * delta)
		if flashlight_battery <= 0.0:
			flashlight_on = false
			flashlight.visible = false


func _handle_flashlight_charging(delta: float) -> void:
	is_charging_flashlight = Input.is_action_pressed("recharge_flashlight") and flashlight_battery < flashlight_max_battery

	if not is_charging_flashlight:
		if crank_audio_player.playing:
			crank_audio_player.stop()
		return

	flashlight_battery = min(flashlight_max_battery, flashlight_battery + flashlight_crank_charge_rate * delta)

	if not crank_audio_player.playing:
		crank_audio_player.play()

	# Manivela e cel mai zgomotos lucru pe care jucătorul îl poate face —
	# emite zgomot repetat cât timp e ținută apăsată.
	_crank_noise_timer -= delta
	if _crank_noise_timer <= 0.0:
		_crank_noise_timer = flashlight_crank_noise_interval
		SoundManager.emit_noise(global_position, noise_radius_crank, 1.0)


# ---------------------------------------------------------------------------
# INTERACȚIUNE — RayCast3D din centrul camerei
# ---------------------------------------------------------------------------

func _try_interact() -> void:
	if not interaction_ray.is_colliding():
		return

	var collider: Object = interaction_ray.get_collider()
	if collider and collider.has_method("interact"):
		collider.interact(self)
