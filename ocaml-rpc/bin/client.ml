module Services = struct
  let get_version =
    Tezos_rpc.Service.get_service ~description:"Get node version"
      ~query:Tezos_rpc.Query.empty ~output:Data_encoding.string
      Tezos_rpc.Path.(root / "version")

  let stream :
      ([ `GET ], unit, unit, unit, unit, string) Tezos_rpc.Service.service =
    Tezos_rpc.Service.get_service ~query:Tezos_rpc.Query.empty
      ~output:Data_encoding.string
      Tezos_rpc.Path.(root / "stream")
end

open Tezos_rpc.Context

let ctxt ~rpc_addr ~rpc_port =
  let endpoint =
    Uri.of_string @@ Format.sprintf "http://%s:%d" rpc_addr rpc_port
  in
  new Tezos_rpc_http_client_unix.RPC_client_unix.http_ctxt
    { Tezos_rpc_http_client_unix.RPC_client_unix.default_config with endpoint }
    Tezos_rpc_http.Media_type.all_media_types

let _version ~rpc_addr ~rpc_port =
  make_call Services.get_version (ctxt ~rpc_addr ~rpc_port) () () ()

let _make_streamed_call ~uri =
  let open Tezos_base.TzPervasives.Lwt_syntax in
  let stream, push = Lwt_stream.create () in
  let on_chunk v = push (Some v) and on_close () = push None in
  let* _spill_all =
    Tezos_rpc_http_client_unix.RPC_client_unix.call_streamed_service
      [ Tezos_rpc_http.Media_type.json ]
      ~base:uri Services.stream ~on_chunk ~on_close () () ()
  in
  return stream

let _make_streamed_call2 ~rpc_addr ~rpc_port =
  make_streamed_call Services.stream (ctxt ~rpc_addr ~rpc_port) () () ()

let main () =
  let open Tezos_base.TzPervasives.Lwt_result_syntax in
  (* Activate logging system. *)
  let*! _ = Tezos_base_unix.Internal_event_unix.init () in
  let* v = _version ~rpc_addr:"127.0.0.1" ~rpc_port:3000 in
  let _ = Printf.eprintf "\nVersion %s\n" v in
  let _uri = Uri.make ~host:"127.0.0.1" ~port:3000 ~path:"stream" () in
  let* s, _ = _make_streamed_call2 ~rpc_addr:"127.0.0.1" ~rpc_port:3000 in
  let*! _res =
    Lwt_stream.fold
      (fun a acc ->
        Printf.printf "\n%s\n" a;
        a :: acc)
      s []
  in
  return_unit

let _ = Lwt_main.run (main ())
