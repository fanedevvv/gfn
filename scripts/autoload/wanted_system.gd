extends Node
## wanted_system.gd — Autoload: nivelul de căutare al jucătorului.
##
## Radarele de viteză (și, pe viitor, alte încălcări — accidente, sens
## interzis) raportează aici prin report_violation(). Patrulele de poliție
## ascultă wanted_level_changed / is_wanted() ca să decidă când intră în
## urmărire — niciun sistem nu vorbește direct cu celălalt.
##
## Înregistrare: Project Settings -> Autoload -> acest script ca
## "WantedSystem" (deja configurat în project.godot).

signal wanted_level_changed(new_level: int)
signal fine_issued(amount: int, reason: String)

const MAX_WANTED_LEVEL: int = 5

@export var wanted_decay_time_sec: float = 30.0  ## fără încălcări noi, nivelul scade după atât

var wanted_level: int = 0

var _decay_timer: float = 0.0


func _process(delta: float) -> void:
	if wanted_level <= 0:
		return

	_decay_timer -= delta
	if _decay_timer <= 0.0:
		_set_wanted_level(wanted_level - 1)
		_decay_timer = wanted_decay_time_sec


## Raportează o încălcare: aplică amenda (limitată la ce are jucătorul —
## nu împingem în datorie) și crește nivelul de căutare.
func report_violation(_vehicle: Node3D, fine: int, reason: String) -> void:
	var actual_fine: int = min(fine, EconomyManager.funds)
	EconomyManager.spend(actual_fine, "fine_%s" % reason)
	fine_issued.emit(actual_fine, reason)

	_set_wanted_level(min(MAX_WANTED_LEVEL, wanted_level + 1))
	_decay_timer = wanted_decay_time_sec


func is_wanted() -> bool:
	return wanted_level > 0


func _set_wanted_level(level: int) -> void:
	level = clamp(level, 0, MAX_WANTED_LEVEL)
	if level == wanted_level:
		return
	wanted_level = level
	wanted_level_changed.emit(wanted_level)
