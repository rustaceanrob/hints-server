use std::{
    net::{IpAddr, Ipv4Addr, SocketAddr},
    path::PathBuf,
    str::FromStr,
};

use axum::{
    Router,
    body::Body,
    http::{StatusCode, header},
    response::{AppendHeaders, IntoResponse},
    routing::get,
};
use tokio::fs::File;
use tokio_util::io::ReaderStream;

const IP_BIND_LOCAL: IpAddr = IpAddr::V4(Ipv4Addr::new(0, 0, 0, 0));
const PORT_BIND_LOCAL: u16 = 3000;
const LOCAL_HOST: SocketAddr = SocketAddr::new(IP_BIND_LOCAL, PORT_BIND_LOCAL);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Chain {
    Signet,
    Bitcoin,
}

#[tokio::main]
async fn main() {
    let app = Router::new()
        .route("/", get(async || "SwiftSync hints assistant."))
        .route("/hints/bitcoin", get(handle_bitcoin_hints))
        .route("/hints/signet", get(handle_signet_hints));
    let listener = tokio::net::TcpListener::bind(&LOCAL_HOST).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

async fn handle_bitcoin_hints() -> impl IntoResponse {
    stream_hints_file(Chain::Bitcoin).await
}

async fn handle_signet_hints() -> impl IntoResponse {
    stream_hints_file(Chain::Signet).await
}

async fn stream_hints_file(chain: Chain) -> impl IntoResponse {
    let bitcoin_dir = std::env::var("HINTS_DIR").unwrap();
    let bitcoin_dir_path = PathBuf::from_str(&bitcoin_dir).unwrap();
    let hintsfile_path = match chain {
        Chain::Signet => bitcoin_dir_path.join("signet.hints"),
        Chain::Bitcoin => bitcoin_dir_path.join("bitcoin.hints"),
    };
    let file = match File::open(hintsfile_path).await {
        Ok(file) => file,
        Err(err) => return Err((StatusCode::NOT_FOUND, format!("File not found: {err}"))),
    };
    let byte_stream = ReaderStream::new(file);
    let body = Body::from_stream(byte_stream);
    let headers = AppendHeaders([
        (header::CONTENT_TYPE, "binary/hints"),
        (header::CONTENT_DISPOSITION, "file"),
    ]);
    Ok((headers, body))
}
