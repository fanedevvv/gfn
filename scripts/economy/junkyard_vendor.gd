class_name JunkyardVendor
extends Area3D
## junkyard_vendor.gd — Modulul de Economie: cimitirul de mașini.
##
## Se atașează pe: rădăcina scenei "JunkyardVendor" (Area3D).
## Noduri copil necesare (vezi junkyard_vendor.tscn):
##   CollisionShape3D — zona de proximitate (opțională; catalogul poate fi
##                       răsfoit și de la distanță, de un UI de hartă)
##   SpawnPoint (Marker3D) — unde apar mașinile cumpărate
##
## Catalogul de epave e citit din fișiere JSON în `listings_folder`
## (implicit res://data/vehicles/). Fiecare fișier descrie o mașină de
## vânzare: preț, scenă și starea inițială de uzură — o epavă nu pornește
## "ca nouă" (vezi VehicleDamage.apply_condition()).
##
## Design: la fel ca Workshop, nu ascultă taste și nu desenează niciun
## meniu — expune catalogul (get_listings()) și purchase(listing_id).
## Garage UI-ul le folosește pentru panoul de cumpărare, arătat/ascuns pe
## baza vehicle_entered/vehicle_exited (simetric cu Workshop).

signal catalog_loaded(listings: Array[Dictionary])
signal vehicle_purchased(listing_id: String, vehicle: Node3D)
signal purchase_denied(listing_id: String, reason: String)
signal vehicle_entered(vehicle: Node3D)
signal vehicle_exited(vehicle: Node3D)

@export var listings_folder: String = "res://data/vehicles/"
@export_group("Spawn")
## Unde se adaugă mașinile cumpărate. Gol = scena curentă (get_tree().current_scene).
@export var vehicle_container_path: NodePath
@export var max_spawned_vehicles: int = 3  ## câte epave nevândute pot sta simultan lângă vânzător

@onready var spawn_point: Marker3D = $SpawnPoint

var _listings: Dictionary = {}          ## id (String) -> Dictionary (datele din JSON)
var _spawned_vehicles: Array[Node3D] = []


func _ready() -> void:
	_load_catalog()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func get_listings() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in _listings.values():
		result.append(value)
	return result


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player_vehicle"):
		vehicle_entered.emit(body)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player_vehicle"):
		vehicle_exited.emit(body)


func get_listing(listing_id: String) -> Dictionary:
	return _listings.get(listing_id, {})


## Cumpără mașina `listing_id`: verifică fonduri, o instanțiază, îi aplică
## starea de uzură din catalog. Returnează instanța, sau null dacă a eșuat
## (bani insuficienți / listing inexistent / scenă lipsă).
func purchase(listing_id: String) -> Node3D:
	if not _listings.has(listing_id):
		purchase_denied.emit(listing_id, "listing_not_found")
		return null

	var listing: Dictionary = _listings[listing_id]
	var price: int = int(listing.get("price", 0))

	if not EconomyManager.spend(price, "junkyard_purchase_%s" % listing_id):
		purchase_denied.emit(listing_id, "insufficient_funds")
		return null

	var vehicle: Node3D = _spawn_vehicle(listing)
	if vehicle == null:
		# Nu lăsăm jucătorul plătit fără să primească nimic — banii se întorc.
		EconomyManager.add_funds(price)
		purchase_denied.emit(listing_id, "spawn_failed")
		return null

	vehicle_purchased.emit(listing_id, vehicle)
	return vehicle


# ---------------------------------------------------------------------------
# CATALOG — încărcat din JSON la pornire
# ---------------------------------------------------------------------------

func _load_catalog() -> void:
	_listings.clear()

	var dir: DirAccess = DirAccess.open(listings_folder)
	if dir == null:
		push_warning("JunkyardVendor: nu pot deschide %s" % listings_folder)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			_load_listing_file(listings_folder.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()

	catalog_loaded.emit(get_listings())


func _load_listing_file(path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("JunkyardVendor: nu pot citi %s" % path)
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("id"):
		push_warning("JunkyardVendor: JSON invalid în %s (lipsește 'id')" % path)
		return

	_listings[parsed["id"]] = parsed


# ---------------------------------------------------------------------------
# SPAWN
# ---------------------------------------------------------------------------

func _spawn_vehicle(listing: Dictionary) -> Node3D:
	var scene_path: String = listing.get("scene_path", "")
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		push_warning("JunkyardVendor: scene_path invalid pentru '%s'" % listing.get("id", "?"))
		return null

	var packed_scene: PackedScene = load(scene_path)
	var vehicle: Node3D = packed_scene.instantiate()
	vehicle.position = _next_spawn_position()
	_get_vehicle_container().add_child(vehicle)

	_apply_condition(vehicle, listing.get("condition", {}))

	_spawned_vehicles.append(vehicle)
	if _spawned_vehicles.size() > max_spawned_vehicles:
		var oldest: Node3D = _spawned_vehicles.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

	return vehicle


func _apply_condition(vehicle: Node3D, condition: Dictionary) -> void:
	if condition.is_empty():
		return
	for child in vehicle.get_children():
		if child is VehicleDamage:
			child.apply_condition(condition)
			return


func _next_spawn_position() -> Vector3:
	var offset: Vector3 = Vector3(_spawned_vehicles.size() * 4.0, 0.0, 0.0)
	return spawn_point.global_position + offset


func _get_vehicle_container() -> Node:
	if vehicle_container_path != NodePath():
		var container: Node = get_node_or_null(vehicle_container_path)
		if container:
			return container
	return get_tree().current_scene
