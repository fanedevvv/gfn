class_name CargoDropoff
extends Area3D
## cargo_dropoff.gd — Modulul de Economie: punct de livrare marfă.
##
## Se atașează pe: rădăcina scenei "CargoDropoff" (Area3D).
## Noduri copil necesare (vezi cargo_dropoff.tscn): CollisionShape3D
##
## Spre deosebire de Workshop/JunkyardVendor, nu are nevoie de interacțiune
## explicită — dacă vehiculul care intră aici cară un contract al cărui
## destination_id se potrivește cu dropoff_id, livrarea se face automat la
## sosire (ca într-un joc de curierat: ajungi, se descarcă, primești banii).
## Dacă vehiculul cară alt contract (destinație greșită), nu se întâmplă
## nimic — poate continua drumul spre destinația corectă.

signal delivery_completed(contract: Dictionary, payout: int, vehicle: Node3D)

@export var dropoff_id: String = ""


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player_vehicle"):
		return

	var cargo_hold: CargoHold = _find_cargo_hold(body)
	if cargo_hold == null or not cargo_hold.has_active_contract():
		return

	var contract: Dictionary = cargo_hold.active_contract
	if cargo_hold.try_deliver(dropoff_id):
		delivery_completed.emit(contract, int(contract.get("payout", 0)), body)


func _find_cargo_hold(vehicle: Node3D) -> CargoHold:
	for child in vehicle.get_children():
		if child is CargoHold:
			return child
	return null
