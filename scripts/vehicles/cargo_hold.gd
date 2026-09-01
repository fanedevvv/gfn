class_name CargoHold
extends Node
## cargo_hold.gd — Modulul de Economie: contracte de marfă.
##
## Se atașează ca nod copil al vehiculului — orice mașină poate transporta
## un contract activ (simplificare pentru MVP; o dubă de marfă dedicată,
## cu capacitate mai mare, poate veni mai târziu ca variantă de vehicul).
##
## Design: la fel ca Workshop/JunkyardVendor, nu ascultă taste — expune
## accept_contract()/try_deliver(), apelate de CargoDepot/CargoDropoff.
## Nu se leagă de fizica mașinii (CarController) — e doar stare de
## business, complet independentă de motor/direcție/uzură.

signal contract_accepted(contract: Dictionary)
signal contract_completed(contract: Dictionary, payout: int)
signal contract_failed(contract: Dictionary, reason: String)
signal time_remaining_changed(seconds: float)

var active_contract: Dictionary = {}

var _time_remaining: float = 0.0
var _has_time_limit: bool = false


func has_active_contract() -> bool:
	return not active_contract.is_empty()


## Apelată de CargoDepot. Returnează false dacă vehiculul cară deja ceva.
func accept_contract(contract: Dictionary) -> bool:
	if has_active_contract():
		return false

	active_contract = contract
	var limit: float = float(contract.get("time_limit_sec", 0))
	_has_time_limit = limit > 0.0
	_time_remaining = limit

	contract_accepted.emit(active_contract)
	return true


## Apelată de CargoDropoff. Livrează doar dacă destination_id se
## potrivește cu dropoff_id — altfel nu face nimic (marfa greșită la
## locul greșit nu se livrează automat).
func try_deliver(dropoff_id: String) -> bool:
	if not has_active_contract():
		return false
	if active_contract.get("destination_id", "") != dropoff_id:
		return false

	var contract: Dictionary = active_contract
	var payout: int = int(contract.get("payout", 0))
	active_contract = {}
	_has_time_limit = false

	EconomyManager.add_funds(payout)
	contract_completed.emit(contract, payout)
	return true


func _process(delta: float) -> void:
	if not has_active_contract() or not _has_time_limit:
		return

	_time_remaining = max(0.0, _time_remaining - delta)
	time_remaining_changed.emit(_time_remaining)

	if _time_remaining <= 0.0:
		var failed_contract: Dictionary = active_contract
		active_contract = {}
		_has_time_limit = false
		contract_failed.emit(failed_contract, "time_expired")
