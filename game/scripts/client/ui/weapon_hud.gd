extends Label
func update_state(player: Variant, weapon: Resource, ammo: int, charge: float) -> void:
	if player == null:
		text = ""
		return
	text = "%s | Ammo: %s | Charge: %d%%" % [weapon.display_name,"∞" if ammo < 0 else str(ammo),roundi(charge*100)]
	modulate = Color(1,0.5,0.3) if ammo == 0 else Color.WHITE
