extends RefCounted
const Notes = preload("res://scripts/core/replay/replay_notebook.gd")
const Archive = preload("res://scripts/core/replay/replay_archive.gd")
const Clip = preload("res://scripts/core/replay/replay_clip_job.gd")
const Diff = preload("res://scripts/core/replay/replay_diff.gd")
const Bundle = preload("res://scripts/core/storage/archive_bundle.gd")
const Replay = preload("res://scripts/core/replay/match_replay.gd")
static func _load(path: Variant) -> Dictionary:
	if not path is String or path.is_empty() or not Notes.safe_path(ProjectSettings.globalize_path(path).simplify_path()): return Notes.failure("unsafe_or_missing_source")
	return Archive.load_verified(path)
static func run(mode: String, args: Dictionary) -> Dictionary:
	if mode == "verify-bundle":
		var inspected := Bundle.inspect(str(args.get("bundle","")))
		if not inspected.ok: return inspected
		return {"ok":true,"version":1,"entries":inspected.entries,"total_bytes":inspected.total_bytes,"manifest":inspected.manifest}
	if mode not in ["clip-replay","diff-replays"]: return Notes.failure("invalid_studio_mode")
	var first := _load(args.get("source"))
	if not first.ok: return first
	var output: Variant = args.get("output","")
	if not output is String: return Notes.failure("invalid_output")
	if mode == "clip-replay":
		if output.is_empty() or not Notes.integer(args.get("start"),0,100000) or not Notes.integer(args.get("end"),0,100000): return Notes.failure("invalid_clip_arguments")
		var job := Clip.new()
		if not job.begin(first.recorder,int(args.start),int(args.end)): return Notes.failure(job.error)
		while not job.finished:
			var progress := job.step(256)
			if not progress.ok: return progress
		var encoded := Archive.encode(job.result_recorder,job.result_runner)
		if not encoded.ok: return encoded
		var verified := Archive.decode(encoded.payload)
		if not verified.ok: return verified
		var written := Notes.atomic_write(output,JSON.stringify(encoded.payload,"",true,true),false,[args.source])
		if not written.ok: return written
		return {"ok":true,"path":output,"actions":job.result_recorder.data.actions.size(),"start":args.start,"end":args.end,"hash":Replay.state_hash(verified.runner)}
	var second := _load(args.get("second"))
	if not second.ok: return second
	var report := Diff.compare(first.recorder,second.recorder)
	if not report.ok: return report
	if not output.is_empty():
		var written := Diff.export(output,report,false,[args.source,args.second])
		if not written.ok: return written
	return {"ok":true,"report":report}
