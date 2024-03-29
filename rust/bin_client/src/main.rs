#![deny(warnings)]
#![warn(rust_2018_idioms)]

//use std::io::Read;

use bytes::{Buf, Bytes};
use http_body_util::{BodyExt, Empty};
use hyper::Request;
use hyper_util::rt::TokioIo;
use tokio::net::TcpStream;

// A simple type alias so as to DRY.
type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

#[tokio::main]
async fn main() -> Result<()> {
    let url = "localhost".parse().unwrap();
    let version = fetch_json(url).await?;
    // print version
    println!("version: {:#?}", version);

    Ok(())
}

async fn fetch_json(url: hyper::Uri) -> Result<String> {
    let host = url.host().expect("uri has no host");
    let port = url.port_u16().unwrap_or(8000);
    let addr = format!("{}:{}", host, port);

    let stream = TcpStream::connect(addr).await?;
    let io = TokioIo::new(stream);

    let (mut sender, conn) = hyper::client::conn::http1::handshake(io).await?;
    tokio::task::spawn(async move {
        if let Err(err) = conn.await {
            println!("Connection failed: {:?}", err);
        }
    });

    let authority = url.authority().unwrap().clone();

    // Fetch the url...
    let req = Request::builder()
        .method("GET")
        .uri("/version")
        .header(hyper::header::HOST, authority.as_str())
        .body(Empty::<Bytes>::new())?;

    let res = sender.send_request(req).await?;

    // asynchronously aggregate the chunks of the body
    let body = res.collect().await?.aggregate();

    // try to parse as json with serde_json
    let version = serde_json::from_reader(body.reader())?;
    println!("version: {:#?}", version);

    // Fetch the url...
    let req = Request::builder()
        .method("GET")
        .uri("/stream")
        .header(hyper::header::HOST, authority.as_str())
        .body(Empty::<Bytes>::new())?;

    let res: hyper::Response<hyper::body::Incoming> = sender.send_request(req).await?;

    // asynchronously aggregate the chunks of the body
    let body = res.collect().await?.aggregate();

    // Create a vector to hold the contents read from the buffer
    /*let mut contents = Vec::new();

    let mut reader = body.reader();
    // Read contents from the buffer in a loop until the end
    loop {
        let mut chunk = [0; 8]; // Define a chunk size
        let bytes_read = reader.read(&mut chunk)?;

        if bytes_read == 0 {
            break; // If no bytes were read, we've reached the end of the buffer
        }

        // Append the read bytes to the contents vector
        contents.extend_from_slice(&chunk[..bytes_read]);
    }

    println!(
        "data: {:?}",
        std::str::from_utf8(&contents)?
            .lines()
            .map(String::from)
            .map(|s| serde_json::from_str(&s))
            .collect::<Vec<std::result::Result<String, serde_json::Error>>>()
    );

    */

    let deserializer = serde_json::Deserializer::from_reader(body.reader());
    let iterator = deserializer.into_iter::<serde_json::Value>();
    for item in iterator {
        println!("Got {:?}", item?);
    }
    // try to parse as json with serde_json
    /*let data: String = serde_json::from_reader(body.reader()).unwrap_or_else(|e| {
        eprintln!("\nError: {}", e);
        ::std::process::exit(1);
    });

    println!("data: {:#?}", data);*/

    Ok(version)
}
