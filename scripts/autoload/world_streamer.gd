extends Node
## world_streamer.gd — Autoload: streaming de lume pe bucăți (Chunk/World
## Streaming), necesar pentru o hartă mare (zonă industrială, oraș, drumuri
## naționale, serpentine montane) fără să încărcăm totul dintr-o dată.
##
## Harta e împărțită într-un grid de pătrate cu latura `chunk_size`, fiecare
## salvat ca scenă separată: res://scenes/world/chunks/chunk_X_Y.tscn (X, Y
## = coordonate de grid, pot fi negative). Coordonata (0,0) e centrată la
## originea lumii — vezi _world_to_chunk_coord().
##
## Pornire: apelează WorldStreamer.start(player, chunk_container) o singură
## dată, din scena lumii (vezi scenes/world/open_world.tscn), când
## playerul/mașina există deja în scenă. Oprește cu WorldStreamer.stop()
## la revenirea în meniu.
##
## Înregistrare: Project Settings -> Autoload -> acest script ca
## "WorldStreamer" (deja configurat în project.godot).

signal chunk_loaded(chunk_coord: Vector2i)
signal chunk_unloaded(chunk_coord: Vector2i)

const CHUNK_PATH_FORMAT: String = "res://scenes/world/chunks/chunk_%d_%d.tscn"

@export var chunk_size: float = 200.0
@export var load_radius_chunks: int = 2         ## raza (în chunk-uri) ținută încărcată
@export var unload_margin_chunks: int = 1        ## histerezis: se descarcă abia dincolo de load_radius + margin
@export var update_interval_sec: float = 0.5     ## cât de des recalculăm chunk-urile necesare
@export var max_concurrent_loads: int = 2        ## câte cereri de încărcare rulează simultan

var _player: Node3D = null
var _chunk_container: Node3D = null

var _loaded_chunks: Dictionary = {}   ## Vector2i -> Node3D (instanța chunk-ului)
var _pending_loads: Dictionary = {}   ## Vector2i -> String (calea resursei în curs de încărcare)
var _load_queue: Array[Vector2i] = [] ## chunk-uri care așteaptă să înceapă încărcarea

var _update_timer: float = 0.0
var _current_center_chunk: Vector2i = Vector2i.ZERO


func start(player: Node3D, chunk_container: Node3D) -> void:
	_player = player
	_chunk_container = chunk_container
	_update_timer = 0.0
	_refresh_required_chunks()


func stop() -> void:
	for coord in _loaded_chunks.keys():
		var chunk_instance: Node3D = _loaded_chunks[coord]
		chunk_instance.queue_free()
	_loaded_chunks.clear()
	_pending_loads.clear()
	_load_queue.clear()
	_player = null
	_chunk_container = null


func get_current_chunk_coord() -> Vector2i:
	return _current_center_chunk


func is_chunk_loaded(coord: Vector2i) -> bool:
	return _loaded_chunks.has(coord)


func _process(delta: float) -> void:
	if _player == null:
		return

	_poll_pending_loads()

	_update_timer -= delta
	if _update_timer <= 0.0:
		_update_timer = update_interval_sec
		_refresh_required_chunks()

	_start_queued_loads()


# ---------------------------------------------------------------------------
# GRID <-> LUME
# ---------------------------------------------------------------------------

func _world_to_chunk_coord(world_position: Vector3) -> Vector2i:
	return Vector2i(roundi(world_position.x / chunk_size), roundi(world_position.z / chunk_size))


func _chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return max(absi(a.x - b.x), absi(a.y - b.y))


# ---------------------------------------------------------------------------
# DECIDE CE SE ÎNCARCĂ / DESCARCĂ
# ---------------------------------------------------------------------------

func _refresh_required_chunks() -> void:
	var center: Vector2i = _world_to_chunk_coord(_player.global_position)
	_current_center_chunk = center

	for dx in range(-load_radius_chunks, load_radius_chunks + 1):
		for dy in range(-load_radius_chunks, load_radius_chunks + 1):
			var coord: Vector2i = center + Vector2i(dx, dy)
			if not _loaded_chunks.has(coord) and not _pending_loads.has(coord) and not _load_queue.has(coord):
				_load_queue.append(coord)

	var unload_radius: int = load_radius_chunks + unload_margin_chunks
	for coord in _loaded_chunks.keys().duplicate():
		if _chebyshev_distance(coord, center) > unload_radius:
			_unload_chunk(coord)


func _unload_chunk(coord: Vector2i) -> void:
	if _loaded_chunks.has(coord):
		var chunk_instance: Node3D = _loaded_chunks[coord]
		chunk_instance.queue_free()
		_loaded_chunks.erase(coord)
		chunk_unloaded.emit(coord)

	_load_queue.erase(coord)
	# Notă: NU ștergem din _pending_loads aici — ResourceLoader nu suportă
	# anularea unei cereri threaded pornite. O lăsăm să se termine în
	# _poll_pending_loads(); _instantiate_chunk() verifică din nou distanța
	# și o aruncă dacă playerul s-a îndepărtat între timp.


# ---------------------------------------------------------------------------
# ÎNCĂRCARE ASINCRONĂ — esențial pentru 60+ FPS pe o hartă întinsă
# ---------------------------------------------------------------------------

func _start_queued_loads() -> void:
	while not _load_queue.is_empty() and _pending_loads.size() < max_concurrent_loads:
		var coord: Vector2i = _load_queue.pop_front()
		if _loaded_chunks.has(coord) or _pending_loads.has(coord):
			continue
		_request_chunk_load(coord)


func _request_chunk_load(coord: Vector2i) -> void:
	var path: String = CHUNK_PATH_FORMAT % [coord.x, coord.y]
	if not ResourceLoader.exists(path):
		return  # nicio scenă definită la această coordonată (ex: marginea hărții) — normal

	var error: Error = ResourceLoader.load_threaded_request(path)
	if error != OK:
		push_warning("WorldStreamer: nu pot porni încărcarea pentru %s (eroare %d)" % [path, error])
		return

	_pending_loads[coord] = path


func _poll_pending_loads() -> void:
	for coord in _pending_loads.keys().duplicate():
		var path: String = _pending_loads[coord]
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)

		match status:
			ResourceLoader.THREAD_LOAD_LOADED:
				var packed_scene: PackedScene = ResourceLoader.load_threaded_get(path)
				_pending_loads.erase(coord)
				_instantiate_chunk(coord, packed_scene)
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_warning("WorldStreamer: încărcare eșuată pentru %s" % path)
				_pending_loads.erase(coord)
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				pass  # continuă să aștepte, verificăm din nou la următorul poll


func _instantiate_chunk(coord: Vector2i, packed_scene: PackedScene) -> void:
	# Playerul s-ar putea fi îndepărtat suficient cât chunk-ul să nu mai fie
	# necesar până s-a terminat încărcarea — nu-l adăugăm degeaba în scenă.
	var unload_radius: int = load_radius_chunks + unload_margin_chunks
	if _chebyshev_distance(coord, _current_center_chunk) > unload_radius:
		return

	var chunk_instance: Node3D = packed_scene.instantiate()
	chunk_instance.position = Vector3(coord.x * chunk_size, 0.0, coord.y * chunk_size)
	_chunk_container.add_child(chunk_instance)
	_loaded_chunks[coord] = chunk_instance
	chunk_loaded.emit(coord)
