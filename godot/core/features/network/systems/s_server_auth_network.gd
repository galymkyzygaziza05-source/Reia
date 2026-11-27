class_name ServerAuthNetworkSystem extends System
## Creates a player only after the Rust QUIC layer has verified Firebase identity.
## The payload received here is rewritten by the trusted Rust server; client-supplied
## role/email fields are never accepted from online connections.

var writer := StreamPeerBuffer.new()

func query() -> QueryBuilder:
	process_empty = true
	return super.query()

func process(_entities: Array[Entity], _components: Array, _delta: float) -> void:
	var auth_request_bucket := NetworkRouter.server.consume_bucket(OpCode.ID.AUTH_REQUEST)
	if not auth_request_bucket.is_empty():
		_process_auth(auth_request_bucket)

func _process_auth(bucket: Dictionary) -> void:
	var ids: PackedInt64Array = bucket["ids"]
	var offsets: PackedInt32Array = bucket["offsets"]
	var data: PackedByteArray = bucket["data"]
	var newly_joined_clients: Array[Dictionary] = []

	for i in range(ids.size()):
		var net_id: int = ids[i]
		var start: int = offsets[i]
		var finish: int = offsets[i + 1] if i + 1 < offsets.size() else data.size()
		var payload_text := data.slice(start, finish).get_string_from_utf8()
		var auth_data: Variant = JSON.parse_string(payload_text)
		if not auth_data is Dictionary:
			push_warning("[SERVER] Ignored malformed authentication payload for client %d." % net_id)
			continue

		var username := String(auth_data.get("username", "Adventurer")).strip_edges()
		var uid := String(auth_data.get("uid", "")).strip_edges()
		var email := String(auth_data.get("email", "")).strip_edges().to_lower()
		var email_verified := bool(auth_data.get("email_verified", false))
		var is_admin := bool(auth_data.get("is_admin", false))

		# Online identities must contain a verified Firebase UID and email.
		# Offline identities are explicitly local and can never be administrators.
		var is_offline_identity := uid == "offline-local"
		if not is_offline_identity and (uid.is_empty() or email.is_empty() or not email_verified):
			push_warning("[SERVER] Rejected incomplete verified identity for client %d." % net_id)
			continue
		if is_offline_identity:
			is_admin = false
		if username.is_empty():
			username = "Adventurer"
		username = username.substr(0, 24)

		# Do not create duplicate player entities if a packet is repeated.
		if EntityMap.server.get_entity(net_id):
			continue

		var player := Entity.new()
		var body := CharacterBody3D.new()
		var col := CollisionShape3D.new()
		col.shape = CapsuleShape3D.new()
		body.add_child(col)

		player.add_component(C_NetworkId.new(net_id))
		player.add_component(C_Transform.new(Transform3D(Basis(), Vector3(0, 5, 0))))
		player.add_component(C_Velocity.new())
		player.add_component(C_MoveInput.new())
		player.add_component(C_CharacterBody3D.new(body))
		player.add_component(C_PlayerTag.new())
		player.add_component(C_Username.new(username))
		player.set_meta("firebase_uid", uid)
		player.set_meta("verified_email", email)
		player.set_meta("is_admin", is_admin)
		player.add_child(body)
		cmd.add_entity(player)

		newly_joined_clients.append({
			"net_id": net_id,
			"username": username,
			"is_admin": is_admin
		})

	if newly_joined_clients.is_empty():
		return

	cmd.execute()
	var all_clients := EntityMap.server.get_all_active_clients()
	for client: Dictionary in newly_joined_clients:
		var net_id: int = client["net_id"]
		var username: String = client["username"]
		var is_admin: bool = client["is_admin"]

		writer.clear()
		writer.put_64(net_id)
		writer.put_u32(Zone.ID.WATERBROOK)
		writer.put_u8(1 if is_admin else 0)
		NetworkRouter.server.queue_packet(net_id, OpCode.ID.AUTH_SUCCESS, writer.data_array)

		_send_existing_entities_to_client(net_id)

		writer.clear()
		writer.put_64(net_id)
		writer.put_string("PLAYER")
		writer.put_string(username)
		writer.put_float(0.0)
		writer.put_float(5.0)
		writer.put_float(0.0)
		NetworkRouter.server.queue_broadcast(all_clients, OpCode.ID.ENTITY_SPAWN, writer.data_array)

func _send_existing_entities_to_client(new_client_id: int) -> void:
	for existing_net_id: int in EntityMap.server._net_id_to_entity.keys():
		if existing_net_id == new_client_id:
			continue
		var existing_entity := EntityMap.server.get_entity(existing_net_id)
		if not existing_entity:
			continue

		var username_comp := existing_entity.get_component(C_Username) as C_Username
		var entity_name := username_comp.username if username_comp else "Entity"
		var trans_comp := existing_entity.get_component(C_Transform) as C_Transform
		var pos := trans_comp.transform.origin if trans_comp else Vector3.ZERO

		writer.clear()
		writer.put_64(existing_net_id)
		writer.put_string("PLAYER")
		writer.put_string(entity_name)
		writer.put_float(pos.x)
		writer.put_float(pos.y)
		writer.put_float(pos.z)
		NetworkRouter.server.queue_packet(new_client_id, OpCode.ID.ENTITY_SPAWN, writer.data_array)
