open Cryptokit

let _decode_fixed32 s off =
  let byte x = int_of_char s.[off + x] in
  ((byte 3) lsl  0)
  + ((byte 2) lsl  8)
  + ((byte 1) lsl 16)
  + ((byte 0) lsl 24)

let _encode_fixed32 (s:bytes) off i =
  let get_char i shift = char_of_int ((i land (0xff lsl shift)) lsr shift) in
  Bytes.set s off (get_char i 24);
  Bytes.set s (off + 1) (get_char i 16);
  Bytes.set s (off + 2) (get_char i  8);
  Bytes.set s (off + 3) (get_char i  0)

let calculate_hmac secret msg =
  let sx0 = Bytes.create 4 in
  _encode_fixed32 sx0 0 (String.length msg);
  let h = Cryptokit.MAC.hmac_sha1 secret in
  let () = h # add_string sx0 in
  let () = h # add_string msg in
  h # result

let to_hex = function
  | "" -> ""
  | s ->
     let n_chars = String.length s * 3 in
     let buf = Buffer.create n_chars in
     let hex c = Printf.sprintf "%02x " (Char.code c) in
     String.iter (fun c -> Buffer.add_string buf (hex c)) s;
     Buffer.sub buf 0 (n_chars - 1)


let unwrap_option msg = function
  | None -> failwith ("None " ^ msg)
  | Some x -> x

let map_option f = function
  | None -> None
  | Some x -> Some (f x)

let get_option default = function
  | None -> default
  | Some x -> x

let show_option x2s = function
  | None -> "None"
  | Some x -> Printf.sprintf "Some %s" (x2s x)

let show_pair x2s y2s (x,y) = Printf.sprintf "(%s, %s)" (x2s x) (y2s y)


let so2s   = show_option (fun x -> x)
let so2hs  = show_option (fun x -> Printf.sprintf "0x%s" (to_hex x))
let bo2s   = show_option (function | true -> "true" | false -> "false")
let i64o2s = show_option Int64.to_string


