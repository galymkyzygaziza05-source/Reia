class_name ClientMain extends Node

## The Root Node for the Client Presentation Layer.
## Responsible for connecting to the server, registering visual Observers,
## and ticking the Client-side prediction ECS.

var ip: String
var port: int
var is_offline: bool
var rust_core: RustCore

func _init(_ip: String, _port: int, _offline: bool = false) -> void:
	ip = _ip
	port = _port
	is_offline = _offline
	name = "ClientMain"

func _ready() -> void:
	# Create GECS World
	var world := World.new()
	world.name = "ClientWorld"
	GameOrchestrator.client_world = world

	# Builds prediction systems and visual observers instantly
	ClientPipeline.build(world)

	if not is_offline:
		print("[CLIENT] Starting Client Initialization...")

		# Start client
		rust_core = RustCore.new()
		add_child(rust_core)
		UIUtils.safe_connect(rust_core.on_network_events, _on_rust_packets, "ClientMain on_network_events")

		# Bind network lifecycle signals
		UIUtils.safe_connect(rust_core.on_client_connected, _on_network_connected, "ClientMain on_client_connected")
		UIUtils.safe_connect(rust_core.on_client_disconnected, _on_network_disconnected, "ClientMain on_client_disconnected")


		var tls_server_name := String(ProjectSettings.get_setting("reia/server_tls_name", ip)).strip_edges()
		rust_core.start_client(ip, port, tls_server_name)

		print("[CLIENT] Connecting to server at %s:%d..." % [ip, port])
	else:
		print("[CLIENT] Offline mode enabled. Skipping network initialization.")

		# In offline mode, immediately authenticate
		call_deferred("_send_auth_request")

func _on_network_connected() -> void:
	print("[CLIENT] Connection established! Requesting Authentication...")
	_send_auth_request()

func _on_network_disconnected(reason: String) -> void:
	FirebaseAuth.is_admin = false
	print("[CLIENT] Disconnected from server: ", reason)

	# Return the user to the Main Menu and alert them
	SceneManager.transition_to_screen(Scenes.Menus.TITLE_SCREEN)
	UIModalManager.show_notification("Connection Failed", reason)

func _send_auth_request() -> void:
	var auth_payload: Dictionary
	if is_offline:
		# Offline sessions do not cross the network and do not receive admin privileges.
		auth_payload = {
			"username": UserPreferences.get_username(),
			"uid": "offline-local",
			"email": "",
			"email_verified": false,
			"is_admin": false
		}
	else:
		var token := FirebaseAuth.id_token
		if token.is_empty():
			UIModalManager.show_notification("Sign in required", "Sign in with your verified Firebase account before joining online.")
			SceneManager.transition_to_screen(Scenes.Menus.TITLE_SCREEN)
			return
		auth_payload = {
			"username": UserPreferences.get_username(),
			"idToken": token
		}

	# Reliable QUIC transport is selected by the Rust layer for AUTH_REQUEST.
	NetworkRouter.client.queue_packet(0, OpCode.ID.AUTH_REQUEST, JSON.stringify(auth_payload).to_utf8_buffer())
	print("[CLIENT] Sent authentication request. Awaiting server verification...")

func _on_rust_packets(buckets: Dictionary) -> void:
	NetworkRouter.client.incoming_buckets = buckets

func _physics_process(delta: float) -> void:
	# Exact same loop as the server, but Client systems only do
	# prediction, interpolation, and VFX triggering.
	if rust_core: rust_core.poll_network()

	var world := GameOrchestrator.client_world

	if not world:
		return

	world.process(delta, SystemGroups.PRE_PROCESS)

	# Safely flush to the Rust network thread
	NetworkRouter.client.flush_to_rust(rust_core)
	NetworkRouter.client.clear_inbox()
