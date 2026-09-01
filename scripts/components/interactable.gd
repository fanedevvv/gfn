class_name Interactable
extends StaticBody3D
## interactable.gd — Modulul 3: bază comună pentru toate obiectele
## interactive din nivel (valve, uși, manete, panouri de siguranțe).
##
## Contract cu player.gd (Modulul 1):
##   - apăsare scurtă pe 'interact' -> Player apelează interact(player)
##   - ținere apăsată pe 'interact' -> Player apelează process_hold(player, delta)
##     în fiecare frame, atâta timp cât ținta rămâne aceeași
##
## Subclasele NU suprascriu interact()/process_hold() direct — suprascriu
## metodele _on_* de mai jos, ca logica comună (semnale, validare
## is_interactable) să rămână garantată pentru toate obiectele.

## Text afișat în UI (Modulul 4) când raza jucătorului lovește acest obiect.
@export var interaction_prompt: String = "Interacționează"

## False dezactivează obiectul (ex: o valvă deja reparată).
@export var is_interactable: bool = true

## True dacă obiectul se folosește prin ținere apăsată (progres în timp),
## nu prin apăsare scurtă. Setează-l în _ready() al subclasei.
@export var requires_hold: bool = false

## Durata (secunde) cât trebuie ținută tasta pentru a finaliza interacțiunea,
## dacă requires_hold e true.
@export var hold_duration: float = 3.0

signal interacted(player: Node3D)
signal hold_progress_changed(progress: float)  # 0.0-1.0
signal hold_completed(player: Node3D)

var _hold_progress: float = 0.0


func interact(player: Node3D) -> void:
	if requires_hold or not is_interactable:
		return
	_on_interact(player)
	interacted.emit(player)


## Apelat de player.gd în fiecare frame cât timp tasta e ținută și ținta e
## acest obiect. Returnează true când interacțiunea s-a finalizat.
func process_hold(player: Node3D, delta: float) -> bool:
	if not requires_hold or not is_interactable:
		return true

	_hold_progress = min(1.0, _hold_progress + delta / hold_duration)
	hold_progress_changed.emit(_hold_progress)
	_on_hold_tick(player, delta)

	if _hold_progress >= 1.0:
		_on_interact(player)
		interacted.emit(player)
		hold_completed.emit(player)
		return true

	return false


## Apelat de player.gd când jucătorul dă drumul tastei sau privește în altă
## parte înainte ca ținerea să se finalizeze. Progresul NU se resetează
## implicit — jucătorul poate relua mai târziu (util când Silt se apropie).
func cancel_hold() -> void:
	_on_hold_cancelled()


func get_hold_progress() -> float:
	return _hold_progress


## Suprascrie în subclase: logica declanșată la finalizarea interacțiunii.
func _on_interact(_player: Node3D) -> void:
	pass


## Suprascrie în subclase: logica rulată în fiecare frame cât timp se ține
## tasta apăsată (ex: rotește o roată, emite zgomot periodic).
func _on_hold_tick(_player: Node3D, _delta: float) -> void:
	pass


## Suprascrie în subclase: logica declanșată când ținerea e întreruptă
## înainte de finalizare (ex: oprește un sunet de motor/manivelă).
func _on_hold_cancelled() -> void:
	pass
