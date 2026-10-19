extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok: failures+=1; push_error(label)
func _initialize()->void:
	if not FileAccess.file_exists("res://scripts/networking/messages/lobby_chat.gd"):
		check(false,"Bounded chat model exists"); quit(1); return
	var Chat=load("res://scripts/networking/messages/lobby_chat.gd")
	var chat=Chat.new()
	chat.reset(1)
	var author={"id":"blue_1","name":"Blue","role":"player"}
	for text in ["", " ", "x\n", "x\t", "x".repeat(257), "😀".repeat(257)]: check(not Chat.valid_text(text),"Invalid chat rejected")
	check(Chat.valid_text("Zażółć 😀 [url]"),"Unicode literal accepted")
	for i in range(4): check(chat.append(author,"hello",str(i).sha256_text().left(32),1,0).ok,"Burst accepted")
	check(not chat.append(author,"spam","z".repeat(32),1,0).ok,"Invalid nonce rejected")
	check(not chat.append(author,"spam","a".repeat(32),1,0).ok,"Rate limit")
	check(chat.append(author,"duplicate",str(0).sha256_text().left(32),1,0).duplicate,"Nonce deduplicated")
	check(chat.history().messages.size()==4,"Duplicate no append")
	check(not chat.append(author,"stale","b".repeat(32),0,10001).ok,"Old generation rejected")
	for i in range(80): check(chat.append(author,"🙂".repeat(250),str(i+10).sha256_text().left(32),1,(i+1)*10001).ok,"History fill")
	var history=chat.history()
	check(history.messages.size()<=64 and JSON.stringify(history.messages).to_utf8_buffer().size()<=65536,"Both history caps")
	check(Chat.valid_history(history),"History wire validation")
	history.messages[0].text="mutated"
	check(chat.history().messages[0].text!="mutated","History copy")
	chat.reset(1)
	for author_index in range(8):
		for i in range(4): check(chat.append({"id":"p"+str(author_index),"name":"Player "+str(author_index),"role":"player"},"Global",str(author_index*4+i).sha256_text().left(32),1,0).ok,"Global burst")
	check(not chat.append({"id":"p9","name":"Player 9","role":"player"},"Global flood","a".repeat(32),1,0).ok,"Global32 limit")
	check(chat.append({"id":"p9","name":"Player 9","role":"player"},"Recovered","a".repeat(32),1,10000).ok,"Global time refill")
	chat.reset(2)
	check(chat.history().messages.is_empty() and chat.history().generation==2,"Generation clears history")
	print("network_chat19: %d failures"%failures)
	quit(1 if failures else 0)
