extends Node
## Retain a departing socket briefly so reliable leave survives the owning scene.
var peer:ENetMultiplayerPeer
var deadline:=0
func begin(value:ENetMultiplayerPeer)->void:
	peer=value
	deadline=Time.get_ticks_msec()+300
	peer.host.flush()
func _process(_delta:float)->void:
	if peer==null: queue_free(); return
	if peer.get_connection_status()!=MultiplayerPeer.CONNECTION_DISCONNECTED: peer.poll()
	if peer.get_connection_status()==MultiplayerPeer.CONNECTION_DISCONNECTED or Time.get_ticks_msec()>=deadline:
		peer.close(); peer=null; queue_free()
func _exit_tree()->void:
	if peer!=null: peer.close(); peer=null
