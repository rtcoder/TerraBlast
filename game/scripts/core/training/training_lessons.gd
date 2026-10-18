extends RefCounted
const LESSONS := {
	"movement":"Move at least 3 metres from the starting position.",
	"jump":"Jump successfully and land again.",
	"cancel_aim":"Aim, begin charging, then cancel without firing.",
	"accuracy":"Damage an enemy with a shot.",
	"power":"Fire one low-power shot (≤1) and one high-power shot (≥3).",
	"wind":"Read the wind indicator, then damage an enemy.",
	"weapons":"Fire each weapon with ammunition available at lesson start.",
	"safe_fire":"Damage an enemy without damaging your team.",
	"blind_accuracy":"Damage an enemy with trajectory assistance disabled.",
	"streak":"Land three consecutive damaging shots.",
	"ammo_budget":"Deal 30 enemy damage in at most three attempts, using a different weapon each time."
}
static func list() -> Array:
	var result := []
	for id in LESSONS: result.append({"id":id,"description":LESSONS[id]})
	return result
static func get_lesson(id: String) -> Dictionary:
	return {"id":id,"description":LESSONS[id]} if LESSONS.has(id) else {}
