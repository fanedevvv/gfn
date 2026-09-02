class_name CarController
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

## Bitul de layer fizic dedicat traficului AI (vezi traffic_car.tscn,
## AnimatableBody3D.collision_layer = 2) — DELIBERAT separat de layer-ul 1
## (vehicule/sol). Găsit prin testare directă (tractare + trafic AI activ):
## dacă ORICE vehicul care nu e condus de jucător (o epavă tractată, o
## mașină parcată) are traficul în propriul collision_mask, ansamblul se
## poate bloca permanent — un vehicul complet nemișcat din trafic, la 40+ m
## distanță, fără nicio coliziune reală posibilă, tot declanșează blocajul.
## Cauza exactă n-a putut fi izolată la un parametru anume (nu ține de
## solver_iterations, sleep, contact_monitor sau bruschețea accelerației —
## toate testate individual); pare o interacțiune la nivelul broadphase-ului
## motorului fizic Godot, sensibilă la simpla PREZENȚĂ a unui corp cu
## layer-ul detectabil, nu la coliziunea reală. Soluția: doar vehiculul
## CONDUS ACTIV de jucător își adaugă acest bit în _ready() (mai jos) — el
## chiar trebuie să lovească fizic traficul; restul (epave, mașini tractate,
## trafic-ul între ele) nu au nevoie, și evitându-l elimină blocajul complet.
const TRAFFIC_COLLISION_LAYER_BIT: int = 2

enum DrivetrainType { RWD, FWD, AWD }
enum GearMode { AUTOMATIC, MANUAL }

## Emise în fiecare frame de fizică — HUD-ul (Modulul UI) se abonează la ele
## pentru turometru, vitezometru și indicatorul de treaptă.
signal speed_changed(speed_kmh: float)
signal rpm_changed(rpm: float)
signal gear_changed(gear_label: String)

@export_group("Control")
## False pentru un vehicul care NU trebuie să răspundă la tastatură (o
## mașină rablagită tractată, o epavă abia cumpărată de la Junkyard încă
## neintrată în ea). Fără asta, ORICE instanță CarController din scenă ar
## răspunde simultan la aceleași taste — citesc Input global, nu un canal
## per-vehicul. Descoperit direct testând tractarea: mașina "rablagită"
## pornea singură la accelerație, înainte să existe vreun joint funcțional.
@export var is_player_controlled: bool = true

@export_group("Tracțiune")
@export var drivetrain: DrivetrainType = DrivetrainType.RWD

@export_group("Motor")
## Tunat empiric (Godot 4.3 headless, VehicleBody3D real): 2800 dă 0-100 km/h
## în ~10.8s cu marjă sigură sub pragul de instabilitate (peste ~2800 combinat
## cu wheel_friction_slip mare, șasiul face wheelie/se răstoarnă — verificat).
@export var max_engine_force: float = 2800.0
@export var idle_rpm: float = 800.0
@export var max_rpm: float = 6500.0

@export_group("Frâne")
## Tunat empiric alături de max_engine_force — cu vechea valoare (60), oprirea
## din ~90 km/h dura 5.5s/30m (prea moale pentru motorul nou). 160 oprește în
## ~2.4s/14m, credibil fără să fie instant.
@export var max_brake_force: float = 160.0

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

@export_group("Componente opționale")
## Nod VehicleDamage (vezi scripts/vehicles/vehicle_damage.gd) — dacă e
## legat, uzura frânelor/ambreiajului/motorului influențează direct forța
## de tracțiune și de frânare. Lasă gol pentru un vehicul fără uzură.
@export var vehicle_damage_path: NodePath
## Nod SurfaceGripSystem (vezi scripts/vehicles/surface_grip_system.gd) —
## dacă e legat, rezistența de rulare a terenului (noroi/zăpadă) reduce
## eficiența motorului. Lasă gol pentru un vehicul fără aderență dinamică.
@export var surface_grip_path: NodePath
## Nod CollisionImpactSystem (vezi scripts/vehicles/collision_impact_system.gd)
## — dacă e legat, primește impulsurile de coliziune ale șasiului (citite
## aici, în _integrate_forces, singurul loc care are acces la
## PhysicsDirectBodyState3D). Lasă gol pentru un vehicul fără consecințe
## de coliziune (ex: mașini de trafic, care oricum nu au VehicleDamage).
@export var collision_impact_path: NodePath

@onready var wheel_fl: VehicleWheel3D = $WheelFL
@onready var wheel_fr: VehicleWheel3D = $WheelFR
@onready var wheel_rl: VehicleWheel3D = $WheelRL
@onready var wheel_rr: VehicleWheel3D = $WheelRR
@onready var _vehicle_damage: VehicleDamage = _resolve_vehicle_damage()
@onready var _surface_grip: SurfaceGripSystem = _resolve_surface_grip()
@onready var _collision_impact: CollisionImpactSystem = _resolve_collision_impact()

var current_gear: int = GEAR_NEUTRAL
var gear_mode: GearMode = GearMode.AUTOMATIC

var _current_steer_angle: float = 0.0
var _engine_rpm: float = 0.0
var _wheel_radius: float = 0.35


