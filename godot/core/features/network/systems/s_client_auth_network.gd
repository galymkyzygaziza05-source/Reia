class_name ClientAuthNetworkSystem extends System
## Listens for AUTH_SUCCESS, stores the local ID, and fires the login UI event

var reader := StreamPeerBuffer.new()

func query() -> QueryBuilder:
	process_empty = true
	return super.query()

func process(_entities: Array[Entity], _components: Array, _delta: float) -> void:
	var auth_failed_bucket := NetworkRouter.client.consume_bucket(OpCode.ID.AUTH_FAILED)
	if not auth_failed_bucket.is_empty():
		_process_auth_failed(auth_failed_bucket)
	var auth_success_bucket := NetworkRouter.client.consume_bucket(OpCode.ID.AUTH_SUCCESS)
	if not auth_success_bucket.is_empty():
		_process_auth_success(auth_success_bucket)

func _process_auth_success(bucket: Dictionary) -> void:
	var ids: PackedInt64Array = bucket["ids"]
	var offsets: PackedInt32Array = bucket["offsets"]
	reader.data_array = bucket["data"]

	for i in range(ids.size()):
		reader.seek(offsets[i])
		var my_net_id := reader.get_64()
		var zone_id := reader.get_u32()
		var is_admin := reader.get_u8() == 1
		FirebaseAuth.is_admin = is_admin

		# Store who WE are so the Spawner System knows which mesh gets the camera
		GameOrchestrator.local_client_net_id = my_net_id

		# Fire to the UI to drop the TitleScreen and load the map
		UIEventBus.auth.login_success.emit(zone_id)
		if is_admin:
			UIEventBus.auth.admin_access_granted.emit()
		break # Only process Auth once per client

func _process_auth_failed(bucket: Dictionary) -> void:
	var data: PackedByteArray = bucket["data"]
	var offsets: PackedInt32Array = bucket["offsets"]
	if offsets.is_empty():
		return
	var start: int = offsets[0]
	var reason := data.slice(start, data.size()).get_string_from_utf8()
	FirebaseAuth.sign_out()
	UIModalManager.show_notification("Authentication failed", reason)
	SceneManager.transition_to_screen(Scenes.Menus.TITLE_SCREEN)
