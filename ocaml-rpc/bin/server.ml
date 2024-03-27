module Configuration = struct
  type t = {
    rpc_addr : string;
    rpc_port : int;
    cors_origins : string list;
    cors_headers : string list;
  }
end

module Events = struct
  include Tezos_base.TzPervasives.Internal_event.Simple

  let section = [ "test_rpc_server" ]

  let event_is_ready =
    Tezos_base.TzPervasives.Internal_event.Simple.declare_2 ~section
      ~name:"is_ready" ~msg:"the RPC server is listening to {addr}:{port}"
      ~level:Notice
      ("addr", Data_encoding.string)
      ("port", Data_encoding.uint16)

  let is_ready ~rpc_addr ~rpc_port = emit event_is_ready (rpc_addr, rpc_port)
end

module Services = struct
  let version_service =
    Tezos_rpc.Service.get_service ~description:"version"
      ~query:Tezos_rpc.Query.empty ~output:Data_encoding.string
      Tezos_rpc.Path.(root / "version")

  let client_version =
    Format.sprintf "v%s/%s/ocamlc.%s" "1.0" Stdlib.Sys.os_type
      Stdlib.Sys.ocaml_version

  let version dir =
    Tezos_rpc.Directory.register0 dir version_service (fun () () ->
        Lwt.return_ok client_version)

  let directory =
    let dir = Tezos_rpc.Directory.empty in
    let dir = version dir in
    dir
end

let start_server
    Configuration.{ rpc_addr; rpc_port; cors_origins; cors_headers } =
  let open Tezos_base.TzPervasives.Lwt_result_syntax in
  let open Tezos_rpc_http_server in
  let p2p_addr = Tezos_base.P2p_addr.of_string_exn rpc_addr in
  let host = Ipaddr.V6.to_string p2p_addr in
  let node = `TCP (`Port rpc_port) in
  let acl = RPC_server.Acl.allow_all in
  let cors =
    Resto_cohttp.Cors.
      { allowed_headers = cors_headers; allowed_origins = cors_origins }
  in
  let server =
    RPC_server.init_server ~acl ~cors
      ~media_types:Tezos_rpc_http.Media_type.all_media_types Services.directory
  in
  Lwt.catch
    (fun () ->
      let*! () =
        RPC_server.launch ~host server
          ~callback:(RPC_server.resto_callback server)
          node
      in
      let*! () = Events.is_ready ~rpc_addr ~rpc_port in
      return server)
    (fun _ -> return server)

let main =
  let config =
    Configuration.
      {
        rpc_addr = "::ffff:127.0.0.1";
        rpc_port = 8000;
        cors_headers = [];
        cors_origins = [];
      }
  in
  let open Tezos_base.TzPervasives.Lwt_result_syntax in
  (* Activate logging system. *)
  let*! _ = Tezos_base_unix.Internal_event_unix.init () in
  let* _ = start_server config in
  Tezos_base.TzPervasives.Lwt_utils.never_ending ()

let _ = Lwt_main.run main
