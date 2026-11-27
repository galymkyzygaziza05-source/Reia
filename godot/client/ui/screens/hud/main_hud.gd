class_name MainHUD extends Control

@onready var chat_box: ChatBox = $BottomLeftAnchor/ChatBox
@onready var health_bar: PlayerHealthBar = $BottomCenterAnchor/PlayerHealthBar
@onready var interaction_prompt: InteractionPrompt = $CenterAnchor/InteractionPrompt
@onready var admin_button: Button = %AdminButton
@onready var admin_panel: PanelContainer = %AdminPanel
@onready var admin_status: Label = %AdminStatus
@onready var admin_announcement: LineEdit = %AdminAnnouncement
@onready var admin_kick_id: LineEdit = %AdminKickId
@onready var admin_kick_button: Button = %AdminKick
@onready var admin_refresh: Button = %AdminRefresh
@onready var admin_send: Button = %AdminSend
@onready var admin_close: Button = %AdminClose

func _ready() -> void:
	admin_button.visible = FirebaseAuth.is_admin
	admin_panel.hide()
	admin_button.pressed.connect(_on_admin_button_pressed)
	admin_refresh.pressed.connect(_request_admin_status)
	admin_send.pressed.connect(_send_announcement)
	admin_kick_button.pressed.connect(_kick_player)
	admin_close.pressed.connect(func() -> void: admin_panel.hide())
	UIEventBus.admin.status_received.connect(_on_admin_status_received)
	UIEventBus.admin.announcement_received.connect(_on_admin_announcement_received)
	UIEventBus.admin.error_received.connect(_on_admin_error_received)
	UIEventBus.admin.success_received.connect(_on_admin_success_received)

func _on_admin_button_pressed() -> void:
	if not FirebaseAuth.is_admin:
		return
	admin_panel.show()
	_request_admin_status()

func _request_admin_status() -> void:
	_send_admin_command({"action": "status"})

func _send_announcement() -> void:
	var message := admin_announcement.text.strip_edges()
	if message.is_empty():
		return
	_send_admin_command({"action": "announce", "message": message})
	admin_announcement.clear()

func _kick_player() -> void:
	var target_id := admin_kick_id.text.strip_edges().to_int()
	if target_id < 0:
		UIModalManager.show_notification("ADMIN PANEL", "Enter the player ID shown in the online list.")
		return
	_send_admin_command({"action": "kick", "target_id": target_id})
	admin_kick_id.clear()

func _send_admin_command(command: Dictionary) -> void:
	if not FirebaseAuth.is_admin:
		return
	NetworkRouter.client.queue_packet(
		0,
		OpCode.ID.ADMIN_COMMAND,
		JSON.stringify(command).to_utf8_buffer()
	)

func _on_admin_status_received(players: Array) -> void:
	var lines := ["ONLINE PLAYERS: %d" % players.size()]
	for player: Dictionary in players:
		var role := " [ADMIN]" if bool(player.get("is_admin", false)) else ""
		lines.append("#%d  %s%s" % [int(player.get("id", -1)), String(player.get("username", "Adventurer")), role])
	admin_status.text = "\n".join(lines)

func _on_admin_announcement_received(message: String) -> void:
	UIModalManager.show_notification("REIA ANNOUNCEMENT", message)

func _on_admin_error_received(message: String) -> void:
	UIModalManager.show_notification("ADMIN PANEL", message)

func _on_admin_success_received(message: String) -> void:
	UIModalManager.show_notification("ADMIN PANEL", message)
