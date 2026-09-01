extends CanvasLayer
## garage_ui.gd — UI pentru Atelier + Junkyard.
##
## Se atașează pe: rădăcina scenei "GarageUI" (CanvasLayer) — vezi
## garage_ui.tscn. Nu se leagă automat de niciun Workshop/JunkyardVendor —
## scena de joc apelează bind_workshop()/bind_junkyard() cu instanțele din
## nivel. Nu adaugă nicio logică de business nouă: doar afișează starea și
## apelează metodele publice deja expuse de cele două componente.
##
## Panourile se arată/ascund pe baza semnalelor de proximitate
## (vehicle_entered/vehicle_exited) — identice ca formă la Workshop și
## JunkyardVendor, deci codul de legare e simetric pentru ambele.

@onready var workshop_panel: PanelContainer = %WorkshopPanel
@onready var junkyard_panel: PanelContainer = %JunkyardPanel

@onready var brakes_status_label: Label = %BrakesStatusLabel
@onready var brakes_cost_label: Label = %BrakesCostLabel
@onready var brakes_button: Button = %BrakesButton

@onready var clutch_status_label: Label = %ClutchStatusLabel
@onready var clutch_cost_label: Label = %ClutchCostLabel
@onready var clutch_button: Button = %ClutchButton

@onready var oil_status_label: Label = %OilStatusLabel
@onready var oil_cost_label: Label = %OilCostLabel
@onready var oil_button: Button = %OilButton

@onready var tires_status_label: Label = %TiresStatusLabel
@onready var tires_cost_label: Label = %TiresCostLabel
@onready var tires_button: Button = %TiresButton

@onready var repair_all_cost_label: Label = %RepairAllCostLabel
@onready var repair_all_button: Button = %RepairAllButton
@onready var workshop_feedback_label: Label = %WorkshopFeedbackLabel

@onready var listings_container: VBoxContainer = %ListingsContainer
@onready var junkyard_feedback_label: Label = %JunkyardFeedbackLabel

var _workshop: Workshop = null
var _junkyard: JunkyardVendor = null
var _damage: VehicleDamage = null


func _ready() -> void:
	workshop_panel.visible = false
	junkyard_panel.visible = false

	brakes_button.pressed.connect(_on_brakes_button_pressed)
	clutch_button.pressed.connect(_on_clutch_button_pressed)
	oil_button.pressed.connect(_on_oil_button_pressed)
	tires_button.pressed.connect(_on_tires_button_pressed)
	repair_all_button.pressed.connect(_on_repair_all_button_pressed)


# ---------------------------------------------------------------------------
# LEGARE — apelată din scena de joc, nu automat
# ---------------------------------------------------------------------------

func bind_workshop(workshop: Workshop) -> void:
	unbind_workshop()
	_workshop = workshop
	_workshop.vehicle_entered.connect(_on_workshop_vehicle_entered)
	_workshop.vehicle_exited.connect(_on_workshop_vehicle_exited)
	_workshop.repair_completed.connect(_on_repair_completed)
	_workshop.repair_denied.connect(_on_repair_denied)


func unbind_workshop() -> void:
	if _workshop == null:
		return
	if _workshop.vehicle_entered.is_connected(_on_workshop_vehicle_entered):
		_workshop.vehicle_entered.disconnect(_on_workshop_vehicle_entered)
	if _workshop.vehicle_exited.is_connected(_on_workshop_vehicle_exited):
		_workshop.vehicle_exited.disconnect(_on_workshop_vehicle_exited)
	if _workshop.repair_completed.is_connected(_on_repair_completed):
		_workshop.repair_completed.disconnect(_on_repair_completed)
	if _workshop.repair_denied.is_connected(_on_repair_denied):
		_workshop.repair_denied.disconnect(_on_repair_denied)
	_unbind_damage()
	_workshop = null
	workshop_panel.visible = false


