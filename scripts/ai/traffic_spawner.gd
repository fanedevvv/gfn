class_name TrafficSpawner
extends Node
## traffic_spawner.gd — Modulul Lume Activă: trafic AI de bază.
##
## Se atașează pe: un Node simplu, COPIL DIRECT al unui Path3D care descrie
## ruta (drumul) — vezi _route de mai jos, rezolvat automat din get_parent().
##
## Populează ruta cu `vehicle_count` mașini la pornire, distribuite uniform
## pe lungimea curbei, fiecare "urmărind" mașina spawnată înaintea ei
## (vehicle_ahead) — un lanț simplu, suficient pentru trafic de fundal.
## Pentru rute în buclă, ultima mașină e legată înapoi de prima, ca lanțul
## să se închidă corect.
##
## Autor drumul cu unealta de desenare Path3D din editor (selectezi nodul
## Path3D, click pe creion în viewport, adaugi puncte) — TrafficSpawner nu
## are nevoie de nimic altceva ca să populeze orice rută desenezi.

const TRAFFIC_CAR_SCENE: PackedScene = preload("res://scenes/ai/traffic_car.tscn")

@export var vehicle_count: int = 4
@export var route_loops: bool = true

@export_group("Viteză")
@export var min_cruise_speed_kmh: float = 35.0
@export var max_cruise_speed_kmh: float = 55.0

@onready var _route: Path3D = get_parent() as Path3D

var _spawned_cars: Array[TrafficCar] = []


func _ready() -> void:
	if _route == null:
		push_warning("TrafficSpawner: trebuie să fie copil direct al unui Path3D.")
		return

	for i in vehicle_count:
		_spawn_car(float(i) / vehicle_count)

	if route_loops and _spawned_cars.size() > 1:
		_spawned_cars[0].vehicle_ahead = _spawned_cars.back()


func _spawn_car(initial_progress_ratio: float) -> void:
	var car: TrafficCar = TRAFFIC_CAR_SCENE.instantiate()
	_route.add_child(car)

	car.loop = route_loops
	car.progress_ratio = initial_progress_ratio
	car.cruise_speed_kmh = randf_range(min_cruise_speed_kmh, max_cruise_speed_kmh)
	car.vehicle_ahead = _spawned_cars.back() if not _spawned_cars.is_empty() else null

	_spawned_cars.append(car)
