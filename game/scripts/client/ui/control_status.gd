extends RefCounted
static func describe(context: Dictionary) -> Dictionary:
	for rule in [["ended","Match ended"],["projectile","Projectile in flight"],["menu","Menu open"],["bot","Bot is planning"],["remote_blocked","Waiting for your online turn"],["training_waiting","Training: review result, then Continue"],["no_ammo","Selected weapon has no ammunition"]]:
		if context.get(rule[0],false): return {"can_control":false,"reason":rule[1]}
	return {"can_control":true,"reason":""}
