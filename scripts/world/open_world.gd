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
##
## Wiring de test pentru contracte de marfă: CargoDepot lângă punctul de
## spawn, două CargoDropoff pe traseul de test (depot_north, market_central).
## Tasta debug_accept_contract preia primul contract disponibil din
## catalog — livrarea se întâmplă singură când ajungi la dropoff-ul corect.
##
## Wiring de test pentru tractare: jucătorul conduce acum tow_truck.tscn
## (moștenește car_base.tscn, doar cu TowHitch adăugat) — o mașină
## "rablagită" (is_player_controlled=false, altfel ar răspunde și ea la
## taste) apare imediat în spatele lui. Tasta debug_toggle_tow prinde/
## eliberează manual, ca test rapid fără să dai cu spatele exact la ea.
## TowDropoff plătește automat la sosire, ca și CargoDropoff.

const TOW_TRUCK_SCENE: PackedScene = preload("res://scenes/vehicles/tow_truck.tscn")
const CAR_SCENE: PackedScene = preload("res://scenes/vehicles/base/car_base.tscn")
const POLICE_SCENE: PackedScene = preload("res://scenes/ai/police_patrol.tscn")

@onready var chunk_container: Node3D = $ChunkContainer
@onready var spawn_point: Marker3D = $SpawnPoint
@onready var workshop: Workshop = $Workshop
@onready var junkyard: JunkyardVendor = $JunkyardVendor
@onready var speed_radar: SpeedRadar = $SpeedRadar
@onready var garage_ui: GarageUI = $GarageUI
@onready var chase_camera: ChaseCamera = $ChaseCamera
@onready var cargo_depot: CargoDepot = $CargoDepot

var _tow_hitch: TowHitch = null


func _ready() -> void:
	var car: VehicleBody3D = TOW_TRUCK_SCENE.instantiate()
	car.position = spawn_point.position
	add_child(car)
	WorldStreamer.start(car, chunk_container)
	chase_camera.set_target(car)

	_tow_hitch = car.get_node("TowHitch")
	_tow_hitch.vehicle_hitched.connect(func(v: Node3D) -> void: print("[TowHitch] prins: %s" % v.name))
	_tow_hitch.vehicle_unhitched.connect(func(v: Node3D) -> void: print("[TowHitch] eliberat: %s" % v.name))
	_tow_hitch.hitch_denied.connect(func(reason: String) -> void: print("[TowHitch] refuzat: %s" % reason))
	_spawn_stranded_vehicle(car)

	garage_ui.bind_workshop(workshop)
	garage_ui.bind_junkyard(junkyard)

	TimeOfDay.period_changed.connect(func(period: TimeOfDay.DayPeriod) -> void: print("[TimeOfDay] ora %.1f — perioadă nouă: %s" % [TimeOfDay.current_hour, TimeOfDay.DayPeriod.keys()[period]]))

	speed_radar.speed_violation.connect(func(_v: Node3D, speed_kmh: float, over: float) -> void: print("[Radar] depășire: %.0f km/h (+%.0f peste limită)" % [speed_kmh, over]))
	WantedSystem.wanted_level_changed.connect(func(level: int) -> void: print("[WantedSystem] nivel de căutare: %d" % level))
	WantedSystem.fine_issued.connect(func(amount: int, reason: String) -> void: print("[WantedSystem] amendă %d (%s) — fonduri rămase: %d" % [amount, reason, EconomyManager.funds]))

	cargo_depot.contract_offer_accepted.connect(func(contract_id: String, _v: Node3D) -> void: print("[Cargo] contract preluat: %s" % contract_id))
	cargo_depot.contract_offer_denied.connect(func(contract_id: String, reason: String) -> void: print("[Cargo] preluare eșuată '%s': %s" % [contract_id, reason]))

	var tow_dropoff: TowDropoff = $TowDropoff
	tow_dropoff.tow_delivered.connect(func(v: Node3D, payout: int) -> void: print("[TowDropoff] livrat %s — +%d$, fonduri: %d$" % [v.name, payout, EconomyManager.funds]))

	var route: Path3D = _create_test_traffic_route()
	_spawn_test_police(route)
	_connect_cargo_signals(car)


func _connect_cargo_signals(car: VehicleBody3D) -> void:
	var cargo_hold: CargoHold = car.get_node("CargoHold")
	cargo_hold.contract_accepted.connect(func(contract: Dictionary) -> void: print("[Cargo] transporți: %s (plată %d$)" % [contract.get("description"), contract.get("payout")]))
	cargo_hold.contract_completed.connect(func(contract: Dictionary, payout: int) -> void: print("[Cargo] livrat: %s — +%d$, fonduri: %d$" % [contract.get("description"), payout, EconomyManager.funds]))
	cargo_hold.contract_failed.connect(func(contract: Dictionary, reason: String) -> void: print("[Cargo] eșuat: %s (%s)" % [contract.get("description"), reason]))


func _spawn_stranded_vehicle(truck: VehicleBody3D) -> void:
	var stranded: VehicleBody3D = CAR_SCENE.instantiate()
	# nu trebuie să răspundă la taste — vezi is_player_controlled în car_controller.gd
	stranded.is_player_controlled = false
	add_child(stranded)
	# camionul are hitch-ul la z=-2.8 față de el (capătul care rămâne în urmă
	# la mers pe +Z) — punem mașina rablagită imediat în spatele lui.
	stranded.global_position = truck.global_position + Vector3(0, 0, -4.0)


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

	if Input.is_action_just_pressed("debug_accept_contract"):
		var available: Array[Dictionary] = cargo_depot.get_available_contracts()
		if not available.is_empty():
			cargo_depot.accept_contract(available[0].get("id"))

	if Input.is_action_just_pressed("debug_toggle_tow"):
		if _tow_hitch.is_hitched():
			_tow_hitch.detach()
		else:
			_tow_hitch.try_attach()