func bind_junkyard(junkyard: JunkyardVendor) -> void:
	unbind_junkyard()
	_junkyard = junkyard
	_junkyard.vehicle_entered.connect(_on_junkyard_vehicle_entered)
	_junkyard.vehicle_exited.connect(_on_junkyard_vehicle_exited)
	_junkyard.catalog_loaded.connect(_on_catalog_loaded)
	_junkyard.vehicle_purchased.connect(_on_vehicle_purchased)
	_junkyard.purchase_denied.connect(_on_purchase_denied)
	_rebuild_listings(_junkyard.get_listings())


func unbind_junkyard() -> void:
	if _junkyard == null:
		return
	if _junkyard.vehicle_entered.is_connected(_on_junkyard_vehicle_entered):
		_junkyard.vehicle_entered.disconnect(_on_junkyard_vehicle_entered)
	if _junkyard.vehicle_exited.is_connected(_on_junkyard_vehicle_exited):
		_junkyard.vehicle_exited.disconnect(_on_junkyard_vehicle_exited)
	if _junkyard.catalog_loaded.is_connected(_on_catalog_loaded):
		_junkyard.catalog_loaded.disconnect(_on_catalog_loaded)
	if _junkyard.vehicle_purchased.is_connected(_on_vehicle_purchased):
		_junkyard.vehicle_purchased.disconnect(_on_vehicle_purchased)
	if _junkyard.purchase_denied.is_connected(_on_purchase_denied):
		_junkyard.purchase_denied.disconnect(_on_purchase_denied)
	_junkyard = null
	junkyard_panel.visible = false


# ---------------------------------------------------------------------------
# ATELIER
# ---------------------------------------------------------------------------

func _on_workshop_vehicle_entered(_vehicle: Node3D) -> void:
	_damage = _workshop.get_vehicle_damage()
	if _damage == null:
		return

	_damage.brake_wear_changed.connect(_on_damage_stat_changed)
	_damage.clutch_wear_changed.connect(_on_damage_stat_changed)
	_damage.oil_level_changed.connect(_on_damage_stat_changed)
	_damage.tire_pressure_changed.connect(_on_tire_pressure_changed)

	workshop_feedback_label.text = ""
	_refresh_workshop_display()
	workshop_panel.visible = true


func _on_workshop_vehicle_exited(_vehicle: Node3D) -> void:
	workshop_panel.visible = false
	_unbind_damage()


func _unbind_damage() -> void:
	if _damage == null:
		return
	if _damage.brake_wear_changed.is_connected(_on_damage_stat_changed):
		_damage.brake_wear_changed.disconnect(_on_damage_stat_changed)
	if _damage.clutch_wear_changed.is_connected(_on_damage_stat_changed):
		_damage.clutch_wear_changed.disconnect(_on_damage_stat_changed)
	if _damage.oil_level_changed.is_connected(_on_damage_stat_changed):
		_damage.oil_level_changed.disconnect(_on_damage_stat_changed)
	if _damage.tire_pressure_changed.is_connected(_on_tire_pressure_changed):
		_damage.tire_pressure_changed.disconnect(_on_tire_pressure_changed)
	_damage = null


func _on_damage_stat_changed(_value: float) -> void:
	_refresh_workshop_display()


func _on_tire_pressure_changed(_wheel_index: int, _bar: float) -> void:
	_refresh_workshop_display()


func _refresh_workshop_display() -> void:
	if _damage == null or _workshop == null:
		return

	brakes_status_label.text = "%d%%" % roundi(_damage.brake_wear_percent)
	brakes_cost_label.text = "%d$" % _workshop.brake_repair_cost

	clutch_status_label.text = "%d%%" % roundi(_damage.clutch_wear_percent)
	clutch_cost_label.text = "%d$" % _workshop.clutch_repair_cost

	oil_status_label.text = "%d%%" % roundi(_damage.oil_level_percent)
	oil_cost_label.text = "%d$" % _workshop.oil_refill_cost

	var tires_total_cost: int = _workshop.tire_inflate_cost * _damage.tire_count
	tires_status_label.text = "%d%%" % roundi(_average_tire_pressure_ratio() * 100.0)
	tires_cost_label.text = "%d$" % tires_total_cost

	var repair_all_cost: int = (
		_workshop.brake_repair_cost + _workshop.clutch_repair_cost + _workshop.oil_refill_cost + tires_total_cost
	)
	repair_all_cost_label.text = "%d$" % repair_all_cost


