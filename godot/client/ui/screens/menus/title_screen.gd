class_name TitleScreen extends Control

enum State { MAIN_MENU, PLAY_MENU, INFO_MENU }
var current_state: State = State.MAIN_MENU

@onready var main_menu_container: Control = $ScreenContainer/FlowStates/MainMenu
@onready var play_menu_container: Control = $ScreenContainer/FlowStates/PlayMenu
@onready var info_menu_container: Control = $ScreenContainer/FlowStates/InfoMenu

# Main Menu Buttons
@onready var btn_main_play: Button = %BtnMainPlay
@onready var btn_about: Button = %BtnAbout
@onready var btn_developers: Button = %BtnDevelopers
@onready var btn_settings: Button = %BtnSettings
@onready var btn_quit: Button = %BtnQuit

# Information page
@onready var info_title: Label = %InfoTitle
@onready var info_body: Label = %InfoBody
@onready var btn_info_back: Button = %BtnInfoBack

# Play Menu Elements
@onready var btn_singleplayer: Button = %BtnSingleplayer
@onready var input_username: LineEdit = %InputUsername
@onready var input_password: LineEdit = %InputPassword
@onready var btn_play_online: Button = %BtnPlayOnline
@onready var btn_register: Button = %BtnRegister
@onready var btn_password_reset: Button = %BtnPasswordReset
@onready var btn_host_play: Button = %BtnHostPlay
@onready var btn_host_only: Button = %BtnHostOnly
@onready var btn_back: Button = %BtnBack

func _ready() -> void:
	_switch_to_state(State.MAIN_MENU, false)
	input_username.text = ""

	UIUtils.safe_connect(btn_main_play.pressed, _on_main_play_clicked, "TitleScreen btn_main_play")
	UIUtils.safe_connect(btn_about.pressed, _on_about_clicked, "TitleScreen btn_about")
	UIUtils.safe_connect(btn_developers.pressed, _on_developers_clicked, "TitleScreen btn_developers")
	UIUtils.safe_connect(btn_settings.pressed, _on_settings_clicked, "TitleScreen btn_settings")
	UIUtils.safe_connect(btn_quit.pressed, _on_quit_clicked, "TitleScreen btn_quit")

	UIUtils.safe_connect(btn_singleplayer.pressed, _on_play_solo, "TitleScreen btn_singleplayer")
	UIUtils.safe_connect(btn_play_online.pressed, _on_play_online, "TitleScreen btn_play_online")
	UIUtils.safe_connect(btn_register.pressed, _on_register, "TitleScreen btn_register")
	UIUtils.safe_connect(btn_password_reset.pressed, _on_password_reset, "TitleScreen btn_password_reset")
	UIUtils.safe_connect(btn_host_play.pressed, _on_host_play, "TitleScreen btn_host_play")
	UIUtils.safe_connect(btn_host_only.pressed, _on_host_only, "TitleScreen btn_host_only")
	UIUtils.safe_connect(btn_back.pressed, _on_back_clicked, "TitleScreen btn_back")
	UIUtils.safe_connect(btn_info_back.pressed, _on_back_clicked, "TitleScreen btn_info_back")

func _on_main_play_clicked() -> void:
	_switch_to_state(State.PLAY_MENU)

func _on_about_clicked() -> void:
	_show_info(
		"ABOUT REIA",
		"Reia is an open-source 3D action-adventure RPG set in a fantasy world of mysterious realms. Explore environments, follow the story, fight enemies, discover abilities and shape your own adventure.\n\nThe project is designed to support offline play and online multiplayer experiences. Some systems are still in development, so features and availability may change between builds.\n\nThis is the community adaptation build based on the original Reia project."
	)

func _on_developers_clicked() -> void:
	_show_info(
		"DEVELOPERS & CONTRIBUTORS",
		"ORIGINAL PROJECT\nQuaint Studios — creators and maintainers of the open-source Reia project.\n\nCOMMUNITY ADAPTATION\nDarkhan — developer contributing to this adapted build, its presentation and future improvements.\n\nOriginal project: github.com/Quaint-Studios/Reia"
	)

func _show_info(title_text: String, body_text: String) -> void:
	info_title.text = title_text
	info_body.text = body_text
	_switch_to_state(State.INFO_MENU)

func _on_settings_clicked() -> void:
	UIModalManager.show_notification("Coming Soon!", "The settings feature isn't implemented yet but it will be soon.")

func _on_quit_clicked() -> void:
	UIModalManager.ask_confirmation("Confirmation", "Are you sure you want to close the game?", _execute_quit)

func _execute_quit() -> void:
	get_tree().quit()

func _on_back_clicked() -> void:
	_switch_to_state(State.MAIN_MENU)

func _on_play_solo() -> void:
	_save_username_and_route()
	UIEventBus.session.intent_play_solo.emit()

func _on_play_online() -> void:
	var auth_ok: bool = await _authenticate()
	if not auth_ok:
		return
	_save_username_and_route()
	var target_ip := String(ProjectSettings.get_setting("reia/server_address", "127.0.0.1"))
	var target_port := int(ProjectSettings.get_setting("reia/server_port", 7777))
	UIEventBus.session.intent_play_online.emit(target_ip, target_port)

func _on_register() -> void:
	var result: Dictionary = await FirebaseAuth.register(input_username.text, input_password.text)
	UIModalManager.show_notification("Reia account", String(result.get("message", "Registration failed.")))

func _on_password_reset() -> void:
	var result: Dictionary = await FirebaseAuth.send_password_reset(input_username.text)
	UIModalManager.show_notification("Password reset", String(result.get("message", "Password reset request failed.")))

func _authenticate() -> bool:
	var result: Dictionary = await FirebaseAuth.sign_in(input_username.text, input_password.text)
	if not bool(result.get("ok", false)):
		UIModalManager.show_notification("Sign in required", String(result.get("message", "Authentication failed.")))
		return false
	return true

func _on_host_play() -> void:
	var auth_ok: bool = await _authenticate()
	if not auth_ok:
		return
	_save_username_and_route()
	UIEventBus.session.intent_host_and_play.emit(7777)

func _on_host_only() -> void:
	_save_username_and_route()
	UIEventBus.session.intent_host_only.emit(7777)

func _save_username_and_route() -> void:
	var user := input_username.text.strip_edges()
	if not FirebaseAuth.email.is_empty():
		user = FirebaseAuth.email.get_slice("@", 0)
	elif user.contains("@"):
		user = user.get_slice("@", 0)
	if user.is_empty():
		user = "Adventurer"
	UserPreferences.save_username(user)

func _switch_to_state(new_state: State, animate: bool = true) -> void:
	current_state = new_state
	var containers: Array[Control] = [main_menu_container, play_menu_container, info_menu_container]
	for container in containers:
		if container.visible and animate:
			_fade_out(container)
		else:
			container.hide()

	var target: Control
	match current_state:
		State.MAIN_MENU:
			target = main_menu_container
		State.PLAY_MENU:
			target = play_menu_container
		_:
			target = info_menu_container

	if animate:
		_fade_in(target)
	else:
		target.show()

func _fade_out(node: Control) -> void:
	var tween := create_tween()
	tween.tween_property(node, "modulate:a", 0.0, 0.2)
	tween.tween_callback(node.hide)

func _fade_in(node: Control) -> void:
	node.show()
	node.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(node, "modulate:a", 1.0, 0.2)
