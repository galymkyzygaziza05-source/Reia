# Reia Firebase integration

## Selected Firebase project

- Project name: Близнецы (default)
- Project ID: `gen-lang-client-0722704032`
- Project number: `351141459593`
- Android application ID: `com.quaintstudios.reia`
- Firebase Android App ID: `1:351141459593:android:0b5c612af49c50f7923858`
- Sole intended administrator email: `llisteenn@gmail.com`

The Android package name was checked against `godot/project.godot` and the project source. Keep it exactly `com.quaintstudios.reia`.

## Security requirements before enabling accounts

The current game protocol sends a placeholder `dummy_token` in `ClientMain.gd`. The current Godot server auth system reads but does not validate that token. Do not treat the current login flow as authenticated or expose administrator actions through it.

A production implementation must:

1. Sign users in with Firebase Authentication and obtain a Firebase ID token.
2. Send that ID token to a trusted server-side verifier over a protected authentication handshake.
3. Verify the token signature, issuer, audience, expiry, and Firebase project ID on the server. Never trust an email or role supplied separately by the game client.
4. Derive the authenticated UID and verified email from the validated token.
5. Grant administrator access only when the verified email exactly matches `llisteenn@gmail.com` (or a server-managed Firebase custom claim assigned only by a trusted Admin SDK process).
6. Reject invalid, expired, revoked, or missing tokens before creating a player entity.
7. Keep service-account credentials and Admin SDK secrets on the server only. Never commit them or include them in the Godot client.
8. Protect Firestore data with Security Rules. A client must never be allowed to write its own admin role.

## Firebase setup checklist

- [ ] Enable Email/Password in Firebase Authentication.
- [ ] Download the Android `google-services.json` for package `com.quaintstudios.reia` if a plugin or Android export workflow requires it. The project currently uses a Godot/Rust architecture; downloading this file alone does not integrate Firebase.
- [ ] Decide and implement the trusted server-side token verification endpoint/handshake.
- [ ] Add Firestore collections and restrictive Security Rules only after the data model is implemented.
- [ ] Add an admin-only panel only after server-verified administrator identity is available.

## Current implementation status

This file records the selected project and security design. It does **not** claim that Firebase Authentication, Firestore, token verification, account registration, or the administrator panel are already implemented. The current placeholder authentication must be replaced before public multiplayer access is considered secure.
