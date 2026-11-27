class_name ServerAdminNetworkSystem extends System
## Handles management commands only after the Rust transport has authorized the admin session.

func query() -> QueryBuilder:
	process_empty = true
	return super.query()

func process(_entities: Array[Entity], _components: Array, _delta: float) -> void:
	var bucket := NetworkRouter.server.consume_bucket(OpCode.ID.ADMIN_COMMAND)
	if not bucket.is_empty():
		_process_commands(bucket)

func _process_commands(bucket: Dictionary) -> void:
	var ids: PackedInt64Array = bucket["ids"]
	var offsets: PackedInt32Array = bucket["offsets"]
	var data: PackedByteArray = bucket["data"]

	for i in range(ids.size()):
		var client_id: int = ids[i]
		var admin_entity := EntityMap.server.get_entity(client_id)
		if not admin_entity or not bool(admin_entity.get_meta("is_admin", false)):
			continue

		var start: int = offsets[i]
		var finish: int = offsets[i + 1] if i + 1 < offsets.size() else data.size()
		var request: Variant = JSON.parse_string(data.slice(start, finish).get_string_from_utf8())
		if not request is Dictionary:
			_send_error(client_id, "Malformed administrator request.")
			continue

		match String(request.get("action", "")):
			"status":
				_send_status(client_id)
			"announce":
				_broadcast_announcement(client_id, String(request.get("message", "")))
			_:
				_send_error(client_id, "Unknown administrator action.")

func _send_status(client_id: int) -> void:
	var players: Array[Dictionary] = []
	for player_id: int in EntityMap.server._net_id_to_entity.keys():
		var player := EntityMap.server.get_entity(player_id)
		if not player or not player.get_component(C_PlayerTag):
			continue
		var username_comp := player.get_component(C_Username) as C_Username
		players.append({
			"id": player_id,
			"username": username_comp.username if username_comp else "Adventurer",
			"email": String(player.get_meta("verified_email", "")),
			"is_admin": bool(player.get_meta("is_admin", false))
		})

	var payload := JSON.stringify({"type": "status", "players": players}).to_utf8_buffer()
	NetworkRouter.server.queue_packet(client_id, OpCode.ID.ADMIN_RESPONSE, payload)

func _broadcast_announcement(client_id: int, raw_message: String) -> void:
	var message := raw_message.strip_edges()
	if message.is_empty():
		_send_error(client_id, "Announcement cannot be empty.")
		return
	message = message.substr(0, 240)
	var payload := JSON.stringify({
		"type": "announcement",
		"message": message
	}).to_utf8_buffer()
	var clients := EntityMap.server.get_all_active_clients()
	NetworkRouter.server.queue_broadcast(clients, OpCode.ID.ADMIN_RESPONSE, payload)

func _send_error(client_id: int, message: String) -> void:
	var payload := JSON.stringify({
		"type": "error",
		"message": message
	}).to_utf8_buffer()
	NetworkRouter.server.queue_packet(client_id, OpCode.ID.ADMIN_RESPONSE, payload)
