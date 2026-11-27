extends Node
## Firebase Email/Password authentication for the Reia client.
## ID and refresh tokens remain in memory and are sent only to the trusted game server.

var id_token: String = ""
var refresh_token: String = ""
var email: String = ""
var uid: String = ""
var is_admin: bool = false
var token_expires_at: int = 0
var _http: HTTPRequest
var _busy := false

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)

func sign_in(user_email: String, password: String) -> Dictionary:
	id_token = ""
	refresh_token = ""
	email = ""
	uid = ""
	token_expires_at = 0
	is_admin = false
	if _busy:
		return {"ok": false, "message": "An authentication request is already running."}
	var normalized_email := user_email.strip_edges().to_lower()
	if not _valid_credentials(normalized_email, password):
		return {"ok": false, "message": "Enter a valid email address and a password of at least 6 characters."}
	var api_key := _api_key()
	if api_key.is_empty():
		return {"ok": false, "message": "Firebase API key is not configured in Project Settings."}

	_busy = true
	var result := await _post(
		"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=" + api_key,
		{"email": normalized_email, "password": password, "returnSecureToken": true}
	)
	_busy = false
	if not result.ok:
		return result

	var token := String(result.data.get("idToken", ""))
	if token.is_empty():
		return {"ok": false, "message": "Firebase did not return an ID token."}

	_busy = true
	var lookup := await _post(
		"https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=" + api_key,
		{"idToken": token}
	)
	_busy = false
	if not lookup.ok:
		return lookup
	var users: Array = lookup.data.get("users", [])
	if users.is_empty() or not bool(users[0].get("emailVerified", false)):
		return {"ok": false, "message": "Verify your email address using the link sent by Firebase, then sign in again."}

	id_token = token
	refresh_token = String(result.data.get("refreshToken", ""))
	email = normalized_email
	uid = String(result.data.get("localId", ""))
	token_expires_at = int(Time.get_unix_time_from_system()) + int(result.data.get("expiresIn", "3600"))
	return {"ok": true, "message": "Signed in successfully."}

func register(user_email: String, password: String) -> Dictionary:
	if _busy:
		return {"ok": false, "message": "An authentication request is already running."}
	var normalized_email := user_email.strip_edges().to_lower()
	if not _valid_credentials(normalized_email, password):
		return {"ok": false, "message": "Enter a valid email address and a password of at least 6 characters."}
	var api_key := _api_key()
	if api_key.is_empty():
		return {"ok": false, "message": "Firebase API key is not configured in Project Settings."}

	_busy = true
	var created := await _post(
		"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" + api_key,
		{"email": normalized_email, "password": password, "returnSecureToken": true}
	)
	if not created.ok:
		_busy = false
		return created

	var token := String(created.data.get("idToken", ""))
	var verification := await _post(
		"https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=" + api_key,
		{"requestType": "VERIFY_EMAIL", "idToken": token}
	)
	_busy = false
	if not verification.ok:
		return verification
	return {"ok": true, "message": "Account created. Check your email and confirm the verification link before signing in."}

func send_password_reset(user_email: String) -> Dictionary:
	if _busy:
		return {"ok": false, "message": "An authentication request is already running."}
	var normalized_email := user_email.strip_edges().to_lower()
	if not normalized_email.contains("@") or not normalized_email.contains("."):
		return {"ok": false, "message": "Enter your account email address first."}
	var api_key := _api_key()
	if api_key.is_empty():
		return {"ok": false, "message": "Firebase API key is not configured in Project Settings."}
	_busy = true
	var result := await _post(
		"https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=" + api_key,
		{"requestType": "PASSWORD_RESET", "email": normalized_email}
	)
	_busy = false
	if not result.ok:
		return result
	return {"ok": true, "message": "If this account exists, Firebase has sent a password reset email."}

func ensure_valid_token() -> bool:
	if id_token.is_empty():
		return false
	var now := int(Time.get_unix_time_from_system())
	if token_expires_at > now + 300:
		return true
	if refresh_token.is_empty() or _busy:
		sign_out()
		return false

	_busy = true
	var headers := PackedStringArray(["Content-Type: application/x-www-form-urlencoded"])
	var body := "grant_type=refresh_token&refresh_token=" + refresh_token.uri_encode()
	var error := _http.request(
		"https://securetoken.googleapis.com/v1/token?key=" + _api_key(),
		headers,
		HTTPClient.METHOD_POST,
		body
	)
	if error != OK:
		_busy = false
		sign_out()
		return false
	var response: Array = await _http.request_completed
	_busy = false
	var response_code: int = response[1]
	var parsed: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	if response_code < 200 or response_code >= 300 or not parsed is Dictionary:
		sign_out()
		return false
	id_token = String(parsed.get("id_token", ""))
	refresh_token = String(parsed.get("refresh_token", refresh_token))
	uid = String(parsed.get("user_id", uid))
	token_expires_at = now + int(parsed.get("expires_in", "3600"))
	if id_token.is_empty():
		sign_out()
		return false
	return true

func sign_out() -> void:
	id_token = ""
	refresh_token = ""
	email = ""
	uid = ""
	is_admin = false
	token_expires_at = 0

func _api_key() -> String:
	return String(ProjectSettings.get_setting("reia/firebase_web_api_key", "")).strip_edges()

func _valid_credentials(user_email: String, password: String) -> bool:
	return user_email.contains("@") and user_email.contains(".") and password.length() >= 6

func _post(url: String, payload: Dictionary) -> Dictionary:
	var headers := PackedStringArray(["Content-Type: application/json"])
	var error := _http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		return {"ok": false, "message": "Could not start the Firebase request (error %d)." % error}
	var response: Array = await _http.request_completed
	var response_code: int = response[1]
	var body: PackedByteArray = response[3]
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if response_code < 200 or response_code >= 300:
		var message := "Firebase authentication failed."
		if parsed is Dictionary:
			var error_data: Dictionary = parsed.get("error", {})
			message = String(error_data.get("message", message)).replace("_", " ").capitalize()
		return {"ok": false, "message": message}
	if not parsed is Dictionary:
		return {"ok": false, "message": "Firebase returned an invalid response."}
	return {"ok": true, "data": parsed}