func _average_tire_pressure_ratio() -> float:
	if _damage.tire_pressures.is_empty():
		return 0.0
	var total: float = 0.0
	for pressure in _damage.tire_pressures:
		total += pressure
	return (total / _damage.tire_pressures.size()) / _damage.tire_pressure_full_bar


func _on_brakes_button_pressed() -> void:
	if _workshop:
		_workshop.repair_brakes()


func _on_clutch_button_pressed() -> void:
	if _workshop:
		_workshop.repair_clutch()


func _on_oil_button_pressed() -> void:
	if _workshop:
		_workshop.refill_oil()


func _on_tires_button_pressed() -> void:
	if _workshop == null or _damage == null:
		return
	for i in _damage.tire_count:
		_workshop.inflate_tire(i)


func _on_repair_all_button_pressed() -> void:
	if _workshop:
		_workshop.repair_all()


func _on_repair_completed(_vehicle: Node3D, part_name: String, cost: int) -> void:
	workshop_feedback_label.text = "Reparat '%s' pentru %d$ — fonduri: %d$" % [part_name, cost, EconomyManager.funds]


func _on_repair_denied(part_name: String, cost: int) -> void:
	workshop_feedback_label.text = "Fonduri insuficiente pentru '%s' (cost %d$, ai %d$)" % [part_name, cost, EconomyManager.funds]


# ---------------------------------------------------------------------------
# JUNKYARD
# ---------------------------------------------------------------------------

func _on_junkyard_vehicle_entered(_vehicle: Node3D) -> void:
	junkyard_feedback_label.text = ""
	junkyard_panel.visible = true


func _on_junkyard_vehicle_exited(_vehicle: Node3D) -> void:
	junkyard_panel.visible = false


func _on_catalog_loaded(listings: Array[Dictionary]) -> void:
	_rebuild_listings(listings)


func _rebuild_listings(listings: Array[Dictionary]) -> void:
	for child in listings_container.get_children():
		child.queue_free()

	for listing in listings:
		listings_container.add_child(_build_listing_row(listing))


func _build_listing_row(listing: Dictionary) -> Control:
	var row: HBoxContainer = HBoxContainer.new()

	var name_label: Label = Label.new()
	name_label.text = str(listing.get("display_name", listing.get("id", "?")))
	name_label.custom_minimum_size.x = 220
	row.add_child(name_label)

	var price_label: Label = Label.new()
	price_label.text = "%d$" % int(listing.get("price", 0))
	price_label.custom_minimum_size.x = 70
	row.add_child(price_label)

	var buy_button: Button = Button.new()
	buy_button.text = "Cumpără"
	var listing_id: String = str(listing.get("id", ""))
	buy_button.pressed.connect(func() -> void: _on_buy_button_pressed(listing_id))
	row.add_child(buy_button)

	return row


func _on_buy_button_pressed(listing_id: String) -> void:
	if _junkyard:
		_junkyard.purchase(listing_id)


func _on_vehicle_purchased(listing_id: String, _vehicle: Node3D) -> void:
	junkyard_feedback_label.text = "Cumpărat '%s' — fonduri: %d$" % [listing_id, EconomyManager.funds]


func _on_purchase_denied(listing_id: String, reason: String) -> void:
	junkyard_feedback_label.text = "Cumpărare eșuată '%s': %s" % [listing_id, reason]
