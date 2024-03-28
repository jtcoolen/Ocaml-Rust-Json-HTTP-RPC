#![deny(warnings)]

use bytes::Bytes;
use futures_util::TryStreamExt;
use http_body_util::combinators::BoxBody;
use http_body_util::{BodyExt, Full, StreamBody};
use hyper::body::Frame;
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper::{header, Method, Request, Response, StatusCode};
use hyper_util::rt::{TokioIo, TokioTimer};
use std::net::SocketAddr;
use tokio::fs::File;
use tokio::net::TcpListener;
use tokio_util::io::ReaderStream;

static NOTFOUND: &[u8] = b"Not Found";

/// HTTP status code 404
fn not_found() -> Response<BoxBody<Bytes, std::io::Error>> {
    Response::builder()
        .status(StatusCode::NOT_FOUND)
        .body(Full::new(NOTFOUND.into()).map_err(|e| match e {}).boxed())
        .unwrap()
}

async fn simple_file_send(
    filename: &str,
) -> hyper::Result<Response<BoxBody<Bytes, std::io::Error>>> {
    // Open file for reading
    println!("simple_file_send");
    let file = File::open(filename).await;
    if file.is_err() {
        eprintln!("ERROR: Unable to open file.");
        println!("ERROR: Unable to open file.");
        return Ok(not_found());
    }

    let file: File = file.unwrap();

    // Wrap to a tokio_util::io::ReaderStream
    let reader_stream = ReaderStream::new(file);

    // Convert to http_body_util::BoxBody
    let stream_body =
        StreamBody::new(reader_stream.map_ok(Frame::data)).map_frame(|f: Frame<Bytes>| {
            let data: Bytes = f.into_data().unwrap();
            let data = std::str::from_utf8(&data).unwrap();
            Frame::data(serde_json::to_string(&data).unwrap().into())
        });
    let boxed_body = stream_body.boxed();

    // Send response
    let response: Response<BoxBody<Bytes, std::io::Error>> = Response::builder()
        .status(StatusCode::OK)
        .body(boxed_body)
        .unwrap();
    println!("end simple_file_send");
    Ok(response)
}

// An async function that consumes a request, does nothing with it and returns a
// response.
async fn hello(
    req: Request<impl hyper::body::Body>,
) -> hyper::Result<Response<BoxBody<Bytes, std::io::Error>>> {
    match (req.method(), req.uri().path()) {
        (&Method::GET, "/version") => {
            let data = "foobar";
            println!("version");
            let json = serde_json::to_string(&data).unwrap();
            let response = Response::builder()
                .header(header::CONTENT_TYPE, "application/json")
                .body(Full::new(json.into()).map_err(|e| match e {}).boxed())
                .unwrap();
            Ok(response)
        }
        (&Method::GET, "/stream") => {
            println!("/stream");
            // Test what happens when file cannot be be found
            simple_file_send("big.txt").await
        }
        _ => Ok(not_found()),
    }
}

#[tokio::main]
pub async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // This address is localhost
    let addr: SocketAddr = ([127, 0, 0, 1], 3000).into();

    // Bind to the port and listen for incoming TCP connections
    let listener = TcpListener::bind(addr).await?;
    println!("Listening on http://{}", addr);
    loop {
        // When an incoming TCP connection is received grab a TCP stream for
        // client<->server communication.
        //
        // Note, this is a .await point, this loop will loop forever but is not a busy loop. The
        // .await point allows the Tokio runtime to pull the task off of the thread until the task
        // has work to do. In this case, a connection arrives on the port we are listening on and
        // the task is woken up, at which point the task is then put back on a thread, and is
        // driven forward by the runtime, eventually yielding a TCP stream.
        let (tcp, _) = listener.accept().await?;
        // Use an adapter to access something implementing `tokio::io` traits as if they implement
        // `hyper::rt` IO traits.
        let io = TokioIo::new(tcp);

        // Spin up a new task in Tokio so we can continue to listen for new TCP connection on the
        // current task without waiting for the processing of the HTTP1 connection we just received
        // to finish
        tokio::task::spawn(async move {
            // Handle the connection from the client using HTTP1 and pass any
            // HTTP requests received on that connection to the `hello` function
            if let Err(err) = http1::Builder::new()
                .keep_alive(false)
                .timer(TokioTimer::new())
                .serve_connection(io, service_fn(hello))
                .await
            {
                println!("Error serving connection: {:?}", err);
            }
        });
    }
}
