use reqwest::Client;
use serde_json::{json, Value};

const EXPECTED_PROJECT_ID: &str = "gen-lang-client-0722704032";

#[derive(Debug, Clone)]
pub struct VerifiedFirebaseUser {
    pub uid: String,
    pub email: String,
    pub username: String,
    pub is_admin: bool,
}

/// Verify a Firebase ID token through Google's Identity Toolkit endpoint.
/// The API key is public Firebase client configuration, but is supplied through
/// server environment so this verifier is bound to the intended Firebase project.
pub async fn verify_auth_payload(
    payload: &[u8],
) -> Result<(VerifiedFirebaseUser, Vec<u8>), String> {
    if payload.len() > 12 * 1024 {
        return Err("Authentication payload is too large".to_string());
    }

    let request: Value = serde_json::from_slice(payload)
        .map_err(|_| "Malformed authentication request".to_string())?;
    let token = request
        .get("idToken")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| "Missing Firebase ID token".to_string())?;

    let requested_name = request
        .get("username")
        .and_then(Value::as_str)
        .unwrap_or("Adventurer")
        .trim();
    let username = if requested_name.is_empty() {
        "Adventurer"
    } else {
        requested_name
    };
    let username: String = username
        .chars()
        .filter(|character| !character.is_control())
        .take(24)
        .collect();
    let username = if username.trim().is_empty() {
        "Adventurer".to_string()
    } else {
        username
    };

    let project_id = std::env::var("FIREBASE_PROJECT_ID")
        .map_err(|_| "Server Firebase project is not configured".to_string())?;
    if project_id != EXPECTED_PROJECT_ID {
        return Err("Server Firebase project does not match this Reia build".to_string());
    }
    let api_key = std::env::var("FIREBASE_WEB_API_KEY")
        .map_err(|_| "Server Firebase API key is not configured".to_string())?;

    let response = Client::new()
        .post("https://identitytoolkit.googleapis.com/v1/accounts:lookup")
        .query(&[("key", api_key.as_str())])
        .json(&json!({ "idToken": token }))
        .send()
        .await
        .map_err(|_| "Could not reach Firebase Authentication".to_string())?;

    if !response.status().is_success() {
        return Err("Firebase rejected the sign-in token".to_string());
    }

    let body: Value = response
        .json()
        .await
        .map_err(|_| "Firebase returned an invalid verification response".to_string())?;
    let user = body
        .get("users")
        .and_then(Value::as_array)
        .and_then(|users| users.first())
        .ok_or_else(|| "Firebase token has no user record".to_string())?;

    let uid = user
        .get("localId")
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| "Firebase user ID is missing".to_string())?
        .to_string();
    let email = user
        .get("email")
        .and_then(Value::as_str)
        .ok_or_else(|| "Firebase account must have an email address".to_string())?
        .trim()
        .to_ascii_lowercase();
    let email_verified = user
        .get("emailVerified")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    if !email_verified {
        return Err("Verify your email address before entering Reia".to_string());
    }

    let is_admin = email == "llisteenn@gmail.com";
    let verified = VerifiedFirebaseUser {
        uid: uid.clone(),
        email: email.clone(),
        username: username.clone(),
        is_admin,
    };
    let trusted_payload = serde_json::to_vec(&json!({
        "uid": uid,
        "email": email,
        "email_verified": true,
        "username": username,
        "is_admin": is_admin
    }))
    .map_err(|_| "Could not create trusted authentication context".to_string())?;

    Ok((verified, trusted_payload))
}
