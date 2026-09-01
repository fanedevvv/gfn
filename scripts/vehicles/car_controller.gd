extends VehicleBody3D
## car_controller.gd — Modulul 1: Controller de bază pentru toate vehiculele.
##
## Se atașează pe: rădăcina scenei vehiculului (VehicleBody3D) — vezi
## scenes/vehicles/base/car_base.tscn. Fiecare vehicul concret (sedan ruginit,
## SUV, dubă, sport) va moșteni această scenă de bază (Scene Inheritance) și
## va suprascrie doar masa, geometria și valorile @export specifice modelului.
##
## Noduri copil necesare:
##   CollisionShape3D          — forma caroseriei (BoxShape3D)
##   WheelFL, WheelFR           (VehicleWheel3D) — roți față, use_as_steering
##   WheelRL, WheelRR           (VehicleWheel3D) — roți spate, use_as_traction
##   (fiecare VehicleWheel3D poate avea un MeshInstance3D copil pentru vizual)
##
## Input Map necesar (Project Settings -> Input Map):
##   throttle, brake                          — acceleratoare (axe 0..1, suportă trigger analog)
##   steer_left, steer_right                  — direcție
##   shift_reverse, shift_neutral, shift_drive — selector R / N / D
##   shift_up, shift_down                     — trepte manuale 1-5 (mod MANUAL)
##   toggle_transmission_mode                 — comută Automat <-> Manual

const GEAR_REVERSE: int = -1
const GEAR_NEUTRAL: int = 0

enum DrivetrainType { RWD, FWD, AWD }
enum GearMode { AUTOMATIC, MANUAL }

## Emise în fiecare frame de fizică — HUD-ul (Modulul UI) se abonează la ele
## pentru turometru, vitezometru și indicatorul de treaptă.
signal speed_changed(speed_kmh: float)
signal rpm_changed(rpm: float)
signal gear_changed(gear_label: String)

@export_group("Tracțiune")
@export var drivetrain: DrivetrainType = DrivetrainType.RWD

@export_group("Motor")
@export var max_engine_force: float = 900.0
@export var idle_rpm: float = 800.0
@export var max_rpm: float = 6500.0

@export_group("Frâne")
@export var max_brake_force: float = 60.0

@export_group("Direcție")
@export var max_steer_angle_deg: float = 35.0
@export var min_steer_angle_at_speed_deg: float = 10.0
@export var steer_speed: float = 3.0            ## cât de repede se apropie de unghiul țintă
@export var steer_return_speed: float = 5.0      ## cât de repede revine la centru fără input
@export var steer_falloff_speed_kmh: float = 120.0 ## viteza la care unghiul de virare atinge minimul

@export_group("Transmisie")
@export var gear_ratios: Array[float] = [3.5, 2.2, 1.6, 1.2, 1.0]  ## trepte 1-5
@export var reverse_ratio: float = 3.2
@export var final_drive_ratio: float = 3.7

@onready var wheel_fl: VehicleWheel3D = $WheelFL
@onready var wheel_fr: VehicleWheel3D = $WheelFR
@onready var wheel_rl: VehicleWheel3D = $WheelRL
@onready var wheel_rr: VehicleWheel3D = $WheelRR

var current_gear: int = GEAR_NEUTRAL
var gear_mode: GearMode = GearMode.AUTOMATIC

var _current_steer_angle: float = 0.0
var _engine_rpm: float = 0.0
var _wheel_radius: float = 0.35


func _ready() -> void:
	# Raza roții e citită din roata din spate-stânga, nu duplicată într-un
	# @export separat — evită desincronizarea dacă cineva schimbă doar una.
	_wheel_radius = wheel_rl.wheel_radius
	center_of_mass_mode = VehicleBody3D.CENTER_OF_MASS_MODE_CUSTOM
	_configure_drivetrain()
	_set_gear(GEAR_NEUTRAL)


func _physics_process(delta: float) -> void:
	var throttle_input: float = Input.get_action_strength("throttle")
	var brake_input: float = Input.get_action_strength("brake")
	var steer_input: float = Input.get_axis("steer_left", "steer_right")

	_handle_gear_shifting_input()
	_update_steering(steer_input, delta)
	_update_drivetrain(throttle_input, brake_input, delta)
	_update_telemetry()


# ---------------------------------------------------------------------------
# TRACȚIUNE — configurează roțile motrice/directoare din enum-ul exportat
# ---------------------------------------------------------------------------

func _configure_drivetrain() -> void:
	wheel_fl.use_as_steering = true
	wheel_fr.use_as_steering = true
	wheel_rl.use_as_steering = false
	wheel_rr.use_as_steering = false

	var front_drive: bool = drivetrain == DrivetrainType.FWD or drivetrain == DrivetrainType.AWD
	var rear_drive: bool = drivetrain == DrivetrainType.RWD or drivetrain == DrivetrainType.AWD

	wheel_fl.use_as_traction = front_drive
	wheel_fr.use_as_traction = front_drive
	wheel_rl.use_as_traction = rear_drive
	wheel_rr.use_as_traction = rear_drive


