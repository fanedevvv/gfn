class_name TowDropoff
extends Area3D
## tow_dropoff.gd — Modulul de Economie: punct de livrare pentru tractare.
##
## Se atașează pe: rădăcina scenei "TowDropoff" (Area3D).
## Noduri copil necesare (vezi tow_dropoff.tscn): CollisionShape3D
##
## Când camionul de tractare (cu TowHitch activ) intră aici având un
## vehicul tractat, livrarea se face automat — plată fixă + detașare —
## la fel ca CargoDropoff, fără interacțiune explicită.

signal tow_delivered(vehicle: Node3D, payout: int)

@export var payout: int = 300


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player_vehicle"):
		return

	var hitch: TowHitch = _find_tow_hitch(body)
	if hitch == null or not hitch.is_hitched():
		return

	var towed_vehicle: Node3D = hitch.get_hitched_vehicle()
	hitch.detach()
	EconomyManager.add_funds(payout)
	tow_delivered.emit(towed_vehicle, payout)


func _find_tow_hitch(vehicle: Node3D) -> TowHitch:
	for child in vehicle.get_children():
		if child is TowHitch:
			return child
	return null
