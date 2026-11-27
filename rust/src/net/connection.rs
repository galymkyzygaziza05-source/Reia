use crate::net::{
    firebase_auth,
    op_codes::OpCode,
    packets::{IncomingPacket, LifecycleEvent},
};
use dashmap::DashMap;
use flume::Sender;
use quinn::Connection;
use std::sync::Arc;

const MAX_AUTH_FRAME: usize = 16 * 1024;

pub async fn handle_client(
    client_id: i64,
    conn: Connection,
    firebase_api_key: String,
    tx: Sender<IncomingPacket>,
    tx_life: Sender<LifecycleEvent>,
    connections: Arc<DashMap<i64, Connection>>,
) {
    // A QUIC connection is not a game session. It becomes one only after a
    // Firebase ID token has been verified on this trusted server.
    let mut authenticated = false;
    let mut is_admin = false;

    loop {
        tokio::select! {
            datagram = conn.read_datagram(), if authenticated => {
                match datagram {
                    Ok(bytes) => {
                        if bytes.len() < 2 {
                            tracing::warn!("Malformed short datagram from client {}", client_id);
                            continue;
                        }

                        let op_code_raw = u16::from_le_bytes([bytes[0], bytes[1]]);
                        match OpCode::try_from(op_code_raw) {
                            Ok(OpCode::AdminKick) => {
                                tracing::warn!("Client {} attempted to send a server-only admin kick opcode", client_id);
                            }
                            Ok(OpCode::AuthRequest) => {
                                // Authentication is accepted only on reliable QUIC streams.
                                tracing::warn!("Client {} attempted to authenticate over an unreliable datagram", client_id);
                            }
                            Ok(OpCode::AdminCommand) if is_admin => {
                                let packet = IncomingPacket {
                                    client_id,
                                    op_code: op_code_raw,
                                    payload: bytes[2..].to_vec(),
                                };
                                if tx.send_async(packet).await.is_err() {
                                    tracing::error!("Godot packet bridge disconnected for admin client {}", client_id);
                                    break;
                                }
                            }
                            Ok(OpCode::AdminCommand) => {
                                tracing::warn!("Non-admin client {} attempted an administrator command", client_id);
                            }
                            Ok(_) => {
                                let packet = IncomingPacket {
                                    client_id,
                                    op_code: op_code_raw,
                                    payload: bytes[2..].to_vec(),
                                };
                                if tx.send_async(packet).await.is_err() {
                                    tracing::error!("Godot packet bridge disconnected for client {}", client_id);
                                    break;
                                }
                            }
                            Err(_) => tracing::warn!("Client {} sent unknown OpCode: {}", client_id, op_code_raw),
                        }
                    }
                    Err(error) => {
                        tracing::info!("Client {} disconnected: {}", client_id, error);
                        break;
                    }
                }
            }
            stream = conn.accept_uni() => {
                match stream {
                    Ok(mut stream) => {
                        let frame = match stream.read_to_end(MAX_AUTH_FRAME).await {
                            Ok(frame) => frame,
                            Err(error) => {
                                tracing::warn!("Could not read reliable auth frame from {}: {}", client_id, error);
                                continue;
                            }
                        };

                        if frame.len() < 2 {
                            tracing::warn!("Client {} sent a malformed reliable frame", client_id);
                            continue;
                        }

                        let op_code_raw = u16::from_le_bytes([frame[0], frame[1]]);
                        if OpCode::try_from(op_code_raw) != Ok(OpCode::AuthRequest) {
                            tracing::warn!("Client {} sent unsupported reliable OpCode {}", client_id, op_code_raw);
                            continue;
                        }
                        if authenticated {
                            tracing::warn!("Client {} attempted a second authentication", client_id);
                            continue;
                        }

                        match firebase_auth::verify_auth_payload(&frame[2..], &firebase_api_key).await {
                            Ok((identity, trusted_payload)) => {
                                authenticated = true;
                                is_admin = identity.is_admin;
                                tracing::info!(
                                    "Firebase identity verified for client {} (uid={}, admin={})",
                                    client_id,
                                    identity.uid,
                                    identity.is_admin
                                );
                                let packet = IncomingPacket {
                                    client_id,
                                    op_code: op_code_raw,
                                    payload: trusted_payload,
                                };
                                if tx.send_async(packet).await.is_err() {
                                    tracing::error!("Godot packet bridge disconnected for client {}", client_id);
                                    break;
                                }
                            }
                            Err(reason) => {
                                tracing::warn!("Authentication rejected for client {}: {}", client_id, reason);
                                let mut response = Vec::with_capacity(2 + reason.len());
                                response.extend_from_slice(&(OpCode::AuthFailed as u16).to_le_bytes());
                                response.extend_from_slice(reason.as_bytes());
                                if let Err(error) = conn.send_datagram(response.into()) {
                                    tracing::debug!("Could not send auth rejection to client {}: {}", client_id, error);
                                }
                                // Fail closed: no gameplay datagrams are accepted for this connection.
                            }
                        }
                    }
                    Err(error) => {
                        tracing::info!("Client {} reliable stream closed: {}", client_id, error);
                        break;
                    }
                }
            }
        }
    }

    connections.remove(&client_id);
    let _ = tx_life
        .send_async(LifecycleEvent::ServerClientDisconnected(client_id))
        .await;
}
