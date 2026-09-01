class_name PressureSystem
extends Node
## pressure_system.gd — Modulul 3: simulează presiunea unui generator/vană
## din baraj. Presiunea urcă natural în timp; dacă atinge pragul critic,
## pornește un cronometru de defecțiune — dacă nu e rezolvată la timp,
## emite `failure_critical` (Modulul 4 va conecta asta la inundare/game over).
##
## Se atașează pe: un Node simplu (nu are nevoie de transform 3D propriu),
## plasat oriunde în arborele nivelului — vezi pressure_system.tscn.
##
## Legare tipică într-un nivel:
##   - PressureGauge.pressure_system_path -> acest nod (pentru afișaj)
##   - repair_object_path (export de mai jos) -> Valve-ul care rezolvă
##     defecțiunea; sau apelează manual resolve_failure() din alt script.

enum State { NORMAL, CRITICAL }

@export_group("Presiune")
@export var rise_rate: float = 1.5           ## unități/secundă în stare NORMAL
@export var rise_rate_variance: float = 0.5   ## zgomot aleator peste rise_rate
@export var critical_threshold: float = 85.0  ## 0-100
@export var starting_pressure: float = 20.0

@export_group("Defecțiune")
@export var time_to_flood: float = 45.0       ## secunde disponibile după ce devine critic
@export var critical_rise_rate: float = 0.8    ## presiunea continuă să urce și în CRITICAL

@export_group("Legare opțională")
## Un Interactable (ex: Valve) al cărui semnal `interacted` rezolvă automat
## defecțiunea. Lasă gol dacă preferi să apelezi resolve_failure() manual.
@export var repair_object_path: NodePath

signal pressure_changed(ratio: float)          ## 0.0-1.0, pentru cadrane
signal failure_started(time_remaining: float)
signal failure_resolved()
signal failure_critical()                      ## neprevenit la timp -> inundare

var state: State = State.NORMAL
var pressure: float = 0.0

var _time_remaining: float = 0.0
var _flood_triggered: bool = false


func _ready() -> void:
	pressure = starting_pressure
	_emit_pressure_changed()

	if repair_object_path != NodePath():
		var repair_node: Node = get_node_or_null(repair_object_path)
		if repair_node and repair_node.has_signal("interacted"):
			repair_node.interacted.connect(_on_repair_object_interacted)


func _process(delta: float) -> void:
	match state:
		State.NORMAL:
			pressure += (rise_rate + randf_range(-rise_rate_variance, rise_rate_variance)) * delta
			pressure = clamp(pressure, 0.0, 100.0)
			_emit_pressure_changed()
			if pressure >= critical_threshold:
				_start_failure()
		State.CRITICAL:
			pressure = min(100.0, pressure + critical_rise_rate * delta)
			_emit_pressure_changed()
			_time_remaining -= delta
			if _time_remaining <= 0.0 and not _flood_triggered:
				_trigger_flood()


## Apelată extern (direct sau prin repair_object_path) când defecțiunea a
## fost reparată. Nu are efect dacă sistemul nu e în stare CRITICAL.
func resolve_failure() -> void:
	if state != State.CRITICAL:
		return
	state = State.NORMAL
	pressure = starting_pressure
	_flood_triggered = false
	_emit_pressure_changed()
	failure_resolved.emit()


func get_pressure_ratio() -> float:
	return pressure / 100.0


func get_time_remaining() -> float:
	return _time_remaining


func _start_failure() -> void:
	state = State.CRITICAL
	_time_remaining = time_to_flood
	failure_started.emit(_time_remaining)


func _trigger_flood() -> void:
	_flood_triggered = true
	failure_critical.emit()


func _emit_pressure_changed() -> void:
	pressure_changed.emit(get_pressure_ratio())


func _on_repair_object_interacted(_player: Node3D) -> void:
	resolve_failure()
