class_name Valve
extends Interactable
## valve.gd — Modulul 3: valvă rotativă de mentenanță.
##
## Se atașează pe: rădăcina scenei "Valve" (StaticBody3D, moștenește
## scripts/components/interactable.gd).
## Noduri copil necesare (vezi valve.tscn):
##   CollisionShape3D
##   Wheel (MeshInstance3D) — roata care se rotește vizual cât timp e ținută
##   AudioStreamPlayer3D — scârțâitul metalic în timpul reparației
##
## Notă tematică: repararea unei valve e o interacțiune ținută, deci
## jucătorul e "prins pe loc" câteva secunde și emite zgomot continuu —
## exact genul de moment în care Silt (Modulul 2) poate trece în HUNTING
## dacă e prin apropiere. Riscul e parte din mecanică, nu un bug.

@export var noise_radius: float = 9.0
@export var noise_interval: float = 0.4
@export var noise_intensity: float = 0.7
@export var wheel_total_turns: float = 3.0

@onready var wheel: MeshInstance3D = $Wheel
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

var _noise_timer: float = 0.0


func _ready() -> void:
	requires_hold = true
	if interaction_prompt == "Interacționează":
		interaction_prompt = "Ține apăsat [E] pentru a repara valva"


func _on_hold_tick(_player: Node3D, delta: float) -> void:
	wheel.rotation.y = _hold_progress * wheel_total_turns * TAU

	if not audio_player.playing:
		audio_player.play()

	_noise_timer -= delta
	if _noise_timer <= 0.0:
		_noise_timer = noise_interval
		SoundManager.emit_noise(global_position, noise_radius, noise_intensity)


func _on_hold_cancelled() -> void:
	if audio_player.playing:
		audio_player.stop()


func _on_interact(_player: Node3D) -> void:
	is_interactable = false
	audio_player.stop()
	interaction_prompt = "Valvă reparată"
