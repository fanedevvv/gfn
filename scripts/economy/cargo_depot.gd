class_name CargoDepot
extends Area3D
## cargo_depot.gd — Modulul de Economie: punct de ridicare marfă.
##
## Se atașează pe: rădăcina scenei "CargoDepot" (Area3D).
## Noduri copil necesare (vezi cargo_depot.tscn): CollisionShape3D
##
## Catalogul de contracte e citit din JSON în `contracts_folder` (implicit
## res://data/economy/) — același tipar ca JunkyardVendor. Fiecare contract
## acceptat dispare din catalog (marfa a fost ridicată), rămâne indisponibil
## până la un restock viitor (nu implementat aici — modul separat, dacă e nevoie).
##
## Design: la fel ca Workshop/JunkyardVendor, nu ascultă taste și nu
## desenează niciun meniu — expune get_available_contracts() și
## accept_contract(id). Garage UI-ul (viitor) le folosește pentru panou.

signal vehicle_entered(vehicle: Node3D)
signal vehicle_exited(vehicle: Node3D)
signal contract_offer_accepted(contract_id: String, vehicle: Node3D)
signal contract_offer_denied(contract_id: String, reason: String)

@export var contracts_folder: String = "res://data/economy/"

var _contracts: Dictionary = {}  ## id (String) -> Dictionary (datele din JSON)
var _vehicle_in_range: Node3D = null
var _cargo_hold_in_range: CargoHold = null


func _ready() -> void:
	_load_contracts()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func has_vehicle_in_range() -> bool:
	return _vehicle_in_range != null


func get_available_contracts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in _contracts.values():
		result.append(value)
	return result


## Atribuie contractul `contract_id` vehiculului aflat în zonă. Returnează
## false dacă nu e niciun vehicul, contractul nu există, sau vehiculul cară
## deja altceva.
func accept_contract(contract_id: String) -> bool:
	if _cargo_hold_in_range == null:
		contract_offer_denied.emit(contract_id, "no_vehicle_in_range")
		return false
	if not _contracts.has(contract_id):
		contract_offer_denied.emit(contract_id, "contract_not_found")
		return false
	if _cargo_hold_in_range.has_active_contract():
		contract_offer_denied.emit(contract_id, "already_carrying_cargo")
		return false

	var contract: Dictionary = _contracts[contract_id]
	if not _cargo_hold_in_range.accept_contract(contract):
		contract_offer_denied.emit(contract_id, "accept_failed")
		return false

	_contracts.erase(contract_id)  # ridicat -- dispare din catalog
	contract_offer_accepted.emit(contract_id, _vehicle_in_range)
	return true


# ---------------------------------------------------------------------------
# CATALOG — încărcat din JSON la pornire
# ---------------------------------------------------------------------------

func _load_contracts() -> void:
	_contracts.clear()

	var dir: DirAccess = DirAccess.open(contracts_folder)
	if dir == null:
		push_warning("CargoDepot: nu pot deschide %s" % contracts_folder)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.begins_with("contract_") and file_name.ends_with(".json"):
			_load_contract_file(contracts_folder.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()


func _load_contract_file(path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("CargoDepot: nu pot citi %s" % path)
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("id"):
		push_warning("CargoDepot: JSON invalid în %s (lipsește 'id')" % path)
		return

	_contracts[parsed["id"]] = parsed


# ---------------------------------------------------------------------------
# DETECȚIA VEHICULULUI ÎN ZONĂ
# ---------------------------------------------------------------------------

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player_vehicle"):
		return
	_vehicle_in_range = body
	_cargo_hold_in_range = _find_cargo_hold(body)
	vehicle_entered.emit(body)


func _on_body_exited(body: Node3D) -> void:
	if body != _vehicle_in_range:
		return
	_vehicle_in_range = null
	_cargo_hold_in_range = null
	vehicle_exited.emit(body)


func _find_cargo_hold(vehicle: Node3D) -> CargoHold:
	for child in vehicle.get_children():
		if child is CargoHold:
			return child
	return null
