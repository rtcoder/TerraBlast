extends RefCounted
static func color(team: int, palette: String) -> Color:
	if palette == "accessible": return Color(0.15,0.65,1) if team == 1 else Color(1,0.75,0.1)
	return Color(0.15,0.36,1) if team == 1 else Color(1,0.18,0.12)
static func label(team: int) -> String: return "A" if team == 1 else "B"
