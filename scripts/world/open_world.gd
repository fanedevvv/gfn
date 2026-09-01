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
## repară tot cât timp mașina stă pe platforma galbenă. Wiring de test
## pentru JunkyardVendor: tasta debug_buy_project_car cumpără epava cea
## mai ieftină din catalog. Ambele sunt doar pentru verificare rapidă —
## dispar când vine Garage UI-ul real, care va apela aceleași metode
## publice din Workshop/JunkyardVendor la click pe buton.
##
## Traseu de test pentru Trafic AI: construit direct din cod (Path3D +
## Curve3D), un patrulater simplu de 80x80m în jurul originii, populat
## automat cu TrafficSpawner. Într-un nivel real, drumurile se desenează
## manual în editor cu unealta Path3D — asta e doar pentru verificare
## rapidă, fără să depindem de o hartă reală care încă nu există.

const CAR_SCENE: PackedScene = preload("res://scenes/vehicles/base/car_base.tscn")

@onready var chunk_container: Node3D = $ChunkContainer
@onready var spawn_point: Marker3D = $SpawnPoint
@onready var workshop: Workshop = $Workshop
@onready var junkyard: JunkyardVendor = $JunkyardVendor


func _ready() -> void:
	var car: VehicleBody3D = CAR_SCENE.instantiate()
	car.position = spawn_point.position
	add_child(car)
	WorldStreamer.start(car, chunk_container)

	workshop.vehicle_entered.connect(func(_v: Node3D) -> void: print("[Workshop] mașină în zonă — fonduri: %d" % EconomyManager.funds))
	workshop.vehicle_exited.connect(func(_v: Node3D) -> void: print("[Workshop] mașină ieșită din zonă"))
	workshop.repair_completed.connect(func(_v: Node3D, part: String, cost: int) -> void: print("[Workshop] reparat '%s' pentru %d — fonduri rămase: %d" % [part, cost, EconomyManager.funds]))
	workshop.repair_denied.connect(func(part: String, cost: int) -> void: print("[Workshop] fonduri insuficiente pentru '%s' (cost %d, ai %d)" % [part, cost, EconomyManager.funds]))

	junkyard.catalog_loaded.connect(func(listings: Array[Dictionary]) -> void: print("[Junkyard] catalog încărcat: %d epave" % listings.size()))
	junkyard.vehicle_purchased.connect(func(listing_id: String, _v: Node3D) -> void: print("[Junkyard] cumpărat '%s' — fonduri rămase: %d" % [listing_id, EconomyManager.funds]))
	junkyard.purchase_denied.connect(func(listing_id: String, reason: String) -> void: print("[Junkyard] cumpărare eșuată pentru '%s': %s" % [listing_id, reason]))

	TimeOfDay.period_changed.connect(func(period: TimeOfDay.DayPeriod) -> void: print("[TimeOfDay] ora %.1f — perioadă nouă: %s" % [TimeOfDay.current_hour, TimeOfDay.DayPeriod.keys()[period]]))

	_create_test_traffic_route()


func _create_test_traffic_route() -> void:
	var route: Path3D = Path3D.new()
	route.name = "TestTrafficRoute"

	var curve: Curve3D = Curve3D.new()
	curve.add_point(Vector3(40, 0.5, 40))
	curve.add_point(Vector3(40, 0.5, -40))
	curve.add_point(Vector3(-40, 0.5, -40))
	curve.add_point(Vector3(-40, 0.5, 40))
	curve.add_point(Vector3(40, 0.5, 40))  # închide bucla, revenind la primul punct
	route.curve = curve

	add_child(route)

	var spawner: TrafficSpawner = TrafficSpawner.new()
	spawner.name = "TrafficSpawner"
	spawner.vehicle_count = 4
	spawner.route_loops = true
	route.add_child(spawner)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_repair_all") and workshop.has_vehicle_in_range():
		workshop.repair_all()

	if Input.is_action_just_pressed("debug_buy_project_car"):
		junkyard.purchase("project_car")
