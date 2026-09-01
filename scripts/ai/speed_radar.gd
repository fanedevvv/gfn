class_name SpeedRadar
extends Area3D
## speed_radar.gd — Modulul Lume Activă: radar de viteză.
##
## Se atașează pe: rădăcina scenei "SpeedRadar" (Area3D), plasat perpendicular
## pe direcția drumului — zona de detecție trebuie TRAVERSATĂ, nu ocolită
## (o cutie subțire de-a latul drumului, ca o linie de radar reală).
## Noduri copil necesare (vezi speed_radar.tscn): CollisionShape3D
##
## Măsoară viteza reală (linear_velocity) a jucătorului la trecerea prin
## zonă. Peste limită, raportează încălcarea la WantedSystem — radarul nu
## știe nimic despre amenzi/poliție, doar constată și raportează.

signal vehicle_measured(vehicle: Node3D, speed_kmh: float)
signal speed_violation(vehicle: Node3D, speed_kmh: float, over_limit_kmh: float)

@export var speed_limit_kmh: float = 50.0
@export var fine_per_kmh_over: int = 5
@export var min_fine: int = 50

var _measured_this_pass: Dictionary = {}  ## vehicle -> true, evită măsurare dublă în același overlap


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player_vehicle") or _measured_this_pass.has(body):
		return
	_measured_this_pass[body] = true

	var speed_kmh: float = body.linear_velocity.length() * 3.6 if body is VehicleBody3D else 0.0
	vehicle_measured.emit(body, speed_kmh)

	if speed_kmh <= speed_limit_kmh:
		return

	var over: float = speed_kmh - speed_limit_kmh
	var fine: int = max(min_fine, int(over * fine_per_kmh_over))
	speed_violation.emit(body, speed_kmh, over)
	WantedSystem.report_violation(body, fine, "speed_%d" % int(speed_kmh))


func _on_body_exited(body: Node3D) -> void:
	_measured_this_pass.erase(body)
