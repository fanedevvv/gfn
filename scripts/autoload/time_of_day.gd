extends Node
## time_of_day.gd — Autoload: ceasul jocului, sursă unică pentru ora curentă.
##
## Nu controlează direct soarele sau cerul — doar avansează timpul și emite
## semnale. Prezentarea (rotația soarelui, culorile cerului) e treaba unui
## SunController separat, plasat în fiecare scenă de lume (vezi
## scripts/world/sun_controller.gd), care se abonează la time_changed. Așa,
## orice alt sistem (trafic, poliție, radare, HUD cu ceas) poate reacționa
## la oră fără să știe nimic despre lumini sau shadere.
##
## Înregistrare: Project Settings -> Autoload -> acest script ca
## "TimeOfDay" (deja configurat în project.godot).

enum DayPeriod { NIGHT, DAWN, DAY, DUSK }

signal time_changed(hour: float)    ## 0.0-24.0
signal period_changed(period: DayPeriod)
signal day_passed(day_number: int)

@export var day_length_seconds: float = 1200.0  ## cât durează o zi întreagă în timp real (20 min implicit)
@export var starting_hour: float = 8.0
@export var is_paused: bool = false

@export_group("Praguri perioade")
@export var dawn_start_hour: float = 5.5
@export var day_start_hour: float = 7.5
@export var dusk_start_hour: float = 18.5
@export var night_start_hour: float = 20.5

var current_hour: float = 8.0
var current_day: int = 1

var _current_period: DayPeriod = DayPeriod.DAY


func _ready() -> void:
	current_hour = starting_hour
	_current_period = _resolve_period(current_hour)


func _process(delta: float) -> void:
	if is_paused:
		return

	var hours_per_second: float = 24.0 / day_length_seconds
	current_hour += hours_per_second * delta

	if current_hour >= 24.0:
		current_hour = fmod(current_hour, 24.0)
		current_day += 1
		day_passed.emit(current_day)

	time_changed.emit(current_hour)

	var period: DayPeriod = _resolve_period(current_hour)
	if period != _current_period:
		_current_period = period
		period_changed.emit(period)


func get_current_period() -> DayPeriod:
	return _current_period


## 0.0 = miezul nopții, 1.0 = amiază, revine la 0.0 spre miezul nopții
## următor — o curbă continuă, utilă pentru intensitate/culoare fără if-uri
## pe intervale de oră.
func get_normalized_day_progress() -> float:
	return (1.0 - cos(current_hour / 24.0 * TAU)) * 0.5


func _resolve_period(hour: float) -> DayPeriod:
	if hour >= night_start_hour or hour < dawn_start_hour:
		return DayPeriod.NIGHT
	if hour < day_start_hour:
		return DayPeriod.DAWN
	if hour < dusk_start_hour:
		return DayPeriod.DAY
	return DayPeriod.DUSK