func _ready() -> void:
	if is_player_controlled:
		add_to_group("player_vehicle")  # necesar pentru zonele Workshop/Junkyard (Modulul de Economie)
		collision_mask |= TRAFFIC_COLLISION_LAYER_BIT  # vezi comentariul constantei — doar mașina condusă activ lovește traficul
	# Raza roții e citită din roata din spate-stânga, nu duplicată într-un
	# @export separat — evită desincronizarea dacă cineva schimbă doar una.
	_wheel_radius = wheel_rl.wheel_radius
	center_of_mass_mode = VehicleBody3D.CENTER_OF_MASS_MODE_CUSTOM
	_configure_drivetrain()
	_set_gear(GEAR_NEUTRAL)

	if _collision_impact:
		contact_monitor = true
		max_contacts_reported = 8


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _collision_impact == null:
		return

	# Contactele de aici sunt ale ȘASIULUI (CollisionShape3D-ul mașinii),
	# NU ale roților — VehicleWheel3D își calculează contactul cu solul
	# separat, prin propriul mecanism de suspensie, nu prin contact_monitor.
	# Dar șasiul TOT poate atinge solul direct — un colț care zgârie
	# asfaltul la o aterizare sau la o oscilație bruscă de suspensie.
	# Verificat empiric: o atingere de sol are normala aproape verticală
	# (~(0,1,0)), în timp ce un perete/obstacol are normala predominant
	# orizontală — filtrăm după asta, nu doar după magnitudinea impulsului.
	var max_impulse: float = 0.0
	var impact_position: Vector3 = Vector3.ZERO
	for i in state.get_contact_count():
		var normal: Vector3 = state.get_contact_local_normal(i)
		if absf(normal.y) > 0.5:
			continue  # aproape vertical -> șasiul a atins solul/o rampă, nu un obstacol

		var impulse: float = state.get_contact_impulse(i).length()
		if impulse > max_impulse:
			max_impulse = impulse
			impact_position = state.get_contact_local_position(i)

	if max_impulse > 0.0:
		_collision_impact.report_impact(max_impulse, impact_position)


func _resolve_vehicle_damage() -> VehicleDamage:
	if vehicle_damage_path == NodePath():
		return null
	return get_node_or_null(vehicle_damage_path) as VehicleDamage


func _resolve_collision_impact() -> CollisionImpactSystem:
	if collision_impact_path == NodePath():
		return null
	return get_node_or_null(collision_impact_path) as CollisionImpactSystem


func _resolve_surface_grip() -> SurfaceGripSystem:
	if surface_grip_path == NodePath():
		return null
	return get_node_or_null(surface_grip_path) as SurfaceGripSystem


func _physics_process(delta: float) -> void:
	var throttle_input: float = 0.0
	var brake_input: float = 0.0
	var steer_input: float = 0.0

	if is_player_controlled:
		throttle_input = Input.get_action_strength("throttle")
		brake_input = Input.get_action_strength("brake")
		steer_input = Input.get_axis("steer_left", "steer_right")
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

	# Semnul de mai jos e verificat empiric (Godot 4.3 headless, VehicleBody3D
	# real): apăsând steer_right, mașina curbează spre partea ei dreaptă
	# (+X local), exact cum trebuie — nu e o presupunere.
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

	# Uzura (dacă vehiculul are un nod VehicleDamage legat) reduce direct
	# forța de tracțiune (ambreiaj tocit / motor supraîncălzit) și eficiența
	# de frânare (plăcuțe uzate) — nu sunt doar cifre cosmetice.
	var engine_efficiency: float = _vehicle_damage.get_engine_efficiency() if _vehicle_damage else 1.0
	var brake_efficiency: float = _vehicle_damage.get_brake_efficiency() if _vehicle_damage else 1.0

	# La fel, dacă vehiculul are un SurfaceGripSystem legat, terenul moale
	# (noroi/zăpadă) fură din eficiența motorului — un singur loc (aici)
	# scrie engine_force, ca să nu existe conflict de ordine între noduri.
	if _surface_grip:
		engine_efficiency *= 1.0 - _surface_grip.get_rolling_resistance()

	if ratio == 0.0 or _engine_rpm >= max_rpm:
		engine_force = 0.0  # în N, sau la limitatorul de turație
	else:
		engine_force = throttle_input * max_engine_force * ratio * engine_efficiency

	brake = brake_input * max_brake_force * brake_efficiency


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
	# Verificat empiric: acest VehicleBody3D se deplasează pe +Z local sub
	# engine_force pozitiv (nu -Z, convenția obișnuită Node3D/Camera3D) —
	# fără minus în față, altfel viteza reală ar ieși negativă la mers înainte.
	# Momentan inofensiv oriunde e citită (mereu prin abs()), dar corect aici
	# evită o capcană dacă cineva folosește vreodată valoarea cu semn.
	return global_transform.basis.z.dot(linear_velocity)


func _get_forward_speed_kmh() -> float:
	return _get_forward_speed_mps() * 3.6


func _update_telemetry() -> void:
	speed_changed.emit(abs(_get_forward_speed_kmh()))
	rpm_changed.emit(_engine_rpm)
