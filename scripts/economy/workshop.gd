class_name Workshop
extends Area3D
## workshop.gd — Modulul de Economie: banc de lucru pentru reparații.
##
## Se atașează pe: rădăcina scenei "Workshop" (Area3D).
## Noduri copil necesare (vezi workshop.tscn):
##   CollisionShape3D — zona de proximitate (jucătorul intră cu mașina)
##
## Design: Workshop nu ascultă taste și nu desenează niciun meniu — expune
## doar semnale (vehicle_entered/exited, repair_completed/denied) și metode
## publice de reparație. Garage UI-ul (modul viitor) se abonează la semnale
## ca să arate/ascundă panoul, și apelează metodele când jucătorul dă click
## pe un buton. Ține logica de business separată de prezentare, ca oricare
## altă interfață (UI nouă, tastă rapidă, NPC mecanic) să o poată folosi.

signal vehicle_entered(vehicle: Node3D)
signal vehicle_exited(vehicle: Node3D)
signal repair_completed(vehicle: Node3D, part_name: String, cost: int)
signal repair_denied(part_name: String, cost: int)

@export_group("Prețuri (bani)")
@export var brake_repair_cost: int = 80
@export var clutch_repair_cost: int = 120
@export var oil_refill_cost: int = 30
@export var tire_inflate_cost: int = 15  ## per roată

var _vehicle_in_range: Node3D = null
var _damage_in_range: VehicleDamage = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func has_vehicle_in_range() -> bool:
	return _vehicle_in_range != null


## Folosit de UI ca să afișeze starea pieselor fără să-și dubleze propria
## logică de căutare a nodului VehicleDamage.
func get_vehicle_damage() -> VehicleDamage:
	return _damage_in_range


# ---------------------------------------------------------------------------
# REPARAȚII — fiecare verifică fonduri prin EconomyManager înainte de a aplica
# ---------------------------------------------------------------------------

func repair_brakes() -> bool:
	return _try_repair("brakes", brake_repair_cost, func() -> void: _damage_in_range.repair_brakes())


func repair_clutch() -> bool:
	return _try_repair("clutch", clutch_repair_cost, func() -> void: _damage_in_range.repair_clutch())


func refill_oil() -> bool:
	return _try_repair("oil", oil_refill_cost, func() -> void: _damage_in_range.refill_oil())


func inflate_tire(wheel_index: int) -> bool:
	return _try_repair(
		"tire_%d" % wheel_index, tire_inflate_cost, func() -> void: _damage_in_range.inflate_tire(wheel_index)
	)


## Repară tot dintr-o dată, la prețul cumulat al tuturor componentelor.
func repair_all() -> bool:
	if _damage_in_range == null:
		return false

	var total_cost: int = (
		brake_repair_cost
		+ clutch_repair_cost
		+ oil_refill_cost
		+ tire_inflate_cost * _damage_in_range.tire_count
	)

	return _try_repair("all", total_cost, func() -> void:
		_damage_in_range.repair_brakes()
		_damage_in_range.repair_clutch()
		_damage_in_range.refill_oil()
		for i in _damage_in_range.tire_count:
			_damage_in_range.inflate_tire(i)
	)


func _try_repair(part_name: String, cost: int, apply_repair: Callable) -> bool:
	if _damage_in_range == null:
		return false

	if not EconomyManager.spend(cost, "workshop_repair_%s" % part_name):
		repair_denied.emit(part_name, cost)
		return false

	apply_repair.call()
	repair_completed.emit(_vehicle_in_range, part_name, cost)
	return true


# ---------------------------------------------------------------------------
# DETECȚIA VEHICULULUI ÎN ZONĂ
# ---------------------------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player_vehicle"):
		return
	_vehicle_in_range = body
	_damage_in_range = _find_vehicle_damage(body)
	vehicle_entered.emit(body)


func _on_body_exited(body: Node3D) -> void:
	if body != _vehicle_in_range:
		return
	_vehicle_in_range = null
	_damage_in_range = null
	vehicle_exited.emit(body)


func _find_vehicle_damage(vehicle: Node3D) -> VehicleDamage:
	for child in vehicle.get_children():
		if child is VehicleDamage:
			return child
	return null
