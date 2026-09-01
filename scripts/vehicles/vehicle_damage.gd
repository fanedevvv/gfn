class_name VehicleDamage
extends Node
## vehicle_damage.gd — Modulul: uzura pieselor mecanice, legată de cutia
## de viteze prin uzura ambreiajului la schimbări proaste de treaptă.
##
## Se atașează pe: un Node simplu, COPIL direct al vehiculului (CarController
## / VehicleBody3D) — vezi car_base.tscn, unde e deja instanțiat și legat
## automat prin vehicle_damage_path = "VehicleDamage".
##
## Design: nu duplică nicio logică de fizică — citește RPM-ul prin semnalul
## deja expus de CarController (rpm_changed/gear_changed) și proprietățile
## publice native ale VehicleBody3D (linear_velocity). Expune înapoi doar
## două metode "get efficiency" pe care car_controller.gd le citește opțional
## ca să aplice consecințe reale în fizică (mai puțină forță/frânare).
##
## Pentru atelier (Modulul de Economie, viitor): repair_brakes(),
## repair_clutch(), refill_oil(), inflate_tire() resetează stările.

signal brake_wear_changed(percent: float)
signal clutch_wear_changed(percent: float)
signal engine_temperature_changed(celsius: float)
signal oil_level_changed(percent: float)
signal tire_pressure_changed(wheel_index: int, bar: float)
signal engine_overheated()
signal part_broke_down(part_name: String)

@export_group("Frâne")
@export var brake_wear_rate: float = 0.4              ## % pierdut/secundă la frânare intensă, la viteză mare
@export var brake_wear_speed_threshold_kmh: float = 40.0 ## sub asta, uzura e neglijabilă

@export_group("Ambreiaj")
@export var clutch_wear_per_bad_shift: float = 3.0     ## % pierdut la o schimbare proastă (mod Manual)
@export var clutch_ideal_rpm_ratio: float = 0.55        ## % din max_rpm considerat "schimbare ideală"
@export var clutch_tolerance_ratio: float = 0.15        ## marjă de toleranță în jurul RPM-ului ideal

@export_group("Motor")
@export var ambient_temperature_c: float = 20.0
@export var overheat_temperature_c: float = 115.0
@export var heating_rate: float = 6.0    ## °C/s la sarcină maximă
@export var cooling_rate: float = 3.0    ## °C/s la ralanti/motor oprit

@export_group("Ulei")
@export var oil_consumption_per_second: float = 0.015
@export var low_oil_threshold_percent: float = 20.0
@export var low_oil_heat_multiplier: float = 1.8   ## motorul se supraîncălzește mai repede cu ulei puțin

@export_group("Presiune roți")
@export var tire_count: int = 4
@export var tire_pressure_full_bar: float = 2.3
@export var tire_leak_rate_bar_per_second: float = 0.0008  ## scurgere naturală lentă

var brake_wear_percent: float = 100.0
var clutch_wear_percent: float = 100.0
var engine_temperature_c: float = 20.0
var oil_level_percent: float = 100.0
var tire_pressures: Array[float] = []

@onready var _vehicle: CarController = get_parent() as CarController

var _last_rpm: float = 0.0
var _has_overheated: bool = false


func _ready() -> void:
	engine_temperature_c = ambient_temperature_c
	tire_pressures.resize(tire_count)
	tire_pressures.fill(tire_pressure_full_bar)

	if _vehicle == null:
		push_warning("VehicleDamage: nu are un CarController ca părinte, dezactivat.")
		set_process(false)
		return

	_vehicle.rpm_changed.connect(_on_rpm_changed)
	_vehicle.gear_changed.connect(_on_gear_changed)


func _process(delta: float) -> void:
	_update_brake_wear(delta)
	_update_engine_temperature(delta)
	_update_oil_level(delta)
	_update_tire_pressures(delta)


# ---------------------------------------------------------------------------
# CITITĂ DE car_controller.gd — consecințe reale în fizică
# ---------------------------------------------------------------------------

## Randament de frânare (0.15-1.0). Frânele complet uzate tot opresc mașina,
## doar mult mai prost — niciodată zero, ca să rămână controlabil.
func get_brake_efficiency() -> float:
	return clamp(brake_wear_percent / 100.0, 0.15, 1.0)


## Randament de tracțiune (0-1), combinând supraîncălzirea motorului
## (limp mode peste pragul critic) și patinarea unui ambreiaj tocit.
func get_engine_efficiency() -> float:
	var thermal_efficiency: float = 1.0
	if engine_temperature_c >= overheat_temperature_c:
		var overheat_ratio: float = clamp((engine_temperature_c - overheat_temperature_c) / 20.0, 0.0, 1.0)
		thermal_efficiency = lerp(1.0, 0.35, overheat_ratio)

	var clutch_efficiency: float = clamp(clutch_wear_percent / 100.0, 0.5, 1.0)

	return thermal_efficiency * clutch_efficiency


# ---------------------------------------------------------------------------
# FRÂNE
# ---------------------------------------------------------------------------

