class_name SurfaceGripSystem
extends Node
## surface_grip_system.gd — Modulul: aderență dinamică pe tip de suprafață.
##
## Se atașează ca nod copil al vehiculului (CarController) — vezi
## car_base.tscn, unde e deja instanțiat și legat automat prin
## surface_grip_path. În fiecare frame de fizică, citește pe ce
## TerrainSurface stă fiecare roată (VehicleWheel3D.get_contact_body(),
## deja calculat de fizica vehiculului) și ajustează live
## wheel_friction_slip — fără layere de coliziune noi, fără raycast propriu.
##
## Design: la fel ca VehicleDamage, NU scrie direct în engine_force/brake
## ale mașinii (ar intra în conflict cu ce scrie car_controller.gd în
## același frame, în funcție de ordinea de procesare a nodurilor). Expune
## doar get_rolling_resistance(), citită opțional de CarController și
## combinată cu eficiența motorului — un singur loc scrie fizica finală.

signal surface_changed(surface_id: int)  ## -1 = fără contact sau teren fără TerrainSurface

@onready var _vehicle: CarController = get_parent() as CarController

var _wheels: Array[VehicleWheel3D] = []
var _base_friction: float = 6.0
var _rolling_resistance: float = 0.0
var _current_surface_id: int = -1


func _ready() -> void:
	if _vehicle == null:
		push_warning("SurfaceGripSystem: trebuie să fie copil al unui CarController.")
		set_physics_process(false)
		return

	# Roțile sunt căutate direct prin get_node(), NU citite din
	# _vehicle.wheel_fl — acelea sunt @onready pe CarController (părintele),
	# iar Godot rulează _ready() la copii înaintea părintelui, deci ar fi
	# încă nule în acest moment.
	_wheels = [
		_vehicle.get_node("WheelFL") as VehicleWheel3D,
		_vehicle.get_node("WheelFR") as VehicleWheel3D,
		_vehicle.get_node("WheelRL") as VehicleWheel3D,
		_vehicle.get_node("WheelRR") as VehicleWheel3D,
	]
	_base_friction = _wheels[0].wheel_friction_slip


## Penalizare 0-1, citită de CarController și înmulțită în eficiența
## motorului (1.0 - resistance) — 0 pe asfalt, mai mare pe noroi/zăpadă.
func get_rolling_resistance() -> float:
	return _rolling_resistance


func get_current_surface_id() -> int:
	return _current_surface_id


func _physics_process(_delta: float) -> void:
	var resistance_sum: float = 0.0
	var contact_count: int = 0
	# Pornesc de la ultima stare cunoscută, nu de la -1/0 — pe suspensie
	# rigidă, e normal ca toate cele 4 roți să raporteze simultan "fără
	# contact" pentru un singur frame de fizică (mic salt la accelerație
	# bruscă); fără asta, suprafața ar "pâlpâi" la -1 și înapoi în fiecare
	# astfel de frame, deranjant pentru orice UI/sunet legat mai târziu.
	var dominant_surface: int = _current_surface_id
	var dominant_grip: float = -1.0

	for wheel in _wheels:
		if not wheel.is_in_contact():
			wheel.wheel_friction_slip = _base_friction
			continue

		var surface: TerrainSurface = wheel.get_contact_body() as TerrainSurface
		var grip_mult: float = surface.grip_multiplier if surface else 1.0
		wheel.wheel_friction_slip = _base_friction * grip_mult

		contact_count += 1
		if surface:
			resistance_sum += surface.rolling_resistance
			if grip_mult >= dominant_grip:
				dominant_grip = grip_mult
				dominant_surface = surface.surface_id

	# Aceeași logică: dacă niciun contact acest frame, păstrez ultima
	# rezistență cunoscută în loc să sar la 0 pentru un singur frame.
	if contact_count > 0:
		_rolling_resistance = resistance_sum / contact_count

	if dominant_surface != _current_surface_id:
		_current_surface_id = dominant_surface
		surface_changed.emit(dominant_surface)
