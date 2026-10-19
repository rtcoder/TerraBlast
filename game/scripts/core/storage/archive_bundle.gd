extends RefCounted
## A bounded ZIP transport for verified library envelopes, never arbitrary extraction.
const Library = preload("res://scripts/core/storage/local_archive_library.gd")
const Archive = preload("res://scripts/core/replay/replay_archive.gd")
const Session = preload("res://scripts/core/replay/session_store.gd")
const Notes = preload("res://scripts/core/replay/replay_notebook.gd")
const MAX_ENTRIES := 20
const MAX_MEMBER := 32*1024*1024
const MAX_TOTAL := 64*1024*1024
const FORMAT := "terrablast_bundle"
static func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
static func _valid_member(name: String) -> bool:
	return name == "manifest.json" or (name.begins_with("entries/") and name.ends_with(".json") and Library.valid_id(name.trim_prefix("entries/").trim_suffix(".json")))
static func _central_directory(bytes: PackedByteArray) -> Dictionary:
	# Inspect declared inflate sizes BEFORE asking ZIPReader to decompress anything.
	if bytes.size() < 22 or bytes.size() > MAX_TOTAL: return Notes.failure("bundle_size_limit")
	var footer := -1
	for cursor in range(bytes.size()-22,maxi(-1,bytes.size()-65558),-1):
		if bytes.decode_u32(cursor) == 0x06054b50 and cursor+22+bytes.decode_u16(cursor+20) == bytes.size(): footer = cursor; break
	if footer < 0: return Notes.failure("invalid_zip_directory")
	var count := bytes.decode_u16(footer+10)
	var central_size := bytes.decode_u32(footer+12)
	var offset := bytes.decode_u32(footer+16)
	if bytes.decode_u16(footer+4) != 0 or bytes.decode_u16(footer+6) != 0 or bytes.decode_u16(footer+8) != count or count < 2 or count > MAX_ENTRIES+1 or offset+central_size != footer: return Notes.failure("zip_member_limit_or_multidisk")
	var cursor := offset
	var total := 0
	var members := {}
	for unused in count:
		if cursor+46 > footer or bytes.decode_u32(cursor) != 0x02014b50: return Notes.failure("invalid_central_header")
		var flags := bytes.decode_u16(cursor+8)
		var method := bytes.decode_u16(cursor+10)
		var compressed := bytes.decode_u32(cursor+20)
		var size := bytes.decode_u32(cursor+24)
		var name_length := bytes.decode_u16(cursor+28)
		var extra := bytes.decode_u16(cursor+30)
		var comment := bytes.decode_u16(cursor+32)
		var local := bytes.decode_u32(cursor+42)
		var end := cursor+46+name_length+extra+comment
		if end > footer or size > MAX_MEMBER or compressed > MAX_TOTAL or flags & 1 or method not in [0,8] or bytes.decode_u16(cursor+34) != 0 or ((bytes.decode_u32(cursor+38) >> 16) & 0xf000) == 0xa000: return Notes.failure("unsafe_zip_member")
		var name := bytes.slice(cursor+46,cursor+46+name_length).get_string_from_utf8()
		if not _valid_member(name) or members.has(name): return Notes.failure("unsafe_or_duplicate_zip_path")
		if local+30 > offset or bytes.decode_u32(local) != 0x04034b50: return Notes.failure("invalid_local_header")
		var local_name := bytes.decode_u16(local+26)
		var data_start := local+30+local_name+bytes.decode_u16(local+28)
		if data_start+compressed > offset or bytes.slice(local+30,local+30+local_name).get_string_from_utf8() != name or bytes.decode_u16(local+8) != method or bytes.decode_u16(local+6) & 1: return Notes.failure("invalid_local_member")
		total += size
		if total > MAX_TOTAL: return Notes.failure("inflate_total_limit")
		members[name] = size
		cursor = end
	if cursor != footer or not members.has("manifest.json"): return Notes.failure("manifest_missing")
	return {"ok":true,"members":members,"total":total}
