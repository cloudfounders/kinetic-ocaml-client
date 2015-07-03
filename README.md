Kinetic OCaml Client
====================
This is an OCaml client for [Seagate's Kinetic drives](https://developers.seagate.com/display/KV/Kinetic+Open+Storage+Documentation+Wiki).
Currently, it uses protocol version 3.0.6.
This is corresponds with version 0.8.0.4 of the Java Simulator or
Kinetic drive firmware version 3.0.1


Installation
============
In order to build the client, you need to have some OCaml libraries present.
In concreto, you need:
  - Lwt
  - piqi
  - Cryptokit


If you have these, you can compile everything with:

```
$> make
```

You can install the library with:


```
$> make install-lib
```


Once you have the library installed, you just add `true:package(kinetic-client) to your ocamlbuild _tags file.

Usage
=====

The API is defined in [kinetic.mli](src/kinetic.mli)

typically you'd do something like:

```OCaml
    let sa = make_socket_address "127.0.0.1" 8123 in
    let secret = "...." in
    let cluster_version = ... in
    let session = Kinetic.make_session ....in
    Lwt_io.with_connection sa
        (fun conn ->
         Kinetic.handshake secret cluster_version conn >>= fun session ->
         ...
         Kinetic.put session conn
             "the_key" (Some "the value")
             ~db_version:None ~new_version:None
             ~forced:true
             ~synchronization:(Some Kinetic.WRITEBACK)
             >>= fun () ->
         ...
        )

```

Remarks
=======

Protocol?
---------

There is a rather stable `protocol`
defined in Seagate's [kinetic-protocol](https://github.com/Seagate/kinetic-protocol) which defines the serialization for valid messages. The protocol itself is rather implicitly defined by the Kinetic Simulator, and the interpretation of what comprises an acceptable client/server conversation varies between Simulator releases.
All this to say that even if both client and server state they support protocol version X, they still might not be able to talk to each other. YMMV

Todo
----
 - We only catered for our own needs, so feature support is rather limited.
   (we welcome pull requests ;) )
 - the API feels heavy, because it's a direct translation of the messages
   into RPC. Once the protocol stabilizes, we should move into something
   more elegant.

Have fun,

   The CloudFounders team