# ---------------------------------------------------------------------------
# DIRECȚIE — revenire lină la centru + unghi redus la viteză mare
# ---------------------------------------------------------------------------

func _update_steering(steer_input: float, delta: float) -> void:
	var speed_ratio: float = clamp(abs(_get_forward_speed_kmh()) / steer_falloff_speed_kmh, 0.0, 1.0)
	var effective_max_steer: float = lerp(
		deg_to_rad(max_steer_angle_deg), deg_to_rad(min_steer_angle_at_speed_deg), speed_ratio
	)

	# NOTĂ: dacă mașina virează invers față de tastă în joc, schimbă semnul
	# de mai jos (convenția +/- pentru steering diferă în funcție de sensul
	# de orientare al caroseriei tale) — se ajustează o singură dată la test.
	var target_angle: float = -steer_input * effective_max_steer

	var rate: float = steer_speed if abs(steer_input) > 0.01 else steer_return_speed
	_current_steer_angle = move_toward(_current_steer_angle, target_angle, rate * delta)
	steering = _current_steer_angle


# ---------------------------------------------------------------------------
# MOTOR + TRANSMISIE — forță, RPM, tăiere la limitator
# ---------------------------------------------------------------------------

func _update_drivetrain(throttle_input: float, brake_input: float, delta: float) -> void:
	if gear_mode == GearMode.AUTOMATIC and current_gear >= 1:
		_update_automatic_shifting()

	var ratio: float = _get_current_gear_ratio()
	_update_engine_rpm(ratio, delta)

	if ratio == 0.0 or _engine_rpm >= max_rpm:
		engine_force = 0.0  # în N, sau la limitatorul de turație
	else:
		engine_force = throttle_input * max_engine_force * ratio

	brake = brake_input * max_brake_force


func _update_engine_rpm(ratio: float, delta: float) -> void:
	if ratio == 0.0:
		# În N, motorul turează liber, proporțional cu accelerația.
		var throttle: float = Input.get_action_strength("throttle")
		var target: float = lerp(idle_rpm, max_rpm, throttle)
		_engine_rpm = move_toward(_engine_rpm, target, 4000.0 * delta)
		return

	var wheel_rps: float = abs(_get_forward_speed_mps()) / (TAU * _wheel_radius)
	var target_rpm: float = max(idle_rpm, wheel_rps * 60.0 * abs(ratio) * final_drive_ratio)
	_engine_rpm = move_toward(_engine_rpm, target_rpm, 6000.0 * delta)


func _get_current_gear_ratio() -> float:
	if current_gear == GEAR_REVERSE:
		return -reverse_ratio
	if current_gear == GEAR_NEUTRAL:
		return 0.0
	return gear_ratios[current_gear - 1]


# ---------------------------------------------------------------------------
# SCHIMBĂTOR DE VITEZE — R / N / D (automat 1-5) + manual 1-5
# ---------------------------------------------------------------------------

func _handle_gear_shifting_input() -> void:
	if Input.is_action_just_pressed("toggle_transmission_mode"):
		gear_mode = GearMode.MANUAL if gear_mode == GearMode.AUTOMATIC else GearMode.AUTOMATIC

	if Input.is_action_just_pressed("shift_reverse"):
		_set_gear(GEAR_REVERSE)
	elif Input.is_action_just_pressed("shift_neutral"):
		_set_gear(GEAR_NEUTRAL)
	elif Input.is_action_just_pressed("shift_drive"):
		_set_gear(1)  # D pornește din prima treaptă; automatul urcă/coboară de acolo

	if gear_mode == GearMode.MANUAL and current_gear >= 1:
		if Input.is_action_just_pressed("shift_up"):
			_set_gear(min(current_gear + 1, gear_ratios.size()))
		elif Input.is_action_just_pressed("shift_down"):
			_set_gear(max(current_gear - 1, 1))


func _update_automatic_shifting() -> void:
	var upshift_rpm: float = max_rpm * 0.9
	var downshift_rpm: float = max_rpm * 0.4

	if _engine_rpm >= upshift_rpm and current_gear < gear_ratios.size():
		_set_gear(current_gear + 1)
	elif _engine_rpm <= downshift_rpm and current_gear > 1:
		_set_gear(current_gear - 1)


func _set_gear(gear: int) -> void:
	current_gear = gear
	gear_changed.emit(_get_gear_label())


func _get_gear_label() -> String:
	match current_gear:
		GEAR_REVERSE:
			return "R"
		GEAR_NEUTRAL:
			return "N"
		_:
			return ("D%d" % current_gear) if gear_mode == GearMode.AUTOMATIC else str(current_gear)


# ---------------------------------------------------------------------------
# TELEMETRIE — viteză reală (km/h) + RPM, transmise prin Signals către HUD
# ---------------------------------------------------------------------------

func _get_forward_speed_mps() -> float:
	return -global_transform.basis.z.dot(linear_velocity)


func _get_forward_speed_kmh() -> float:
	return _get_forward_speed_mps() * 3.6


func _update_telemetry() -> void:
	speed_changed.emit(abs(_get_forward_speed_kmh()))
	rpm_changed.emit(_engine_rpm)
