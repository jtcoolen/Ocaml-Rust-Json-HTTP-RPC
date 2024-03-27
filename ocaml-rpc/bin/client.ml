module Services = struct
  let get_version =
    Tezos_rpc.Service.post_service ~description:"Get node version"
      ~query:Tezos_rpc.Query.empty ~input:Data_encoding.empty
      ~output:Data_encoding.string
      Tezos_rpc.Path.(root / "version")
end

open Tezos_rpc.Context

let ctxt ~rpc_addr ~rpc_port =
  let endpoint =
    Uri.of_string @@ Format.sprintf "http://%s:%d" rpc_addr rpc_port
  in
  new Tezos_rpc_http_client_unix.RPC_client_unix.http_ctxt
    { Tezos_rpc_http_client_unix.RPC_client_unix.default_config with endpoint }
    Tezos_rpc_http.Media_type.all_media_types

let version ~rpc_addr ~rpc_port =
  make_call Services.get_version (ctxt ~rpc_addr ~rpc_port) () () ()

let main () =
  let open Tezos_base.TzPervasives.Lwt_result_syntax in
  (* Activate logging system. *)
  let*! _ = Tezos_base_unix.Internal_event_unix.init () in
  let* v = version ~rpc_addr:"127.0.0.1" ~rpc_port:3000 in
  let _ = Printf.eprintf "Version %s\n" v in
  return_unit

let _ = Lwt_main.run (main ())