let trimmed x =
  let x', post =
    let len = String.length x in
    if len < 20
    then x, "" else
      (String.sub x 0 20), Printf.sprintf "... (%i bytes)" len
  in
  Printf.sprintf "0x%S%s" (to_hex x')  post





open Kinetic_piqi
open Message
open Command
open Command_header
open Command_body
open Command_status

let section = Lwt_log.Section.make "kinetic"
let tracing = Lwt_log.Section.make "tracing"

let _assert_type (command:Command.t) typ =
  let header  = unwrap_option "header" command.header in
  let htyp    = unwrap_option "message type" header.message_type in
  assert (htyp = typ)

let _get_status (command: Command.t) =
  let status = unwrap_option "status" command.status in
  status

let _get_status_code (status:Command_status.t) =
  let code = unwrap_option "status.code" status.code in
  code

let _get_status_message (status:Command_status.t) =
  let msg = unwrap_option "status.message" status.status_message in
  msg

let _get_detailed_status_message (status:Command_status.t) =
  match status.detailed_message with
  | Some x -> x
  | None -> "None"

let _assert_success (command:Command.t) =
  let code = _get_status command |> _get_status_code in
  assert (code = `success)

let message_type2s = function
  | `invalid_message_type -> "invalide_message_type"
  | `get -> "get"
  | `get_response -> "get_response"
  | `put -> "put"
  | `put_response -> "put_response"
  | `delete -> "delete"
  | `delete_response -> "delete_response"
  | `start_batch_response -> "start_batch_response"
  | `end_batch_response -> "end_batch_response"
  | `flushalldata -> "flushalldata"
  | `flushalldata_response -> "flushalldata_response"
  | _ -> "TODO: message type2s"

let status_code2s = function
  | `invalid_status_code -> "invalid_status_code"
  | `not_attempted -> "not_attempted"
  | `success -> "success"
  | `hmac_failure -> "hmac_failure"
  | `not_authorized -> "not_authorized"
  | `version_failure -> "version_failure"
  | `internal_error -> "internal_error"
  | `header_required -> "header_required"
  | `not_found -> "not_found"
  | `version_mismatch -> "version_mismatch"
  | `service_busy -> "service_busy"
  | `expired -> "expired"
  | `data_error -> "data_error"
  | `perm_data_error -> "perm_data_error"
  | `remote_connection_error ->"remove_connection_error"
  | `no_space -> "no_space"
  | `no_such_hmac_algorithm -> "no_such_hmac_algorithm"
  | `invalid_request -> "invalid_request"
  | _ -> "TODO: status_code2s"

let status_code2i = function
  | `invalid_status_code     -> -1
  | `not_attempted           ->  0 (* p2p *)
  | `success                 ->  1
  | `hmac_failure            ->  2
  | `not_authorized          ->  3
  | `version_failure         ->  4
  | `internal_error          ->  5
  | `header_required         ->  6
  | `not_found               ->  7
  | `version_mismatch        ->  8
  | `service_busy            ->  9
  | `expired                 -> 10
  | `data_error              -> 11
  | `perm_data_error         -> 12
  | `remote_connection_error -> 13
  | `no_space                -> 14
  | `no_such_hmac_algorithm  -> 15
  | `invalid_request         -> 16
  | `nested_operation_errors -> 17
  | `device_locked           -> 18
  | `device_already_unlocked -> 19
  | `connection_terminated   -> 20
  | `invalid_batch           -> 21 (* 3.0.6 *)
  | _ -> 42

let _get_message_type (command:Command.t) =
  let header = unwrap_option "header" command.header in
  unwrap_option "message_type" header.message_type

let _assert_both (command:Command.t) typ code =
  let header = unwrap_option "header" command.header in
  let htyp = unwrap_option "message type" header.message_type in
  if htyp = typ
  then
    begin
      let status = _get_status command in
      let ccode = _get_status_code status in
      if ccode = code
      then ()
      else
        begin
          let () = Printf.printf "ccode:%s\n%!" (status_code2s ccode) in
          let sm = _get_status_message status in
          failwith sm
        end
    end
  else
    failwith (
      htyp |>
        message_type2s |>
        Printf.sprintf "unexpected type: %s"
      )


let maybe_verify_msg (m:Message.t) =
  let open Message in
  match m.auth_type with
  | Some `unsolicitedstatus -> ()
  | _ -> failwith "todo:verify_msg"


let verify_status (status:Command_status.t) =
  let open Command_status in
  let code = unwrap_option "status.code" status.code in
  match code with
  | `success -> ()
  | _ -> failwith "todo: other status"



let verify_cluster_version (header:Command_header.t) my_cluster_version =

  let cluster_version = get_option 0L header.cluster_version in
  assert (my_cluster_version = cluster_version);
  ()

let verify_limits log = ()

open Lwt

let maybe_read_value ic value_ln =
  match value_ln with
  | 0 -> Lwt.return None
  | n -> let vb = Bytes.create value_ln in
         Lwt_io.read_into_exactly ic vb 0 value_ln >>= fun () ->
         Lwt.return (Some vb)

let network_receive ic trace =
  let msg_bytes = Bytes.create 9 in
  Lwt_io.read_into_exactly ic msg_bytes 0 9 >>= fun () ->
  let magic = msg_bytes.[0] in
  let proto_ln = _decode_fixed32 msg_bytes 1 in
  let value_ln = _decode_fixed32 msg_bytes 5 in
  (*
    Lwt_io.printlf
    "magic:%C proto_ln:%i value_ln:%i" magic proto_ln value_ln
    >>= fun () ->
   *)
  assert (magic = 'F');
  let proto_raw = Bytes.create proto_ln in
  Lwt_io.read_into_exactly ic proto_raw 0 proto_ln >>= fun () ->
  begin
    if trace
    then Lwt_log.info_f
           ~section:tracing
           "received: %s" (to_hex proto_raw)
    else Lwt.return_unit
  end
  >>= fun () ->

  maybe_read_value ic value_ln >>= fun vo ->
  let buf = Piqirun.init_from_string proto_raw in
  let m = parse_message buf in
  Lwt.return (m,vo)


let network_send oc proto_raw vo trace =
  let prelude = Bytes.create 9 in
  Bytes.set prelude 0 'F';

  _encode_fixed32 prelude 1 (String.length proto_raw);
  let write_vo = match vo with
    |None ->
      begin
        _encode_fixed32 prelude 5 0;
        fun () -> Lwt.return_unit
      end
    |Some v ->
      begin
        _encode_fixed32 prelude 5 (Bytes.length v);
        fun () -> Lwt_io.write oc v
      end
  in
  begin
    if trace
    then
      Lwt_log.debug_f ~section:tracing "sending: %s\n" (to_hex proto_raw)
    else
      Lwt.return_unit
  end
    >>= fun () ->
  Lwt_io.write oc prelude >>= fun () ->
  Lwt_io.write oc proto_raw >>= fun ()->
  write_vo ()

let _parse_command (m:Message.t) =
  let open Message in
  let command_bytes = unwrap_option "command_bytes" m.command_bytes in
  let command_buf = Piqirun.init_from_string command_bytes in
  let command = parse_command command_buf in
  command

let _get_sequence (command : Command.t) =
  let header = unwrap_option "header" command.header in
  let seq = unwrap_option "sequence" header.sequence in
  seq

let _get_ack_sequence (command:Command.t) =
  let header = unwrap_option "header" command.header in
  let ack_seq = unwrap_option "ack_sequence" header.ack_sequence in
  ack_seq


module Config = struct
    type t = {
        vendor: string;
        model:string;
        serial_number: string;
        world_wide_name: string;
        version: string;
        max_key_size: int;
        max_value_size: int;
        max_version_size: int;
        max_tag_size: int;
        max_connections: int;
        max_outstanding_read_requests: int;
        max_outstanding_write_requests: int;
        max_message_size: int;
        max_key_range_count: int;
        (* max_operation_count_per_batch: int; *)
        (* max_batch_count_per_device: int; *)
      }

    let make ~vendor ~world_wide_name ~model
             ~serial_number
             ~version
             ~max_key_size
             ~max_value_size
             ~max_version_size
             ~max_tag_size
             ~max_connections
             ~max_outstanding_read_requests
             ~max_outstanding_write_requests
             ~max_message_size
             ~max_key_range_count
             (* ~max_operation_count_per_batch *)
             (* ~max_batch_count_per_device *)
      = {
        vendor;
        model;
        serial_number;
        world_wide_name;
        version;
        max_key_size;
        max_value_size;
        max_version_size;
        max_tag_size;
        max_connections;
        max_outstanding_read_requests;
        max_outstanding_write_requests;
        max_message_size;
        max_key_range_count;
        (* max_operation_count_per_batch; *)
        (* max_batch_count_per_device; *)
      }

    let show t =
      let buffer = Buffer.create 128 in
      let add x = Printf.kprintf (fun s -> Buffer.add_string buffer s) x in
      add "Config {";
      add " version: %S;" t.version;
      add " wwn:%S;" t.world_wide_name;
      add " serial_number:%S;" t.serial_number;
      add " max_key_size:%i;" t.max_key_size;
      add " max_value_size:%i;" t.max_value_size;
      add " max_version_size:%i;" t.max_version_size;
      add " max_tag_size:%i;" t.max_tag_size;
      add " max_connections:%i;" t.max_connections;
      add " max_outstanding_read_requests:%i;" t.max_outstanding_read_requests;
      add " max_oustranding_write_requests:%i;" t.max_outstanding_write_requests;
      add " max_message_size:%i;" t.max_message_size;
      (*
      add " max_key_range_count:%i;" t.max_operation_count_per_batch;
      add " max_batch_count_per_device:%i;" t.max_batch_count_per_device;
      *)
      add "}";
      Buffer.contents buffer
end
module Session = struct

    type t = {
        secret: string;
        cluster_version: int64;
        identity: int64;
        connection_id: int64;
        mutable sequence: int64;
        mutable batch_id: int32;

        config : Config.t;
        mutable trace: bool
      }


    let incr_sequence t = t.sequence <- Int64.succ t.sequence
    let set_sequence t i64 = t.sequence <- i64

end

module Batch =
struct

  type rc = | Ok | Nok of int * bytes

  type handler = rc -> unit Lwt.t

  type t = { mvar :  bool Lwt_mvar.t;
             handlers : (command_message_type,
                         rc -> unit Lwt.t) Hashtbl.t;
             connection : Lwt_io.input_channel * Lwt_io.output_channel;
             batch_id : int32;
             go : bool ref;
             session : Session.t;
             mutable count : int;
           }

  let find t h =
    try Some (Hashtbl.find t h)
    with Not_found -> None


  let remove t h = Hashtbl.remove t h

  let make session connection batch_id =
    let ic,oc = connection in
    let handlers = Hashtbl.create 5 in
    let mvar = Lwt_mvar.create_empty () in
    let success = ref true in
    let rec loop (go:bool ref) (ic:Lwt_io.input_channel) =
      let size = Hashtbl.length handlers in
      if size > 0 || !go
      then
        begin
          Lwt_log.debug ~section "waiting for msg" >>= fun () ->
          network_receive ic session.Session.trace >>= fun (m,vo) ->
          Lwt_log.debug ~section "got msg" >>= fun () ->
          let command = _parse_command m in
          let typ = _get_message_type command in
          let typs = message_type2s typ in
          begin
            match find handlers typ with
            | None ->
               Lwt_log.info_f ~section "\tignoring: %s" typs
            | Some h ->
               Lwt_log.debug_f ~section "found handler for: %s" typs
               >>= fun () ->
               let () = remove handlers typ in
               let status = _get_status command in
               let ccode = _get_status_code status in
               let rc =
                 match ccode with
                 | `success -> Ok
                 | _ ->
                    let sm = _get_status_message status in
                    let dsm = _get_detailed_status_message status in
                    Lwt_log.ign_debug_f ~section
                                        "dsm:%S" dsm;
                    let (rci:int) = status_code2i ccode in
                    Nok (rci, sm)
               in
               Lwt.catch
                 (fun () ->h rc)
                 (fun exn -> go:= false;
                             success := false;
                             Lwt.return_unit)
          end >>= fun ()->
          loop go ic
        end
      else
        begin
          Lwt_mvar.put mvar !success >>= fun () ->
          Lwt_log.debug ~section "loop ends here."
        end
    in
    let go = ref true in
    let t =
      Lwt.catch
        (fun () ->loop go ic )
        (fun exn ->
         Lwt_log.debug_f ~exn ~section "batch loop for %li failed" batch_id
         >>= fun ()->
         let rci = status_code2i `internal_error in
         let rc_bad = Nok (rci, Printexc.to_string exn) in
         Hashtbl.iter (fun k h ->
                       Lwt.ignore_result (h rc_bad);
                      ) handlers;
         Lwt.return_unit
        )
    in
    let () = Lwt.ignore_result t in
    { mvar  ; handlers ; connection; batch_id; go = go;
      session; count = 0;}

  let inc_count t = t.count <- t.count + 1

  let add_handler t typ h =
    let typs = message_type2s typ in
    Lwt_log.debug_f ~section "add handler for: %s" typs >>= fun () ->
    Hashtbl.add t.handlers typ h;
    Lwt.return_unit

  let close t =
    Lwt_log.debug ~section "closing...." >>= fun () ->
    t.go := false;
    Lwt_mvar.take  t.mvar >>= fun success ->
    Lwt.return success
end




module Kinetic = struct


    type session = Session.t

    let get_connection_id (session:session) =
      let open Session in session.connection_id


    type batch = Batch.t
    let get_batch_id (batch:batch) =
      let open Batch in batch.batch_id
    type synchronization =
      |WRITETHROUGH
      |WRITEBACK
      |FLUSH
    type tag =
      | Invalid of Bytes.t
      | Sha1 of Bytes.t
      | Crc32 of int32

    type rc = Batch.rc

    let convert_rc = function
      | Batch.Ok -> None
      | Batch.Nok(i,m) -> Some (i,m)

    let show_tag = function
      | Invalid h -> Printf.sprintf "Invalid %s" (to_hex h)
      | Sha1 h -> Printf.sprintf "Sha1 %s" (to_hex h)
      | Crc32 h ->Printf.sprintf "Crc32 %lx" h

    type handler = Batch.handler

    type key = bytes
    type value = bytes
    type version = bytes option

    type connection = Lwt_io.input_channel * Lwt_io.output_channel
    type closer = unit -> unit Lwt.t

    type client = {
        session : session ;
        connection: connection;
        closer : closer;
      }

    type entry = {
        key:key;
        db_version:version;
        new_version : version;
        vt: (value * tag) option;
      }

    let make_sha1 v =
      let h = Cryptokit.Hash.sha1() in
      let () = h # add_string v in
      Sha1 (h # result)

    let make_crc32 v = failwith "todo"

    let make_entry
      ~key ~db_version ~new_version vt
      =
      { key; db_version; new_version; vt }

    let show_entry e =
      let vt2s   = show_option (show_pair trimmed show_tag) in
      Printf.sprintf "{ key=%S; db_version=%s; new_version=%s; vo=%s }"
               e.key
               (so2hs e.db_version)
               (so2hs e.new_version)
               (vt2s e.vt)


    let get_config (session:Session.t) =
      let open Session in
      session.config

    exception Kinetic_exc of (int * bytes) list

    let handshake secret cluster_version ?(trace = false) (ic,oc)  =
      network_receive ic trace >>= fun (m,vo) ->
      let () = maybe_verify_msg m in
      let command = _parse_command m in
      let status = unwrap_option "command.status" command.status in
      let () = verify_status status in
      let header = unwrap_option "command.header" command.header in
      let open Command_header in
      let connection_id = unwrap_option "header.connection_id" header.connection_id in
      Lwt_log.debug_f ~section "connection_id:%Li"
                      connection_id
      >>= fun () ->
      Lwt_log.debug_f "sequence:%s" (i64o2s header.sequence)
      >>= fun () ->
      Lwt_log.debug_f "ack_sequence:%s" (i64o2s header.ack_sequence)
      >>= fun () ->
      let () = verify_cluster_version header cluster_version in
      let open Command_body in
      let body = unwrap_option "command.body" command.body in
      let open Command_get_log in
      let log = unwrap_option "body.get_log" body.get_log in
      (*
         self.config = cmd.body.getLog.configuration
         self.limits = cmd.body.getLog.limits
       *)

      let open Command_get_log_configuration in
      let () = verify_limits log in
      let cfg = unwrap_option "configuration" log.configuration in
      let wwn = unwrap_option "world_wide_name" cfg.world_wide_name in
      let vendor = unwrap_option "vendor" cfg.vendor in
      let model = unwrap_option "model" cfg.model in
      let serial_number = unwrap_option
                            "serial_number"
                            cfg.serial_number in
      let version = unwrap_option "version" cfg.version in
      let limits = unwrap_option "limits" log.limits in
      let open Command_get_log_limits in
      let int_of k o =
        let m_k_s32 = unwrap_option k o in
        Int32.to_int m_k_s32
      in
      let max_key_size     = int_of "max_key_size" limits.max_key_size
      and max_value_size   = int_of "max_value_size" limits.max_value_size
      and max_version_size = int_of "max_version_size" limits.max_version_size
      and max_tag_size     = int_of "max_tag_size" limits.max_tag_size
      and max_connections  = int_of "max_connections" limits.max_connections
      and max_outstanding_read_requests =
        int_of "max_outstanding_read_requests" limits.max_outstanding_read_requests
      and max_outstanding_write_requests =
        int_of "max_outstanding_write_requests" limits.max_outstanding_write_requests
      and max_message_size = int_of "max_message_size" limits.max_message_size
      and max_key_range_count =
        int_of "max_key_range_count" limits.max_key_range_count
      (* and max_operation_count_per_batch =
        int_of "max_operation_count_per_batch" limits.max_operation_count_per_batch

      and max_batch_count_per_device =
        int_of "max_batch_count_per_device" limits.max_batch_count_per_device
       *)
      in
      let config =
        Config.make ~vendor
                    ~world_wide_name:wwn
                    ~model
                    ~serial_number
                    ~version
                    ~max_key_size
                    ~max_value_size
                    ~max_version_size
                    ~max_tag_size
                    ~max_connections
                    ~max_outstanding_read_requests
                    ~max_outstanding_write_requests
                    ~max_message_size
                    ~max_key_range_count
                    (* ~max_operation_count_per_batch *)
                    (* ~max_batch_count_per_device *)
      in
      Lwt_log.debug_f "config=%s" (Config.show config) >>= fun () ->
      let session =
        let open Session in {
          cluster_version;
          identity = 1L;
          sequence = 1L;
          secret;
          connection_id;
          batch_id = 1l;
          config ;
          trace;
        }
      in
      Lwt.return session



  let make_serialized_msg session mt body_manip =
    let open Message_hmacauth in
    let open Session in
    let command = default_command () in
    let header = default_command_header () in
    let () = header.cluster_version <- Some session.cluster_version in
    let () = header.connection_id <- Some session.connection_id in
    let () = header.sequence <- Some session.sequence in

    let () = command.header <- Some header in

    let body = default_command_body () in
    let () = body_manip body in
    let () = command.body <- Some body in
    let m = default_message () in

    let () = header.message_type <- Some mt in


    let command_bytes = Piqirun.to_string(gen_command command) in
    m.command_bytes <- Some command_bytes;
    let hmac = calculate_hmac session.secret command_bytes in
    let hmac_auth = default_message_hmacauth() in
    hmac_auth.identity <- Some session.identity;
    hmac_auth.hmac <- Some hmac;
    m.auth_type <- Some `hmacauth;
    m.hmac_auth <- Some hmac_auth;
    let proto_raw = Piqirun.to_string(gen_message m) in
    proto_raw

  let make_pin_auth_serialized_msg session (pin:string) mt body_manip =

    let open Session in
    let command = default_command () in
    let header = default_command_header () in
    let () = header.cluster_version <- Some session.cluster_version in
    let () = header.connection_id <- Some session.connection_id in
    let () = header.sequence <- Some session.sequence in

    let () = command.header <- Some header in

    let body = default_command_body () in
    let () = body_manip body in
    let () = command.body <- Some body in
    let m = default_message () in

    let () = header.message_type <- Some mt in


    let command_bytes = Piqirun.to_string(gen_command command) in
    m.command_bytes <- Some command_bytes;

    m.auth_type <- Some `pinauth;
    let pin_auth = default_message_pinauth() in
    let () = pin_auth.Message_pinauth.pin <- Some pin in
    m.pin_auth <- Some pin_auth;
    let proto_raw = Piqirun.to_string(gen_message m) in
    proto_raw

  let set_attributes ~ko
                     ~db_version
                     ~new_version
                     ~forced
                     ~synchronization
                     ~maybe_tag
                     (body:Command_body.t)
    =
    let open Command_key_value in
    let kv = default_command_key_value() in
    kv.key <- ko;
    kv.force <- forced;
    kv.db_version <- db_version;
    kv.new_version <- new_version;
    let () = match maybe_tag with
    | None -> ()
    | Some tag ->
       begin
         match tag with
         | Invalid h ->
            begin
              kv.algorithm <- Some `invalid_algorithm;
              kv.tag <- Some h;
            end
         | Sha1 h ->
            begin
              kv.algorithm <- Some `sha1;
              kv.tag <- Some h
            end
         | Crc32 h ->
            let s = Bytes.create 4 in
            _encode_fixed32 s 0 (Int32.to_int h);
            kv.algorithm <- Some `crc32;
            kv.tag <- Some s
       end
    in
    body.key_value <- Some kv;
    let translate = function
      | WRITETHROUGH -> `writethrough
      | WRITEBACK -> `writeback
      | FLUSH     -> `flush
    in
    let sync = map_option translate synchronization in
    kv.synchronization <- sync;
    ()

  let make_delete_forced client key =
    let mb = set_attributes ~ko:(Some key)
                            ~db_version:None
                            ~new_version:None
                            ~forced:(Some true)
                            ~maybe_tag:None
                            ~synchronization:(Some WRITEBACK)
    in
    make_serialized_msg client.session `delete mb

  let make_put client key value
               ~db_version ~new_version
               ~forced ~synchronization
               ~tag
    =
    let mb =
      set_attributes
        ~ko:(Some key)
        ~db_version
        ~new_version
        ~forced
        ~synchronization
        ~maybe_tag:tag
    in
    make_serialized_msg client.session `put mb

  let _no_manip _ = ()

  let make_flush session =
    make_serialized_msg session `flushalldata _no_manip

  let make_batch_message
        ?(body_manip = _no_manip)
        session mt batch_id =
    let open Message_hmacauth in
    let open Session in
    let command = default_command () in
    let header = default_command_header () in
    header.cluster_version <- Some session.cluster_version;
    header.connection_id <- Some session.connection_id;
    header.sequence <- Some session.sequence;
    header.batch_id <- Some batch_id;

    let () = command.header <- Some header in

    let body = default_command_body () in

    let () = body_manip body in

    let () = command.body <- Some body in

    let m = default_message () in

    let () = header.message_type <- Some mt in

    let command_bytes = Piqirun.to_string(gen_command command) in
    m.command_bytes <- Some command_bytes;
    let hmac = calculate_hmac session.secret command_bytes in
    let hmac_auth = default_message_hmacauth() in
    hmac_auth.identity <- Some session.identity;
    hmac_auth.hmac <- Some hmac;

    m.auth_type <- Some `hmacauth;
    m.hmac_auth <- Some hmac_auth;
    let proto_raw = Piqirun.to_string(gen_message m) in
    proto_raw

  let make_start_batch session batch_id =
    make_batch_message session `start_batch batch_id

  let make_end_batch (b:Batch.t) =
    let open Batch in
    let body_manip body =
      let batch = default_command_batch () in
      let count = b.count in
      let open Command_batch in
      batch.count <- Some (Int32.of_int count);
      body.batch <- Some batch
    in
    make_batch_message b.session `end_batch b.batch_id ~body_manip

  let make_abort_batch session batch_id =
    make_batch_message session `abort_batch batch_id

  let tracing (session:Session.t) t =
    session.Session.trace <- t

  let _call client msg vo =
    let ic,oc = client.connection in
    let trace = client.session.Session.trace in
    network_send oc msg vo trace >>= fun () ->
    network_receive ic trace >>= fun (r,vo) ->
    Lwt.return (r,vo)

  let put (client:client) k value
          ~db_version ~new_version
          ~forced
          ~synchronization
          ~tag
    =
    let msg =
      make_put
        client k value
        ~db_version ~new_version
        ~forced ~synchronization
        ~tag
    in
    _call client msg (Some value) >>= fun (r,vo) ->
    assert (vo = None);
    let command = _parse_command r in
    let () = Session.incr_sequence client.session in
    _assert_both command `put_response `success;
    Lwt.return_unit

  let delete_forced (client:client) k =
    let msg = make_delete_forced client k in
    _call client msg None >>= fun (r, vo) ->
    assert (vo = None);
    let command = _parse_command r in
    let () = Session.incr_sequence client.session in
    _assert_type command `delete_response;
    _assert_success command;
    Lwt.return_unit



  let make_get session key =
    let mb = set_attributes ~ko:(Some key)
                            ~db_version:None
                            ~new_version:None
                            ~forced:None
                            ~synchronization:None
                            ~maybe_tag:None
    in
    make_serialized_msg session `get mb

  let get client k =
    let msg = make_get client.session k in
    _call client msg None >>= fun (r,vo) ->

    let command = _parse_command r in

    (* _assert_type command  `get_response;*)

    let status = _get_status command in

    let code = _get_status_code status in
    Lwt_log.debug_f ~section "code=%i" (status_code2i code) >>= fun () ->
    let () = Session.incr_sequence client.session in

    match code with
    | `not_found ->
       Lwt_log.debug_f "`not_found" >>= fun () ->
       Lwt.return None
    | `success    ->
       Lwt_log.debug_f "`success" >>= fun () ->
       begin
         let version =
           let body = unwrap_option "body" command.body in
           let open Command_key_value in
           let kv = unwrap_option "kv" body.key_value in
           let db_version = kv.db_version in
           db_version
         in
         let v = unwrap_option "value" vo in
         let r = Some(v, version) in
         Lwt.return r
       end
    | x ->
       Lwt_log.info_f ~section "code=%i" (status_code2i x) >>= fun () ->
       let sm = _get_status_message status in
       Lwt.fail (Failure sm)

  let set_kr start_key sinc end_key einc reverse_results max_results body =
    let open Command_range in
    let range = default_command_range () in
    range.start_key <- Some start_key;
    range.start_key_inclusive <- Some sinc;
    range.end_key   <- Some end_key;
    range.end_key_inclusive <- Some einc;
    range.reverse <- Some reverse_results;
    let max32 = Int32.of_int max_results in
    range.max_returned <- Some max32;
    body.range <- Some range;
    ()

  let make_get_key_range session
                         start_key sinc
                         end_key einc
                         reverse_results
                         max_results =
      let manip = set_kr
                    start_key sinc
                    end_key einc
                    reverse_results
                    max_results
      in
      make_serialized_msg session `getkeyrange manip

  let get_key_range_result (command : Command.t) =
    match command.body with
    | None -> []
    | Some body ->
      let range   = unwrap_option "range" body.range in
      let open Command_range in
      let (keys:string list) = range.keys in
      keys


  let get_key_range client
                    (start_key:string) sinc
                    (end_key:string) einc
                    (reverse_results:bool)
                    (max_results:int) =
    let msg = make_get_key_range client.session start_key sinc
                                 end_key einc reverse_results
                                 max_results
    in
    _call client msg None >>= fun (r,vo) ->
    let command = _parse_command r in
    _assert_type command `getkeyrange_response;
    Session.incr_sequence client.session;
    let status = _get_status command in
    let code = _get_status_code status in
    match code with
    | `success ->
       let key_list = get_key_range_result command in
       Lwt.return key_list
    | _ -> let sm = _get_status_message status in
           Lwt.fail (Failure sm)

  let default_handler rc =
    let open Batch in
    match rc with
    | Ok        -> Lwt_log.debug  ~section "default_handler ok"
    | Nok(i,sm) ->
       Lwt_log.info_f ~section "NOK!: rc:%i; sm=%S"  i sm >>= fun () ->
       Lwt.fail (Kinetic_exc [i,sm])

  let start_batch_operation
        ?(handler = default_handler)
        client =
    let open Session in
    let session = client.session in
    let (ic,oc) = client.connection in
    let batch_id = session.batch_id in
    let () = session.batch_id <- Int32.succ batch_id in
    let msg = make_start_batch session batch_id in
    network_send oc msg None session.Session.trace >>= fun () ->
    let batch = Batch.make session (ic,oc) batch_id in
    Batch.add_handler
      batch
      `start_batch_response
      handler
    >>= fun () ->
    let () = Session.incr_sequence session in
    Lwt.return batch

  let end_batch_operation
        ?(handler = default_handler)
        (batch:Batch.t)
    =
    Lwt_log.debug_f ~section "end_batch_operation" >>= fun () ->
    let open Batch in
    let msg = make_end_batch batch in
    Batch.add_handler batch `end_batch_response handler >>= fun () ->
    let ic, oc = batch.connection in
    let session = batch.session in
    let trace = session.Session.trace in
    network_send oc msg None trace >>= fun () ->

    let () = Session.incr_sequence session in
    let flush = make_flush session in

    network_send oc flush None trace >>= fun () ->
    Batch.close batch >>= fun success ->
    Session.incr_sequence session;
    network_receive ic trace >>= fun (flush_result, vo) ->
    assert (vo = None);
    let command = _parse_command flush_result in
    _assert_both command `flushalldata_response `success;
    Lwt.return (success, batch.connection)


  let make_batch_msg session
                     batch_id
                     mt
                     entry
                     ~forced
      =
      let open Message_hmacauth in
      let open Session in
      let command = default_command () in
      let header = default_command_header () in
      header.cluster_version <- Some session.cluster_version;
      header.connection_id <- Some session.connection_id;
      header.sequence <- Some session.sequence;
      header.ack_sequence <- Some session.sequence;

      (* batch_id *)
      header.batch_id <- Some batch_id;

      command.header <- Some header;
      let body = default_command_body () in
      let maybe_tag = map_option snd entry.vt in
      let synchronization = Some WRITETHROUGH in
      set_attributes ~ko:(Some entry.key)
                     ~db_version:entry.db_version
                     ~new_version:entry.new_version
                     ~forced
                     ~synchronization
                     ~maybe_tag
                     body;
      command.body <- Some body;
      let m = default_message () in
      header.message_type <- Some mt;
      let command_bytes = Piqirun.to_string(gen_command command) in
      m.command_bytes <- Some command_bytes;
      let hmac = calculate_hmac session.secret command_bytes in
      let hmac_auth = default_message_hmacauth() in
      hmac_auth.identity <- Some session.identity;
      hmac_auth.hmac <- Some hmac;
      m.auth_type <- Some `hmacauth;
      m.hmac_auth <- Some hmac_auth;
      let proto_raw = Piqirun.to_string(gen_message m) in
      proto_raw

  let batch_put
        (batch:Batch.t) entry
        ~forced
    =
    Lwt_log.debug_f ~section "batch_put %s" (show_entry entry) >>= fun () ->
    let open Batch in
    let msg = make_batch_msg
                batch.session
                batch.batch_id
                `put
                entry
                ~forced
    in
    let (ic,oc) = batch.connection in
    let vo = map_option fst entry.vt in
    let session = batch.session in
    let trace = session.Session.trace in
    network_send oc msg vo trace >>= fun () ->
    let () = Batch.inc_count batch in
    Session.incr_sequence session;
    Lwt.return_unit


  let batch_delete
        (batch:Batch.t)
        entry
        ~forced
    =
    let open Batch in
    let msg = make_batch_msg batch.session
                             batch.batch_id
                             `delete
                             entry
                             ~forced
    in
    let (ic,oc) = batch.connection in
    let session = batch.session in
    let trace = session.Session.trace in
    network_send oc msg None trace >>= fun () ->
    let () = Batch.inc_count batch in
    Session.incr_sequence session;
    Lwt.return_unit


  let make_noop session =
    let mb = set_attributes ~ko:None
                            ~db_version:None
                            ~new_version:None
                            ~forced:None
                            ~synchronization:None
                            ~maybe_tag:None
    in
    make_serialized_msg session `noop mb

  (*

    let make_p2p_push session (host,port,tls) operations =
      let open Message_p2_poperation in
      let open Message_p2_poperation_operation in
      let open Message_p2_poperation_peer in
      let manip body =
        let poperations =
          List.map
          (fun ((k:string),(nko:string option)) ->
           let pop = default_message_p2_poperation_operation () in
           pop.key <- Some k;
           pop.new_key <- nko;
           pop
          ) operations
        in
        let ppeer = default_message_p2_poperation_peer () in
        let () = ppeer.hostname <- Some host in
        let () = ppeer.port <- Some (Int32.of_int port) in
        let () = ppeer.tls <- Some tls in

        let p2pop = default_message_p2_poperation () in
        let () = p2pop.peer <- Some ppeer in
        let () = p2pop.operation <- poperations in
        let () = body.p2p_operation <- Some p2pop in
        ()
      in
      make_serialized_msg session `peer2_peerpush manip

 *)
    let noop client =
      let msg = make_noop client.session in
      let vo = None in
      _call client msg vo >>= fun (r,vo) ->
      assert (vo = None);
      let command = _parse_command r in
      let () = Session.incr_sequence client.session in
      _assert_both command `noop_response `success;
      Lwt.return_unit

    let make_instant_secure_erase session ~pin =

      let manip body
        =
        let () =
          set_attributes
            ~ko:None
            ~db_version:None
            ~new_version:None
            ~forced:None
            ~synchronization:None
            ~maybe_tag:None
            body
        in
        let pinop = default_command_pin_operation  () in
        let open Command_pin_operation in
        let () = pinop.pin_op_type <- Some `secure_erase_pinop in
        body.pin_op <- Some pinop
      in
      make_pin_auth_serialized_msg
        session
        pin `pinop manip

    let instant_secure_erase ?pin client =
      let pin = get_option "" pin in
      let msg = make_instant_secure_erase client.session ~pin in
      let vo = None in
      _call client msg vo >>= fun(r,vo) ->
      assert (vo = None);
      let command = _parse_command r in
      let () = Session.incr_sequence client.session in
      _assert_both command `pinop_response `success;
      Lwt.return_unit

    let make_download_firmware session =
      (*
        14984113
        authType: HMACAUTH
        hmacAuth {
          identity: 1
          hmac: "\323\240\'\215\267\302\246>*\335A\33461\372x;o\177\364"
        }
        commandBytes: "\n\020\010\000\030\230\361\254\314\262\361\247\341\n \0008\026\022\004\032\002(\001"

        header {
          clusterVersion: 0
          connectionID: 775357505907407000
          sequence: 0
          messageType: SETUP
        }
        body {
          setup {
            firmwareDownload: true
          }
        }

       *)

      let manip body =
        let open Command_setup in
        let setup = default_command_setup () in
        setup.firmware_download <- Some true;
        body.setup <- Some setup
      in
      make_serialized_msg
        session `setup manip


    let download_firmware client slod_data =
      let msg = make_download_firmware client.session in
      let vo = Some slod_data in
      _call client msg vo >>= fun (r, vo) ->
      assert (vo = None);
      let command = _parse_command r in
      let () = Session.incr_sequence client.session in
      _assert_both command `setup_response `success;
      Lwt.return_unit



(*






    let p2p_push session (ic,oc) peer operations =
      let msg = make_p2p_push session peer operations in
      network_send oc msg None >>= fun () ->
      network_receive ic >>= fun (r,vo) ->
      _assert_type r `peer2_peerpush_response;
      let () = incr_session session in
      let status = get_status_code r in
      let lwt_fail x = Lwt.fail(Failure x) in
      match status with
      | `success -> Lwt.return_unit
      | `invalid_status_code
      | `not_attempted
      | `hmac_failure
      | `not_authorized
      | `version_failure
      | `internal_error
      | `header_required
      | `not_found -> lwt_fail "not_found"
      | `version_mismatch -> lwt_fail "version_mismatch"
      | `service_busy -> lwt_fail "service_busy"
      | `expired -> lwt_fail "expired"
      | `data_error -> lwt_fail "data_error"
      | `perm_data_error -> lwt_fail "perm_data_error"
      | `remote_connection_error ->
         lwt_fail ("remote_connection_error: ")
      | `no_space -> lwt_fail "no_space"
      | `no_such_hmac_algorithm -> lwt_fail "no_such_hmac_algorithm"
      | `invalid_request ->
         let (int_status:int) = Obj.magic status in
         Lwt_io.printlf "x=%i\n%!" int_status >>= fun () ->
         let sm = get_status_message r in
         Lwt.fail (Failure sm)

 *)
    let make_socket_address h p = Unix.ADDR_INET(Unix.inet_addr_of_string h, p)

    let ssl_connect ctx ip port =
      Lwt_log.debug_f "ssl_connect:(%s,%i)" ip port >>= fun () ->
      let sa = Unix.ADDR_INET(Unix.inet_addr_of_string ip, port) in
      let domain = Unix.domain_of_sockaddr sa in
      let socket = Lwt_unix.socket domain Unix.SOCK_STREAM 0  in
      Lwt_unix.connect socket sa >>= fun () ->
      Lwt_log.debug_f "connected" >>= fun () ->

      (*
        Ssl.set_verify ctx
          [Ssl.Verify_peer; Ssl.Verify_fail_if_no_peer_cert]
           (Some Ssl.client_verify_callback);
           Ssl.load_verify_locations ctx ca_cert "";
       *)

      Lwt_ssl.ssl_connect socket ctx >>= fun ssl_socket ->
      Lwt_log.debug_f "ssl_connect ok" >>= fun () ->
      Lwt.return ssl_socket


    let wrap_connection ?trace ?secret ?cluster_version connection closer =
      let secret =
        match secret with
        | None -> "asdfasdf"
        | Some secret -> secret
      in
      let cluster_version =
        match cluster_version with
        | None -> 0L
        | Some cluster_version -> cluster_version
      in
      handshake secret cluster_version ?trace connection
      >>= fun session ->
      Lwt.return {session ; connection; closer}

    let make_client ?ctx ?secret ?cluster_version ?trace ~ip ~port =
      let sa = make_socket_address ip port in
      match ctx with
      | None ->
         Lwt_io.open_connection sa >>= fun connection ->
         let closer () =
           Lwt.catch
             (fun () ->
               let ic,oc = connection in
               Lwt_io.close ic >>= fun () ->
               Lwt_io.close oc >>= fun () ->
               Lwt.return_unit
             )
             (fun exn -> Lwt_log.info ~exn "during close")
         in
         wrap_connection ?secret ?cluster_version ?trace connection closer

      | Some ctx ->
         ssl_connect ctx ip port >>= fun ssl_socket ->
         let ic = Lwt_ssl.in_channel_of_descr ssl_socket
         and oc = Lwt_ssl.out_channel_of_descr ssl_socket
         in
         Lwt_log.debug_f "have streams" >>= fun () ->
         let connection = (ic,oc) in
         let closer () =
           Lwt.catch
             (fun () -> Lwt_ssl.close ssl_socket)
             (fun exn -> Lwt_log.info ~exn "during close ")
         in
         wrap_connection ?trace ?secret ?cluster_version connection closer

    let dispose t = t.closer ()

    let get_session t  = t.session



    let with_client ?ctx ?secret ?cluster_version ?trace ~ip ~port  f =
      make_client ?ctx ?secret ?cluster_version ?trace ~ip ~port
      >>= fun client ->
      Lwt.finalize
        (fun () -> f client)
        (fun () -> dispose client)
  end
