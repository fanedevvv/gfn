extends Node
## economy_manager.gd — Autoload: portofelul jucătorului.
##
## Orice sistem de economie (atelier, junkyard, contracte de marfă, vânzare
## de vehicule restaurate) trece prin acest singleton — o singură sursă de
## adevăr pentru bani, ca să nu existe stări divergente între module.
##
## Înregistrare: Project Settings -> Autoload -> acest script ca
## "EconomyManager" (deja configurat în project.godot).

signal funds_changed(new_amount: int)
signal transaction_denied(amount: int, reason: String)

@export var starting_funds: int = 500

var funds: int = 0


func _ready() -> void:
	funds = starting_funds


func can_afford(amount: int) -> bool:
	return amount >= 0 and funds >= amount


## Încearcă să scadă `amount` din portofel. Returnează false și emite
## transaction_denied dacă nu sunt bani destui — apelantul (Workshop,
## Junkyard etc.) decide ce face în acest caz, EconomyManager doar refuză.
func spend(amount: int, reason: String = "") -> bool:
	if amount < 0:
		return false
	if not can_afford(amount):
		transaction_denied.emit(amount, reason)
		return false
	funds -= amount
	funds_changed.emit(funds)
	return true


func add_funds(amount: int) -> void:
	if amount <= 0:
		return
	funds += amount
	funds_changed.emit(funds)
