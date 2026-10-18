extends RefCounted
const DEFAULTS := {"reservation_seconds":30.0,"hello_seconds":5.0,"packets_per_second":100,"bytes_per_second":65536,"snapshot_chunks_per_frame":8,"snapshot_bytes_per_frame":1048576,"receive_bytes_per_frame":131072}
const LIMITS := {"reservation_seconds":[1,300],"hello_seconds":[1,30],"packets_per_second":[60,1000],"bytes_per_second":[8192,1048576],"snapshot_chunks_per_frame":[1,64],"snapshot_bytes_per_frame":[65536,8388608],"receive_bytes_per_frame":[8192,4194304]}
var values := DEFAULTS.duplicate()
func apply(candidate: Dictionary) -> Dictionary:
	var next:=values.duplicate()
	for key in candidate:
		var v: Variant=candidate[key]
		if not DEFAULTS.has(key) or not (v is int or v is float) or not is_finite(float(v)): return {"ok":false,"reason":"invalid_option"}
		if v<LIMITS[key][0] or v>LIMITS[key][1] or (DEFAULTS[key] is int and v!=int(v)): return {"ok":false,"reason":"invalid_option"}
		next[key]=v
	values=next
	return {"ok":true,"reason":""}
