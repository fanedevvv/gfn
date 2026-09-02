class_name TowHitch
extends Area3D
## tow_hitch.gd — Modulul de Economie: tractare.
##
## Se atașează pe: rădăcina scenei "TowHitch" (Area3D), copil al camionului
## de tractare (vezi tow_truck.tscn), poziționat la capătul care rămâne în
## URMA camionului cât timp acesta se deplasează înainte — NU la eticheta
## "față" din car_base.tscn (vezi nota empirică din chase_camera.gd/
## collision_impact_system.gd despre direcția reală de mers, +Z local).
##
## Detectează vehicule Towable în proximitate; try_attach()/detach() creează
## sau distrug un joint REAL între șasiul camionului și cel al vehiculului
## tractat — o prindere tip cârlig (nu o sudură rigidă), ca vehiculul
## tractat să poată vira liber în urma camionului, exact ca o remorcă.
##
## Generic6DOFJoint3D, NU PinJoint3D — un PinJoint3D e un joint sferic, cu
## rotație complet liberă pe toate axele, nerealist pentru o remorcare reală
## (cârligul unei remorci nu permite tangaj/ruliu independent, doar girație/
## viraje). Blocând tangajul (X) și ruliul (Z) la o marjă mică și lăsând
## girația (Y) liberă, ansamblul se comportă mult mai stabil la accelerații
## bruște — dar NU asta a rezolvat blocajul permanent descris mai jos; vezi
## TRAFFIC_COLLISION_LAYER_BIT din car_controller.gd pentru fixul real.
##
## Blocaj găsit prin testare (test complet în open_world.tscn cu trafic AI
## activ): ansamblul tractat se putea bloca permanent — motorul la forță
## maximă, viteză zero, șasiul înclinat într-un echilibru STABIL dar greșit.
## Bisectat până la cauză: dacă ORICE vehicul din scenă (nu neapărat cel
## tractat) are traficul AI în propriul collision_mask — chiar și un vehicul
## nemișcat, la 40+ m distanță, fără nicio coliziune reală posibilă —
## blocajul apare. Nu ține de solver_iterations, sleep, contact_monitor sau
## bruschețea accelerației (toate testate individual); pare o interacțiune
## la nivelul broadphase-ului motorului fizic Godot, sensibilă la simpla
## PREZENȚĂ a unui corp cu layer-ul detectabil, nu la coliziunea reală.
## Fix: doar vehiculul CONDUS ACTIV de jucător își adaugă bitul traficului
## în mască (vezi TRAFFIC_COLLISION_LAYER_BIT) — el chiar trebuie să
## lovească fizic traficul; vehiculele tractate/parcate nu au nevoie.
signal vehicle_hitched(vehicle: Node3D)
signal vehicle_unhitched(vehicle: Node3D)
signal hitch_denied(reason: String)

@export_group("Joint")
## Marja de tangaj/ruliu permisă (grade) — mică intenționat, doar atât cât
## să absoarbă un hop de suspensie, nu o rotație liberă completă.
@export var pitch_roll_limit_deg: float = 5.0
@export var linear_damping: float = 1.0
@export var angular_damping: float = 1.0

var _vehicle_in_range: RigidBody3D = null
var _towable_in_range: Towable = null

var _hitched_vehicle: RigidBody3D = null
var _hitched_towable: Towable = null
var _joint: Generic6DOFJoint3D = null

@onready var _truck: RigidBody3D = get_parent() as RigidBody3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func is_hitched() -> bool:
	return _joint != null


func get_hitched_vehicle() -> Node3D:
	return _hitched_vehicle


