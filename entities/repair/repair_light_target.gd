class_name RepairLightTarget
extends Interactable
## Una luz de una estructura por reparar (el candil, el fogón; C5.5, D-191), para encenderla o apagarla con E. La crea
## `RepairSiteView`, una por luz, con una caja alrededor de su vacío. No choca: solo la encuentra el rayo de
## interactuar, y solo con la estructura completa (antes no se pone delante de las piezas por reparar).

var _view: RepairSiteView
var _index: int = 0
var _area: Area3D


## Prepara la luz `index` de `view` con su caja (en el espacio de la vista). Se llama ANTES de añadirla.
func setup(view: RepairSiteView, index: int, box: AABB) -> void:
	_view = view
	_index = index
	name = "Light_%d" % index
	display_name_key = view.site.data.lights[index].name_key
	position = box.get_center()
	collision_layer = 0
	var shape := BoxShape3D.new()
	shape.size = box.size
	_area = Area3D.new()
	_area.name = "WorkArea"
	_area.collision_mask = 0
	_area.monitoring = false
	var area_collision := CollisionShape3D.new()
	area_collision.shape = shape
	_area.add_child(area_collision)
	add_child(_area)
	refresh()


## A tiro del rayo solo con la estructura completa.
func refresh() -> void:
	_area.collision_layer = VeinView.WORK_AREA_LAYER if _view.site.is_complete() else 0


func interact(_by: Node) -> void:
	_view.island.switch_repair_light(_view.site.origin, _index, WorldState.player_inventory)


func get_interact_hint_key() -> String:
	if not _view.site.is_complete():
		return ""
	return "HINT_LIGHT_OFF" if _view.site.is_lit(_index) else "HINT_LIGHT_ON"


## Si encenderla gasta algo y no lo llevas: «Necesitas: Madera».
func get_note_text() -> String:
	var fuel: Dictionary[ItemData, int] = _view.site.data.lights[_index].fuel
	if fuel.is_empty() or _view.site.is_lit(_index):
		return ""
	var names: PackedStringArray = []
	for item: ItemData in fuel:
		if WorldState.player_inventory.get_total(item) < fuel[item]:
			names.append(tr(item.name_key))
	return "" if names.is_empty() else tr("HINT_NEEDS_TOOL") % ", ".join(names)