static func inspect(path: String) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	if not Notes.safe_path(absolute): return Notes.failure("unsafe_bundle_path")
	var file := FileAccess.open(absolute,FileAccess.READ)
	if file == null: return Notes.failure("bundle_open_failed")
	if file.get_length() > MAX_TOTAL: file.close(); return Notes.failure("bundle_size_limit")
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var central := _central_directory(bytes)
	if not central.ok: return central
	var reader := ZIPReader.new()
	if reader.open(absolute) != OK: return Notes.failure("invalid_zip")
	var manifest_bytes := reader.read_file("manifest.json")
	if manifest_bytes.size() != central.members["manifest.json"]: reader.close(); return Notes.failure("member_size_mismatch")
	var manifest: Variant = JSON.parse_string(manifest_bytes.get_string_from_utf8())
	if not manifest is Dictionary or manifest.size() != 3 or manifest.get("format") != FORMAT or manifest.get("version") != 1 or not manifest.get("entries") is Array or manifest.entries.is_empty() or manifest.entries.size() > MAX_ENTRIES or central.members.size() != manifest.entries.size()+1: reader.close(); return Notes.failure("invalid_manifest")
	var entries: Array[Dictionary] = []
	var envelopes: Array[Dictionary] = []
	var ids := {}
	for row in manifest.entries:
		if not row is Dictionary or row.size() != 6 or not Library.valid_id(str(row.get("id",""))) or row.get("kind") not in ["replay","session"] or not row.get("title") is String or not Library.valid_title(row.title) or not Notes.hex_string(row.get("sha256"),64) or not Notes.integer(row.get("size"),1,MAX_MEMBER) or row.get("file") != "entries/"+row.id+".json" or ids.has(row.id) or central.members.get(row.file) != row.size: reader.close(); return Notes.failure("invalid_manifest_entry")
		ids[row.id] = true
		var content := reader.read_file(row.file)
		if content.size() != int(row.size) or _hash(content) != row.sha256: reader.close(); return Notes.failure("member_hash_mismatch")
		var envelope: Variant = JSON.parse_string(content.get_string_from_utf8())
		if not envelope is Dictionary or envelope.size() != 4 or envelope.get("format") != Library.FORMAT or envelope.get("version") != 1 or not envelope.get("metadata") is Dictionary or envelope.metadata.size() != 4 or envelope.metadata.get("id") != row.id or envelope.metadata.get("title") != row.title or envelope.metadata.get("kind") != row.kind or not Notes.integer(envelope.metadata.get("created"),0,9223372036854775807) and not (envelope.metadata.get("created") is float and is_finite(envelope.metadata.created) and envelope.metadata.created >= 0): reader.close(); return Notes.failure("invalid_envelope")
		var verified: Dictionary = Archive.decode(envelope.get("payload")) if row.kind == "replay" else Session.decode(envelope.get("payload"))
		if not verified.ok: reader.close(); return Notes.failure("invalid_payload: "+str(verified.get("reason","unknown")))
		entries.append(row.duplicate(true))
		envelopes.append(envelope.duplicate(true))
	reader.close()
	return {"ok":true,"entries":entries,"envelopes":envelopes,"total_bytes":central.total,"manifest":manifest}
static func export_bundle(library: RefCounted, ids: Array, path: String, replace := false) -> Dictionary:
	if ids.is_empty() or ids.size() > MAX_ENTRIES: return Notes.failure("bundle_entry_limit")
	var absolute := ProjectSettings.globalize_path(path).simplify_path()
	if not Notes.safe_path(absolute) or absolute == library.base_path or absolute.begins_with(library.base_path+"/") or path.begins_with("res://"): return Notes.failure("unsafe_output")
	if FileAccess.file_exists(absolute) and not replace: return Notes.failure("output_exists")
	var manifest := {"format":FORMAT,"version":1,"entries":[]}
	var contents := {}
	var total := 0
	for id in ids:
		if not id is String or not Library.valid_id(id) or contents.has(id): return Notes.failure("invalid_or_duplicate_id")
		var read: Dictionary = library._read(id)
		if not read.ok: return read
		var loaded: Dictionary = library.load_entry(id)
		if not loaded.ok: return loaded
		var content := JSON.stringify(read.envelope,"",true,true).to_utf8_buffer()
		total += content.size()
		if content.size() > MAX_MEMBER or total > MAX_TOTAL: return Notes.failure("bundle_size_limit")
		contents[id] = content
		manifest.entries.append({"id":id,"kind":read.envelope.metadata.kind,"title":read.envelope.metadata.title,"file":"entries/"+id+".json","size":content.size(),"sha256":_hash(content)})
	if total + JSON.stringify(manifest,"",true,true).to_utf8_buffer().size() > MAX_TOTAL: return Notes.failure("bundle_size_limit")
	var temporary := absolute+".tmp-"+Crypto.new().generate_random_bytes(16).hex_encode()
	var writer := ZIPPacker.new()
	if writer.open(temporary) != OK: return Notes.failure("bundle_write_failed")
	var error := writer.start_file("manifest.json")
	if error == OK: error = writer.write_file(JSON.stringify(manifest,"",true,true).to_utf8_buffer())
	writer.close_file()
	for row in manifest.entries:
		if error != OK: break
		error = writer.start_file(row.file)
		if error == OK: error = writer.write_file(contents[row.id])
		writer.close_file()
	var close_error := writer.close()
	if error == OK: error = close_error
	if error == OK:
		var verified := inspect(temporary)
		if not verified.ok: error = ERR_INVALID_DATA
	if error == OK and Notes.safe_path(absolute): error = DirAccess.rename_absolute(temporary,absolute)
	else: error = ERR_FILE_CANT_WRITE
	if error != OK: DirAccess.remove_absolute(temporary); return Notes.failure("bundle_write_failed")
	return {"ok":true,"path":path,"count":ids.size()}
static func import_bundle(library: RefCounted, path: String) -> Dictionary:
	var bundle := inspect(path)
	if not bundle.ok: return bundle
	var ready: Dictionary = library._ready_directory(true)
	if not ready.ok: return ready
	var count := 0
	for filename in DirAccess.get_files_at(library.base_path):
		if filename.get_extension() == "json" and Library.valid_id(filename.get_basename()): count += 1
	if count+bundle.entries.size() > Library.MAX_ENTRIES: return Notes.failure("entry_limit")
	var saved: Array[String] = []
	for envelope in bundle.envelopes:
		var result: Dictionary = library._save_encoded(envelope.metadata.kind,envelope.metadata.title,{"ok":true,"payload":envelope.payload})
		if not result.ok:
			for id in saved: library.delete_entry(id)
			return Notes.failure("import_rolled_back: "+str(result.get("reason","failed")))
		saved.append(result.id)
	return {"ok":true,"ids":saved,"count":saved.size()}