## Prinde vehiculul aflat în proximitate. Returnează false (+ hitch_denied)
## dacă deja tractăm ceva, nu e nimic tractabil în rază, ținta e deja
## prinsă de alt camion, sau ținta încă nu s-a stabilizat (vezi
## Towable.has_settled() — un vehicul proaspăt apărut prins imediat
## poate bloca fizic ansamblul, verificat empiric).
func try_attach() -> bool:
	if is_hitched():
		hitch_denied.emit("already_hitched")
		return false
	if _towable_in_range == null or _towable_in_range.is_hitched:
		hitch_denied.emit("no_towable_in_range")
		return false
	if not _towable_in_range.has_settled():
		hitch_denied.emit("target_not_settled")
		return false

	var target: RigidBody3D = _vehicle_in_range

	# Construim și configurăm joint-ul într-o variabilă LOCALĂ, nu direct în
	# _joint — dacă orice pas de mai jos eșuează, obiectul rămâne în starea
	# curentă (is_hitched()==false), nu într-o stare pe jumătate atașată.
	# Părinte = camionul însuși, nu get_tree().current_scene — acela poate
	# fi null în afara fluxului normal de scenă (ex: instanțiere directă din
	# cod/test), iar Joint3D nu are nevoie să fie frate cu corpurile legate.
	var new_joint: Generic6DOFJoint3D = Generic6DOFJoint3D.new()
	new_joint.node_a = _truck.get_path()
	new_joint.node_b = target.get_path()
	new_joint.exclude_nodes_from_collision = true

	# Poziție blocată pe toate cele 3 axe (limită inferioară = superioară =
	# 0) — echivalentul liniar al unui PinJoint3D, punctul rămâne fix.
	new_joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	new_joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	new_joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	new_joint.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_DAMPING, linear_damping)

	new_joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	new_joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	new_joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	new_joint.set_param_y(Generic6DOFJoint3D.PARAM_LINEAR_DAMPING, linear_damping)

	new_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, true)
	new_joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT, 0.0)
	new_joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT, 0.0)
	new_joint.set_param_z(Generic6DOFJoint3D.PARAM_LINEAR_DAMPING, linear_damping)

	# Tangaj (X) și ruliu (Z) blocate la o marjă mică — vezi comentariul
	# clasei despre echilibrul greșit găsit cu rotație complet liberă.
	# Girație (Y) liberă — remorca trebuie să poată vira în urma camionului.
	var pitch_roll_limit_rad: float = deg_to_rad(pitch_roll_limit_deg)
	new_joint.set_flag_x(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	new_joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -pitch_roll_limit_rad)
	new_joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, pitch_roll_limit_rad)
	new_joint.set_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_DAMPING, angular_damping)

	new_joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
	new_joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT, -pitch_roll_limit_rad)
	new_joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT, pitch_roll_limit_rad)
	new_joint.set_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_DAMPING, angular_damping)

	new_joint.set_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, false)
	new_joint.set_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_DAMPING, angular_damping)

	# global_position necesită ca nodul să fie deja în arbore ca să rezolve
	# transformarea (altfel Godot dă "!is_inside_tree()") — deci add_child()
	# ÎNTÂI, poziția globală DUPĂ.
	_truck.add_child(new_joint)
	new_joint.global_position = (_truck.global_position + target.global_position) / 2.0

	_joint = new_joint
	_hitched_vehicle = target
	_hitched_towable = _towable_in_range
	_hitched_towable.is_hitched = true

	vehicle_hitched.emit(target)
	return true


func detach() -> void:
	if not is_hitched():
		return

	_joint.queue_free()
	_joint = null

	if _hitched_towable:
		_hitched_towable.is_hitched = false

	var vehicle: Node3D = _hitched_vehicle
	_hitched_vehicle = null
	_hitched_towable = null

	vehicle_unhitched.emit(vehicle)


func _on_body_entered(body: Node3D) -> void:
	if body == _truck:
		return
	var towable: Towable = _find_towable(body)
	if towable == null:
		return
	_vehicle_in_range = body as RigidBody3D
	_towable_in_range = towable


func _on_body_exited(body: Node3D) -> void:
	if body == _vehicle_in_range:
		_vehicle_in_range = null
		_towable_in_range = null


func _find_towable(vehicle: Node3D) -> Towable:
	for child in vehicle.get_children():
		if child is Towable:
			return child
	return null
