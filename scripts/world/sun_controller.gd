extends DirectionalLight3D
## sun_controller.gd — Se atașează direct pe nodul "Sun" (DirectionalLight3D)
## dintr-o scenă de lume (vezi open_world.tscn).
##
## Se abonează la TimeOfDay.time_changed și rotește soarele + ajustează
## intensitatea/culoarea în funcție de oră. Pur prezentare — nu ține nicio
## stare proprie de timp, asta rămâne exclusiv la TimeOfDay (autoload).
##
## Rotația Y (azimut, direcția est-vest) rămâne cea setată manual în editor
## pe acest nod — scriptul animează doar X (arcul de înălțime al soarelui
## pe cer), ca să poți orienta soarele diferit per hartă fără să atingi codul.

@export var sunrise_color: Color = Color(1.0, 0.65, 0.4)
@export var noon_color: Color = Color(1.0, 0.98, 0.92)
@export var night_color: Color = Color(0.25, 0.35, 0.55)
@export var max_energy: float = 1.2
@export var night_energy: float = 0.05

## Opțional: un WorldEnvironment din aceeași scenă, ca ambianța/cerul să se
## întunece odată cu soarele. Lasă gol dacă scena nu are WorldEnvironment.
@export var world_environment_path: NodePath

@onready var _world_environment: WorldEnvironment = _resolve_world_environment()


func _ready() -> void:
	TimeOfDay.time_changed.connect(_on_time_changed)
	_on_time_changed(TimeOfDay.current_hour)


func _resolve_world_environment() -> WorldEnvironment:
	if world_environment_path == NodePath():
		return null
	return get_node_or_null(world_environment_path) as WorldEnvironment


func _on_time_changed(hour: float) -> void:
	# Soarele descrie un arc complet în 24h; sub orizont noaptea.
	var sun_angle_deg: float = (hour / 24.0) * 360.0 - 90.0
	rotation_degrees.x = -sun_angle_deg

	var day_progress: float = TimeOfDay.get_normalized_day_progress()
	light_energy = lerp(night_energy, max_energy, day_progress)
	light_color = _color_for_progress(day_progress)

	if _world_environment and _world_environment.environment:
		_world_environment.environment.ambient_light_energy = lerp(0.05, 1.0, day_progress)
		_world_environment.environment.background_energy_multiplier = lerp(0.05, 1.0, day_progress)


func _color_for_progress(day_progress: float) -> Color:
	if day_progress < 0.5:
		# noapte -> răsărit/apus (aceeași culoare de tranziție pe ambele capete ale arcului)
		return night_color.lerp(sunrise_color, day_progress * 2.0)
	# răsărit/apus -> amiază
	return sunrise_color.lerp(noon_color, (day_progress - 0.5) * 2.0)
