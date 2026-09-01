extends Node3D
## open_world.gd — scenă rădăcină de test pentru World Streaming + Atelier.
##
## Se atașează pe: rădăcina scenei "OpenWorld" (Node3D) — vezi open_world.tscn.
## Noduri copil necesare:
##   ChunkContainer (Node3D) — WorldStreamer adaugă instanțele de chunk aici
##   SpawnPoint (Marker3D)   — poziția inițială a mașinii de test
##
## Instanțiază temporar o mașină din car_base.tscn ca să existe un "player"
## de urmărit pentru WorldStreamer — sistemul complet de spawn/intrare-în-
## vehicul vine într-un modul viitor (economie/garaj).
##
## Wiring de test pentru Workshop: tasta debug_repair_all (vezi Input Map)
## repară tot cât timp mașina stă pe platforma galbenă. E doar pentru
## verificare rapidă — dispare când vine Garage UI-ul real, care va apela
## aceleași metode publice din Workshop la click pe buton.

const CAR_SCENE: PackedScene = preload("res://scenes/vehicles/base/car_base.tscn")

@onready var chunk_container: Node3D = $ChunkContainer
@onready var spawn_point: Marker3D = $SpawnPoint
@onready var workshop: Workshop = $Workshop


func _ready() -> void:
	var car: VehicleBody3D = CAR_SCENE.instantiate()
	car.position = spawn_point.position
	add_child(car)
	WorldStreamer.start(car, chunk_container)

	workshop.vehicle_entered.connect(func(_v: Node3D) -> void: print("[Workshop] mașină în zonă — fonduri: %d" % EconomyManager.funds))
	workshop.vehicle_exited.connect(func(_v: Node3D) -> void: print("[Workshop] mașină ieșită din zonă"))
	workshop.repair_completed.connect(func(_v: Node3D, part: String, cost: int) -> void: print("[Workshop] reparat '%s' pentru %d — fonduri rămase: %d" % [part, cost, EconomyManager.funds]))
	workshop.repair_denied.connect(func(part: String, cost: int) -> void: print("[Workshop] fonduri insuficiente pentru '%s' (cost %d, ai %d)" % [part, cost, EconomyManager.funds]))


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_repair_all") and workshop.has_vehicle_in_range():
		workshop.repair_all()
