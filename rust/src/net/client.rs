use crate::net::error::NetworkInitError;
use crate::net::op_codes::OpCode;
use crate::net::packets::{IncomingPacket, LifecycleEvent, OutgoingPacket};
use flume::{Receiver, Sender};
use quinn::{ClientConfig, Endpoint, TransportConfig};
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::Duration;
use tokio::io::AsyncWriteExt;

pub async fn start_quinn_client(
    ip: String,
    server_name: String,
    port: u16,
    tx_in: Sender<IncomingPacket>,
    rx_out: Receiver<OutgoingPacket>,
    tx_life: Sender<LifecycleEvent>,
) -> Result<(), NetworkInitError> {
    let _ = rustls::crypto::ring::default_provider().install_default();

    // Validate the server certificate against trusted public roots.
    // Keep the DNS certificate name separate from the socket address.
    let root_store = rustls::RootCertStore::from_iter(
        webpki_roots::TLS_SERVER_ROOTS.iter().cloned()
    );
    let mut crypto = rustls::ClientConfig::builder()
        .with_root_certificates(root_store)
        .with_no_client_auth();
    crypto.alpn_protocols = vec![b"mmo-proto".to_vec()];

    // Explicitly configure transport settings to prevent drops during Godot Scene Loads
    let mut transport_config = TransportConfig::default();
    transport_config.max_idle_timeout(Some(Duration::from_secs(30).try_into().unwrap()));
    transport_config.keep_alive_interval(Some(Duration::from_secs(5)));
    transport_config.datagram_receive_buffer_size(Some(usize::MAX));
    let transport_config = Arc::new(transport_config);

    // Quinn requires wrapping the rustls config in `QuicClientConfig`
    let quic_config = quinn::crypto::rustls::QuicClientConfig::try_from(crypto)
        .map_err(|e| NetworkInitError::TlsConfigFailed(e.to_string()))?;
    let mut client_config = ClientConfig::new(Arc::new(quic_config));
    client_config.transport_config(transport_config);

    // Bind to a random local port (0.0.0.0:0) and connect
    let mut endpoint =
        Endpoint::client("0.0.0.0:0".parse().expect("hardcoded address")).map_err(|e| {
            NetworkInitError::BindFailed {
                port: 0,
                reason: e.to_string(),
            }
        })?;
    endpoint.set_default_client_config(client_config);

    let addr_string = format!("{}:{}", ip, port);
    let server_addr: SocketAddr = addr_string
        .parse()
        .map_err(|_| NetworkInitError::InvalidAddress(addr_string))?;

    let mut retries = 0;
    let max_retries = 5;

    // "localhost" here matches the dummy cert generated on the server
    loop {
        match endpoint
            .connect(server_addr, "localhost")
            .map_err(|e| NetworkInitError::ConnectionFailed(e.to_string()))?
            .await
        {
            Ok(connection) => {
                tracing::info!("Connected to Server: {}", server_addr);
                let _ = tx_life.send_async(LifecycleEvent::ClientConnected).await;

                // Spawn a task to READ incoming datagrams from Server
                let conn_read = connection.clone();
                let tx_life_clone = tx_life.clone();
                let tx_in_clone = tx_in.clone();

                tokio::spawn(async move {
                    loop {
                        match conn_read.read_datagram().await {
                            Ok(bytes) => {
                                if bytes.len() < 2 {
                                    continue;
                                }

                                let op_code_raw = u16::from_le_bytes([bytes[0], bytes[1]]);

                                // Validate against our generated registry
                                if let Ok(_valid_op) = OpCode::try_from(op_code_raw) {
                                    let packet = IncomingPacket {
                                        client_id: 0, // 0 signifies the Server
                                        op_code: op_code_raw,
                                        payload: bytes[2..].to_vec(),
                                    };
                                    let _ = tx_in_clone.send_async(packet).await;
                                } else {
                                    tracing::warn!("Server sent unknown OpCode: {}", op_code_raw);
                                }
                            }
                            Err(e) => {
                                tracing::warn!("Read connection lost: {}", e);
                                // Send clean, user-friendly error to Godot
                                let _ = tx_life_clone
                                    .send_async(LifecycleEvent::ClientDisconnected(
                                        "Connection to the server was lost.".to_string(),
                                    ))
                                    .await;
                                break;
                            } // Disconnected
                        }
                    }
                });

                // Loop to WRITE outgoing datagrams to Server
                while let Ok(outgoing) = rx_out.recv_async().await {
                    // Pack the 2-byte OpCode and the Godot Payload into a single network buffer
                    let mut buffer = Vec::with_capacity(2 + outgoing.payload.len());
                    buffer.extend_from_slice(&outgoing.op_code.to_le_bytes());
                    buffer.extend_from_slice(&outgoing.payload);

                    if outgoing.op_code == OpCode::AuthRequest as u16 {
                        // Firebase ID tokens are sent on a reliable QUIC stream,
                        // never in lossy movement datagrams.
                        match connection.open_uni().await {
                            Ok(mut stream) => {
                                if let Err(error) = stream.write_all(&buffer).await {
                                    tracing::error!("Failed to write authentication stream: {}", error);
                                    let _ = tx_life.send_async(LifecycleEvent::ClientDisconnected(
                                        "Could not send authentication request.".to_string()
                                    )).await;
                                    break;
                                }
                                if let Err(error) = stream.finish() {
                                    tracing::error!("Failed to finish authentication stream: {}", error);
                                    break;
                                }
                            }
                            Err(error) => {
                                tracing::error!("Could not open authentication stream: {}", error);
                                let _ = tx_life.send_async(LifecycleEvent::ClientDisconnected(
                                    "Could not open authentication channel.".to_string()
                                )).await;
                                break;
                            }
                        }
                    } else if connection.send_datagram(buffer.into()).is_err() {
                        tracing::error!("Failed to send datagram to server. Connection lost.");
                        let _ = tx_life
                            .send_async(LifecycleEvent::ClientDisconnected(
                                "Connection to the server was lost.".to_string(),
                            ))
                            .await;
                        break;
                    }
                }

                // If rx_out closes, Godot has shut down the client. Break out of retry loop.
                break;
            }
            Err(e) => {
                // Log the raw, complex crypto/timeout errors to the Rust console for developers
                tracing::warn!("Connection attempt {} failed: {}", retries + 1, e);

                if retries >= max_retries {
                    tracing::error!("All retries failed. Giving up.");

                    // Send a sanitized, friendly string to the Godot UI!
                    let _ = tx_life.send_async(
                        LifecycleEvent::ClientDisconnected(
                            "Unable to reach the server. Please check your connection and try again.".to_string()
                        )
                    ).await;
                    break;
                }

                // Exponential backoff: 1s, 2s, 4s, 8s, 16s
                let backoff = 1 << retries;
                tokio::time::sleep(std::time::Duration::from_secs(backoff)).await;
                retries += 1;
            }
        }
    }

    Ok(())
}
