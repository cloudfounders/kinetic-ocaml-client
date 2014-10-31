Kinetic OCaml Client
====================
This is an OCaml client for Seagate's Kinetic drives. Currently, it uses protocol version 2.0.4, which is what our drives speaks.

- [ ] Also support 3.X protocol
- [ ] use 4.0.2 Bytes iso strings for buffers (depends on piqi)
- [ ] opam installable


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
    let session = Kinetic.make_session ....in
    Lwt_io.with_connection
      sa
      (fun conn ->
       ...
       Kinetic.set session conn key (Some value) >>= fun () ->
       ...
      )

    ````


Have fun,
