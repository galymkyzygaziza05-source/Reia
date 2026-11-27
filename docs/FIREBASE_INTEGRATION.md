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

The authentication foundation is implemented on the working branch, but it is not ready for public release until the required Firebase and TLS configuration is applied and end-to-end tests pass.

Production requirements:

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
- [x] Implement a trusted server-side Firebase token verification handshake in the adaptation branch; run end-to-end tests before release.
- [ ] Add Firestore collections and restrictive Security Rules only after the data model is implemented.
- [x] Add the initial admin-only dashboard with online status, announcements and kick.
- [ ] Expand moderation, audit history, persistent bans and server configuration controls.



## Implemented in the Reia adaptation branch

The following authentication foundation is now present in the working branch:

- Godot client email/password sign-in and account registration use Firebase Authentication REST endpoints.
- New accounts receive an email-verification message; online sign-in is refused until Firebase reports `emailVerified=true`.
- The Firebase ID token is kept in memory and sent in a reliable QUIC unidirectional stream, not a lossy gameplay datagram.
- The Rust server verifies the token through Firebase Identity Toolkit `accounts:lookup` before marking a connection authenticated.
- Gameplay datagrams are ignored until the connection passes Firebase verification.
- The trusted server derives UID, verified email, and administrator status. The only administrator allowlist entry is `llisteenn@gmail.com`.
- Godot creates a player only from the trusted identity payload. The first-join training dummy has been removed.
- The server includes the administrator bit in the authentication-success response; the client opens the dashboard only after that server-approved claim.
- The first admin dashboard supports online-player status, server-wide announcements, and kicking a selected non-admin player. Rust drops administrator commands from every non-admin connection before they reach Godot; kick requests are converted to a server-side QUIC connection close.
- The online game server address, UDP port and TLS DNS name are configurable through Godot Project Settings.

## Required configuration before running online

1. Enable **Email/Password** in Firebase Authentication.
2. Enable email verification in the account workflow and ensure Firebase email templates are configured.
3. The selected Firebase Web API key is already populated in `godot/project.godot` under `reia/firebase_web_api_key`. This is a public Firebase client identifier, not a service-account credential.
4. On the trusted game server, set:
   - `FIREBASE_PROJECT_ID=gen-lang-client-0722704032`
   - `FIREBASE_WEB_API_KEY=<the same Firebase Web API key>`
5. Set `REIA_TLS_CERT_PATH` and `REIA_TLS_KEY_PATH` on the game server to the full-chain PEM certificate and matching private key. Set Godot `reia/server_tls_name` to the certificate DNS name; set `reia/server_address` to the server IP and `reia/server_port` to its UDP port.
6. Never put a Firebase service-account JSON file or Admin SDK private key in the client or Git repository.

## Important production security blocker

Release QUIC clients validate server certificates against trusted public roots and check a configurable DNS name. Debug builds permit the generated self-signed certificate only when connecting to `localhost` over a loopback address. The server loads its production certificate chain and private key from `REIA_TLS_CERT_PATH` and `REIA_TLS_KEY_PATH`. **Before public use, configure a valid certificate chain for the server domain and set Godot `reia/server_tls_name` to that exact domain.**

## Still not implemented

- Persistent bans, audit logs, server configuration controls, and moderation history.
- Firebase token revocation checks and refresh-token/session renewal.
- Persistent player profiles, account linking, and password reset UI.
- Firestore schema and Security Rules.
- Provisioning and configuring a valid production QUIC certificate for the actual server domain.
- End-to-end Godot export/runtime verification. Rust CI and Godot parsing/build checks must pass before this branch is considered complete.

## Current implementation status

Firebase email/password account creation, email verification, client sign-in, reliable token transport, server-side token lookup, pre-authentication gameplay gating, and server-derived administrator identity are implemented in this working branch. The basic admin dashboard is implemented; advanced moderation, audit logs, persistent bans, Firestore, persistent profiles, token revocation checks, background refresh for long-running sessions, and production QUIC certificate provisioning and runtime validation remain outstanding. The branch must pass CI and runtime testing before merge or release.
