class_name Towable
extends Node
## towable.gd — Modulul de Economie: tractare.
##
## Se atașează ca nod copil al oricărui vehicul care poate fi tractat
## (practic toate — orice mașină poate fi remorcată). Stare simplă, citită
## și scrisă de TowHitch-ul camionului de tractare.
##
## has_settled() există pentru un motiv concret, găsit prin testare: un
## VehicleBody3D proaspăt apărut oscilează vizibil în timp ce suspensia se
## stabilizează (~1-1.5s, verificat empiric). Un singur vehicul absoarbe
## asta fără probleme, dar un PinJoint3D rigid legat între DOUĂ vehicule
## care oscilează simultan poate amplifica mișcarea până la un blocaj —
## reprodus direct: atașare imediată la apariție a dus la o mașină complet
## blocată, cu engine_force la maxim dar viteză zero. TowHitch refuză
## atașarea până la stabilizare, exact cum CollisionImpactSystem ignoră
## impacturile de așezare la coliziuni (aceeași cauză de fond).
##
## Cronometrul acumulează delta simulat (_process), NU Time.get_ticks_msec()
## — timpul real de perete nu avansează sincron cu frame-urile de fizică
## (mai ales headless, unde motorul rulează mai repede decât timpul real).
## Toate celelalte cronometre din proiect (CargoHold, VehicleDamage,
## TimeOfDay) folosesc aceeași convenție.

@export var settle_time_sec: float = 1.5

var is_hitched: bool = false

var _elapsed_sec: float = 0.0


func _process(delta: float) -> void:
	if _elapsed_sec < settle_time_sec:
		_elapsed_sec += delta


func has_settled() -> bool:
	return _elapsed_sec >= settle_time_sec
