class_name TrafficCar
extends PathFollow3D
## traffic_car.gd — Modulul Lume Activă: trafic AI de bază.
##
## Se atașează pe: rădăcina scenei "TrafficCar" (PathFollow3D) — se
## instanțiază ca și copil al unui Path3D care descrie ruta (drumul).
## Nu e simulată prin fizică (VehicleBody3D) — se mișcă direct prin
## `progress` de-a lungul curbei, mult mai ieftin pentru trafic de fundal
## pe o hartă mare (esențial pentru cele 60+ FPS cerute).
##
## Coliziunea reală cu jucătorul vine din AnimatableBody3D copil — nodul
## Godot dedicat exact corpurilor mișcate cinematic (nu prin forțe), care
## totuși împing/opresc corect alte corpuri fizice (VehicleBody3D inclusiv).
##
## Noduri copil necesare (vezi traffic_car.tscn):
##   AnimatableBody3D (sync_to_physics = true)
##     ├── CollisionShape3D
##     └── BodyMesh (MeshInstance3D, placeholder)

@export var cruise_speed_kmh: float = 45.0
@export var acceleration: float = 3.0            ## m/s²
@export var braking_deceleration: float = 6.0     ## m/s²
@export var following_distance_m: float = 8.0     ## distanța minimă față de mașina din față

var current_speed_mps: float = 0.0

## Setat de TrafficSpawner la instanțiere — mașina "din față" pe aceeași
## rută, folosită doar ca să decidem dacă frânăm. Poate rămâne null (prima
## mașină de pe rută dacă ruta nu e buclă, sau dacă a fost eliberată între timp).
var vehicle_ahead: TrafficCar = null


func _physics_process(delta: float) -> void:
	var target_speed_mps: float = cruise_speed_kmh / 3.6

	if vehicle_ahead != null and is_instance_valid(vehicle_ahead):
		var gap: float = vehicle_ahead.progress - progress
		if gap < 0.0 and loop:
			gap += get_parent().curve.get_baked_length()  # ruta e o buclă, distanța "înfășoară"
		if gap < following_distance_m:
			target_speed_mps = min(target_speed_mps, vehicle_ahead.current_speed_mps * 0.9)

	var rate: float = acceleration if current_speed_mps < target_speed_mps else braking_deceleration
	current_speed_mps = move_toward(current_speed_mps, target_speed_mps, rate * delta)

	progress += current_speed_mps * delta

	if not loop and progress_ratio >= 1.0:
		queue_free()  # a ajuns la capătul unei rute care nu e buclă