func _update_brake_wear(delta: float) -> void:
	if brake_wear_percent <= 0.0 or _vehicle == null:
		return

	var speed_kmh: float = _vehicle.linear_velocity.length() * 3.6
	var brake_intensity: float = _vehicle.brake / max(_vehicle.max_brake_force, 0.001)

	if speed_kmh < brake_wear_speed_threshold_kmh or brake_intensity <= 0.01:
		return

	var wear: float = brake_wear_rate * brake_intensity * (speed_kmh / brake_wear_speed_threshold_kmh) * delta
	brake_wear_percent = max(0.0, brake_wear_percent - wear)
	brake_wear_changed.emit(brake_wear_percent)

	if brake_wear_percent <= 0.0:
		part_broke_down.emit("brakes")


# ---------------------------------------------------------------------------
# AMBREIAJ — legătura directă cu cutia de viteze
# ---------------------------------------------------------------------------

func _on_gear_changed(_label: String) -> void:
	if _vehicle == null or _vehicle.gear_mode != CarController.GearMode.MANUAL:
		return
	if _vehicle.current_gear < 1:
		return  # R/N nu implică ambreiajul în acest model simplificat

	var rpm_ratio: float = _last_rpm / max(_vehicle.max_rpm, 1.0)
	var deviation: float = abs(rpm_ratio - clutch_ideal_rpm_ratio)

	if deviation <= clutch_tolerance_ratio:
		return  # schimbare "curată", fără uzură suplimentară

	var wear: float = clutch_wear_per_bad_shift * (deviation / clutch_tolerance_ratio)
	clutch_wear_percent = max(0.0, clutch_wear_percent - wear)
	clutch_wear_changed.emit(clutch_wear_percent)

	if clutch_wear_percent <= 0.0:
		part_broke_down.emit("clutch")


# ---------------------------------------------------------------------------
# MOTOR — temperatură, în funcție de sarcină (RPM) și nivelul de ulei
# ---------------------------------------------------------------------------

func _on_rpm_changed(rpm: float) -> void:
	_last_rpm = rpm


func _update_engine_temperature(delta: float) -> void:
	if _vehicle == null:
		return

	var load_ratio: float = clamp(_last_rpm / max(_vehicle.max_rpm, 1.0), 0.0, 1.0)
	var oil_penalty: float = low_oil_heat_multiplier if oil_level_percent <= low_oil_threshold_percent else 1.0

	if load_ratio > 0.15:
		engine_temperature_c += heating_rate * load_ratio * oil_penalty * delta
	else:
		engine_temperature_c -= cooling_rate * delta

	engine_temperature_c = clamp(engine_temperature_c, ambient_temperature_c, overheat_temperature_c + 20.0)
	engine_temperature_changed.emit(engine_temperature_c)

	if engine_temperature_c >= overheat_temperature_c and not _has_overheated:
		_has_overheated = true
		engine_overheated.emit()
		part_broke_down.emit("engine")
	elif engine_temperature_c < overheat_temperature_c:
		_has_overheated = false


# ---------------------------------------------------------------------------
# ULEI
# ---------------------------------------------------------------------------

func _update_oil_level(delta: float) -> void:
	if oil_level_percent <= 0.0 or _last_rpm <= 0.0:
		return
	oil_level_percent = max(0.0, oil_level_percent - oil_consumption_per_second * delta)
	oil_level_changed.emit(oil_level_percent)


# ---------------------------------------------------------------------------
# PRESIUNE ROȚI — scurgere naturală lentă; pana e declanșată extern
# ---------------------------------------------------------------------------

func _update_tire_pressures(delta: float) -> void:
	for i in tire_pressures.size():
		if tire_pressures[i] <= 0.0:
			continue
		tire_pressures[i] = max(0.0, tire_pressures[i] - tire_leak_rate_bar_per_second * delta)
		tire_pressure_changed.emit(i, tire_pressures[i])


## Apelată extern (coliziune cu moloz, hazard de teren — module viitoare)
## când o roată se pancturează brusc.
func puncture_tire(wheel_index: int, severity: float = 1.0) -> void:
	if wheel_index < 0 or wheel_index >= tire_pressures.size():
		return
	tire_pressures[wheel_index] = max(0.0, tire_pressures[wheel_index] - severity * tire_pressure_full_bar)
	tire_pressure_changed.emit(wheel_index, tire_pressures[wheel_index])


# ---------------------------------------------------------------------------
# REPARAȚII — hook-uri pentru bancul de lucru din atelier (Modulul de Economie)
# ---------------------------------------------------------------------------

func repair_brakes() -> void:
	brake_wear_percent = 100.0
	brake_wear_changed.emit(brake_wear_percent)


func repair_clutch() -> void:
	clutch_wear_percent = 100.0
	clutch_wear_changed.emit(clutch_wear_percent)


func refill_oil() -> void:
	oil_level_percent = 100.0
	oil_level_changed.emit(oil_level_percent)


func inflate_tire(wheel_index: int) -> void:
	if wheel_index < 0 or wheel_index >= tire_pressures.size():
		return
	tire_pressures[wheel_index] = tire_pressure_full_bar
	tire_pressure_changed.emit(wheel_index, tire_pressures[wheel_index])
