use std::{
    net::{IpAddr, Ipv4Addr, SocketAddr},
    path::PathBuf,
    str::FromStr,
};

use axum::{
    Router,
    body::Body,
    http::{StatusCode, header},
    response::{AppendHeaders, Html, IntoResponse},
    routing::get,
};
use tokio::fs::File;
use tokio_util::io::ReaderStream;

const IP_BIND_LOCAL: IpAddr = IpAddr::V4(Ipv4Addr::new(0, 0, 0, 0));
const PORT_BIND_LOCAL: u16 = 8080;
const LOCAL_HOST: SocketAddr = SocketAddr::new(IP_BIND_LOCAL, PORT_BIND_LOCAL);
const HINTS_DIR: &str = "/root/hints/";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Chain {
    Signet,
    Bitcoin,
}

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/", get(index))
        .route("/hints/bitcoin", get(handle_bitcoin_hints))
        .route("/hints/signet", get(handle_signet_hints));
    let listener = tokio::net::TcpListener::bind(&LOCAL_HOST).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

async fn index() -> Html<&'static str> {
    Html(
        r#"
        <!DOCTYPE html>
        <html>
            <head>
                <meta charset="utf-8">
                <title>SwiftSync Hints</title>
            </head>
            <body>
                <h1>SwiftSync Hints</h1>
                <ul>
                    <li><a href="/hints/bitcoin">Bitcoin hints</a></li>
                    <li><a href="/hints/signet">Signet hints</a></li>
                </ul>
            </body>
        </html>
        "#,
    )
}

async fn handle_bitcoin_hints() -> impl IntoResponse {
    stream_hints_file(Chain::Bitcoin).await
}

async fn handle_signet_hints() -> impl IntoResponse {
    stream_hints_file(Chain::Signet).await
}

async fn stream_hints_file(chain: Chain) -> impl IntoResponse {
    let bitcoin_dir_path = PathBuf::from_str(&HINTS_DIR).unwrap();
    let (hintsfile_path, hintsfile_disposition) = match chain {
        Chain::Signet => (
            bitcoin_dir_path.join("signet.hints"),
            "attachment; filename=\"signet.hints\"",
        ),
        Chain::Bitcoin => (
            bitcoin_dir_path.join("bitcoin.hints"),
            "attachment; filename=\"bitcoin.hints\"",
        ),
    };
    let file = match File::open(hintsfile_path).await {
        Ok(file) => file,
        Err(err) => return Err((StatusCode::NOT_FOUND, format!("File not found: {err}"))),
    };
    let byte_stream = ReaderStream::new(file);
    let body = Body::from_stream(byte_stream);
    let headers = AppendHeaders([
        (header::CONTENT_TYPE, "application/octet-stream"),
        (header::CONTENT_DISPOSITION, hintsfile_disposition),
    ]);
    Ok((headers, body))
}
