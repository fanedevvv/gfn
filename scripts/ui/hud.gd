extends CanvasLayer
## hud.gd — HUD-ul de bord: viteză, RPM, treaptă curentă.
##
## Se atașează pe: rădăcina scenei "HUD" (CanvasLayer).
## Noduri copil necesare (vezi hud.tscn):
##   DashboardPanel/GearLabel     (Label)
##   DashboardPanel/SpeedLabel    (Label)
##   DashboardPanel/TachometerBar (ProgressBar)
##
## Nu se leagă automat de un vehicul la _ready() — sistemul de intrare/
## ieșire din mașină (modul viitor) apelează bind_vehicle(car) când
## jucătorul urcă la volan și unbind_vehicle() când coboară. Așa se
## refolosește același HUD pentru orice vehicul din joc, fără cablaj fix.

const REDLINE_RATIO: float = 0.9  ## % din RPM maxim de la care bara devine roșie

@onready var speed_label: Label = $DashboardPanel/SpeedLabel
@onready var gear_label: Label = $DashboardPanel/GearLabel
@onready var tachometer_bar: ProgressBar = $DashboardPanel/TachometerBar

var _bound_vehicle: Node = null


func _ready() -> void:
	visible = false


## Conectează HUD-ul la semnalele de telemetrie ale unui vehicul
## (car_controller.gd: speed_changed, rpm_changed, gear_changed).
func bind_vehicle(vehicle: Node) -> void:
	unbind_vehicle()

	if vehicle == null:
		return

	_bound_vehicle = vehicle
	_bound_vehicle.speed_changed.connect(_on_speed_changed)
	_bound_vehicle.rpm_changed.connect(_on_rpm_changed)
	_bound_vehicle.gear_changed.connect(_on_gear_changed)

	# Fiecare vehicul își poate avea propriul RPM maxim (SUV vs. sport) —
	# citim direct din instanță, nu presupunem o valoare fixă în HUD.
	if "max_rpm" in _bound_vehicle:
		tachometer_bar.max_value = _bound_vehicle.max_rpm

	visible = true


## Deconectează HUD-ul de vehiculul curent (ex: jucătorul coboară din mașină).
func unbind_vehicle() -> void:
	if _bound_vehicle == null:
		return

	if _bound_vehicle.speed_changed.is_connected(_on_speed_changed):
		_bound_vehicle.speed_changed.disconnect(_on_speed_changed)
	if _bound_vehicle.rpm_changed.is_connected(_on_rpm_changed):
		_bound_vehicle.rpm_changed.disconnect(_on_rpm_changed)
	if _bound_vehicle.gear_changed.is_connected(_on_gear_changed):
		_bound_vehicle.gear_changed.disconnect(_on_gear_changed)

	_bound_vehicle = null
	visible = false


func _on_speed_changed(speed_kmh: float) -> void:
	speed_label.text = "%d km/h" % roundi(speed_kmh)


func _on_rpm_changed(rpm: float) -> void:
	tachometer_bar.value = rpm

	var is_redline: bool = rpm >= tachometer_bar.max_value * REDLINE_RATIO
	tachometer_bar.modulate = Color(1.0, 0.25, 0.2) if is_redline else Color(1.0, 1.0, 1.0)


func _on_gear_changed(gear_label_text: String) -> void:
	gear_label.text = gear_label_text
