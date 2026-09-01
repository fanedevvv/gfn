extends Node3D
## pressure_gauge.gd — Modulul 3: cadran vizual care afișează presiunea
## unui PressureSystem din nivel. Se montează pe panoul din Camera de
## Control (sau se vede printr-o cameră CCTV, în bucata următoare).
##
## Se atașează pe: rădăcina scenei "PressureGauge" (Node3D).
## Noduri copil necesare (vezi pressure_gauge.tscn):
##   DialMesh (MeshInstance3D) — fața fixă a cadranului
##   Needle (Node3D) -> NeedleMesh (MeshInstance3D) — acul, se rotește pe Z
##   WarningLight (OmniLight3D) — clipește roșu cât timp sistemul e CRITICAL
##
## Design: nu știe nimic despre Valve sau reparații — ascultă exclusiv
## semnalele PressureSystem-ului legat. Complet decuplat de mecanica de
## reparare, ca să poată afișa orice sursă de date pe viitor.

@export var pressure_system_path: NodePath
@export var needle_min_angle_deg: float = -120.0
@export var needle_max_angle_deg: float = 120.0
@export var blink_interval: float = 0.4

@onready var needle: Node3D = $Needle
@onready var warning_light: OmniLight3D = $WarningLight

var _pressure_system: Node = null
var _is_warning: bool = false
var _blink_timer: float = 0.0


func _ready() -> void:
	warning_light.visible = false

	if pressure_system_path == NodePath():
		return

	_pressure_system = get_node_or_null(pressure_system_path)
	if _pressure_system == null:
		return

	_pressure_system.pressure_changed.connect(_on_pressure_changed)
	_pressure_system.failure_started.connect(_on_failure_started)
	_pressure_system.failure_resolved.connect(_on_failure_resolved)
	_on_pressure_changed(_pressure_system.get_pressure_ratio())


func _process(delta: float) -> void:
	if not _is_warning:
		return

	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_timer = blink_interval
		warning_light.visible = not warning_light.visible


func _on_pressure_changed(ratio: float) -> void:
	var angle: float = lerp(needle_min_angle_deg, needle_max_angle_deg, clamp(ratio, 0.0, 1.0))
	needle.rotation_degrees.z = angle


func _on_failure_started(_time_remaining: float) -> void:
	_is_warning = true
	warning_light.visible = true


func _on_failure_resolved() -> void:
	_is_warning = false
	warning_light.visible = false
