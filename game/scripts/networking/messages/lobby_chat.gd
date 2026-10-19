extends RefCounted
## Bounded, transport-independent authoritative lobby text history.
const Protocol=preload("res://scripts/networking/messages/match_protocol.gd")
const MAX_MESSAGES:=64
const MAX_BYTES:=65536
var generation:=0
var sequence:=0
var messages:Array=[]
var nonces:Dictionary={}
var author_times:Dictionary={}
var global_times:Array=[]

static func valid_text(value:Variant)->bool:
	if not value is String or value.strip_edges().is_empty() or value.length()>256 or value.to_utf8_buffer().size()>1024: return false
	for i in value.length():
		var code:int=value.unicode_at(i)
		if code<32 or (code>=127 and code<=159): return false
	return true

static func valid_nonce(value:Variant)->bool:
	if not value is String or value.length()!=32: return false
	for c in value:
		if c not in "0123456789abcdef": return false
	return true

static func valid_event(value:Variant)->bool:
	if not value is Dictionary: return false
	var identity:Variant=value.get("author_id")
	if not identity is String or identity.is_empty() or identity.length()>64: return false
	for i in identity.length():
		if identity.unicode_at(i)<32 or identity.unicode_at(i)>=127: return false
	if value.get("author_role")=="spectator" and not Protocol.valid_spectator_id(identity): return false
	return Protocol.integer(value.get("generation"),0,2147483647) and Protocol.integer(value.get("sequence"),1,2147483647) and value.get("author_id") is String and not value.author_id.is_empty() and value.author_id.length()<=64 and Protocol.valid_display_name(value.get("author_name")) and value.get("author_role") in ["player","spectator"] and valid_text(value.get("text")) and valid_nonce(value.get("nonce"))

static func valid_history(value:Variant)->bool:
	if not value is Dictionary or not Protocol.integer(value.get("generation"),0,2147483647) or not Protocol.integer(value.get("first_sequence"),1,2147483647) or not value.get("messages") is Array or value.messages.size()>MAX_MESSAGES: return false
	if JSON.stringify(value.messages).to_utf8_buffer().size()>MAX_BYTES: return false
	var expected:int=int(value.first_sequence)
	for row in value.messages:
		if not valid_event(row) or row.generation!=value.generation or row.sequence!=expected: return false
		expected+=1
	return true

func reset(next_generation:int)->void:
	generation=next_generation
	sequence=0
	messages.clear(); nonces.clear(); author_times.clear(); global_times.clear()

func append(author:Dictionary,text:String,nonce:String,expected_generation:int,now_ms:int)->Dictionary:
	if expected_generation!=generation: return {"ok":false,"reason":"stale_generation"}
	if not valid_text(text) or not valid_nonce(nonce): return {"ok":false,"reason":"invalid_chat"}
	if not author.get("id") is String or not Protocol.valid_display_name(author.get("name")) or author.get("role") not in ["player","spectator"]: return {"ok":false,"reason":"invalid_author"}
	var id:String=author.id
	# Author identities are limited by the server; this independent model also caps them.
	if not nonces.has(id) and nonces.size()>=16: return {"ok":false,"reason":"chat_identity_limit"}
	var cache:Array=nonces.get(id,[])
	if cache.has(nonce): return {"ok":true,"duplicate":true,"reason":""}
	var times:Array=author_times.get(id,[])
	while not times.is_empty() and now_ms-int(times[0])>=10000: times.pop_front()
	while not global_times.is_empty() and now_ms-int(global_times[0])>=10000: global_times.pop_front()
	if times.size()>=4 or global_times.size()>=32: return {"ok":false,"reason":"chat_rate_limit"}
	if sequence>=2147483646: return {"ok":false,"reason":"chat_sequence_limit"}
	times.append(now_ms); global_times.append(now_ms); author_times[id]=times
	cache.append(nonce)
	if cache.size()>64: cache.pop_front()
	nonces[id]=cache
	sequence+=1
	var event:Dictionary={"generation":generation,"sequence":sequence,"author_id":id,"author_name":author.name,"author_role":author.role,"text":text.strip_edges(),"nonce":nonce}
	messages.append(event)
	while messages.size()>MAX_MESSAGES or JSON.stringify(messages).to_utf8_buffer().size()>MAX_BYTES: messages.pop_front()
	return {"ok":true,"duplicate":false,"reason":"","event":event.duplicate(true)}

func history()->Dictionary:
	return {"generation":generation,"first_sequence":messages[0].sequence if not messages.is_empty() else sequence+1,"messages":messages.duplicate(true)}

func forget_identity(id:String)->void:
	nonces.erase(id); author_times.erase(id)
