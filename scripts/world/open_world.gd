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
## GarageUI (panourile de Atelier/Junkyard) e legat de Workshop și
## JunkyardVendor la _ready() — apare/dispare automat pe baza proximității,
## fără nicio tastă de debug.
##
## Traseu de test pentru Trafic AI + Poliție: construit direct din cod
## (Path3D + Curve3D), un patrulater simplu de 80x80m în jurul originii,
## populat automat cu TrafficSpawner și o patrulă de poliție. Într-un nivel
## real, drumurile se desenează manual în editor cu unealta Path3D — asta
## e doar pentru verificare rapidă, fără să depindem de o hartă reală care
## încă nu există.
##
## Wiring de test pentru radar/poliție: SpeedRadar e plasat pe latura de
## sus a patrulaterului (40 km/h limită) — depășește-o cu mașina și
## patrula (dacă e în raza de detecție) intră în urmărire. Tasta
## debug_trigger_wanted forțează un nivel de căutare, ca test rapid fără
## să conduci până la radar.

const CAR_SCENE: PackedScene = preload("res://scenes/vehicles/base/car_base.tscn")
const POLICE_SCENE: PackedScene = preload("res://scenes/ai/police_patrol.tscn")

@onready var chunk_container: Node3D = $ChunkContainer
@onready var spawn_point: Marker3D = $SpawnPoint
@onready var workshop: Workshop = $Workshop
@onready var junkyard: JunkyardVendor = $JunkyardVendor
@onready var speed_radar: SpeedRadar = $SpeedRadar
@onready var garage_ui: GarageUI = $GarageUI


func _ready() -> void:
	var car: VehicleBody3D = CAR_SCENE.instantiate()
	car.position = spawn_point.position
	add_child(car)
	WorldStreamer.start(car, chunk_container)

	garage_ui.bind_workshop(workshop)
	garage_ui.bind_junkyard(junkyard)

	TimeOfDay.period_changed.connect(func(period: TimeOfDay.DayPeriod) -> void: print("[TimeOfDay] ora %.1f — perioadă nouă: %s" % [TimeOfDay.current_hour, TimeOfDay.DayPeriod.keys()[period]]))

	speed_radar.speed_violation.connect(func(_v: Node3D, speed_kmh: float, over: float) -> void: print("[Radar] depășire: %.0f km/h (+%.0f peste limită)" % [speed_kmh, over]))
	WantedSystem.wanted_level_changed.connect(func(level: int) -> void: print("[WantedSystem] nivel de căutare: %d" % level))
	WantedSystem.fine_issued.connect(func(amount: int, reason: String) -> void: print("[WantedSystem] amendă %d (%s) — fonduri rămase: %d" % [amount, reason, EconomyManager.funds]))

	var route: Path3D = _create_test_traffic_route()
	_spawn_test_police(route)


func _create_test_traffic_route() -> Path3D:
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

	return route


func _spawn_test_police(route: Path3D) -> void:
	var police: PolicePatrol = POLICE_SCENE.instantiate()
	add_child(police)
	police.global_position = Vector3(40, 1, -20)
	police.set_patrol_route(route)


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_trigger_wanted"):
		WantedSystem.report_violation(null, 0, "debug")
