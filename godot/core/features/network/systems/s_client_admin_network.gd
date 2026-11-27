class_name ClientAdminNetworkSystem extends System
## Receives server responses for the verified administrator dashboard.

func query() -> QueryBuilder:
	process_empty = true
	return super.query()

func process(_entities: Array[Entity], _components: Array, _delta: float) -> void:
	var bucket := NetworkRouter.client.consume_bucket(OpCode.ID.ADMIN_RESPONSE)
	if bucket.is_empty():
		return

	var offsets: PackedInt32Array = bucket["offsets"]
	var data: PackedByteArray = bucket["data"]
	for i in range(offsets.size()):
		var start: int = offsets[i]
		var finish: int = offsets[i + 1] if i + 1 < offsets.size() else data.size()
		var response: Variant = JSON.parse_string(data.slice(start, finish).get_string_from_utf8())
		if not response is Dictionary:
			continue
		match String(response.get("type", "")):
			"status":
				UIEventBus.admin.status_received.emit(response.get("players", []))
			"announcement":
				UIEventBus.admin.announcement_received.emit(String(response.get("message", "")))
			"error":
				UIEventBus.admin.error_received.emit(String(response.get("message", "Administrator request failed.")))
			"success":
				UIEventBus.admin.success_received.emit(String(response.get("message", "Administrator command completed.")))
