open Lwt.Infix
module Log = Solver_api.Solver.Log
module Store = Git_unix.Store

let clone_path = "opam-repository"

let open_store () =
  let path = Fpath.v clone_path in
  Git_unix.Store.v ~dotgit:path path >|= function
  | Ok x -> x
  | Error e ->
      Fmt.failwith "Failed to open opam-repository: %a" Store.pp_error e

let clone () =
  match Unix.lstat clone_path with
  | Unix.{ st_kind = S_DIR; _ } -> Lwt.return_unit
  | _ -> Fmt.failwith "%S is not a directory!" clone_path
  | exception Unix.Unix_error (Unix.ENOENT, _, "opam-repository") ->
      Process.exec
        ( "",
          [|
            "git";
            "clone";
            "--bare";
            "https://github.com/ocaml/opam-repository.git";
            clone_path;
          |] )

(** * TODO: Find the oldest commit that touches all the paths. Should find the
    most recent commit backwards `from` that have touched the paths. Process all
    the paths and check using `OpamFile.OPAM.effectively_equal` to see whether
    Resolve for a packages revdeps.

    Don't want to scope on opam_repository *)
let oldest_commit_with ~log ~from pkgs =
  let from = Store.Hash.to_hex from in
  let paths =
    pkgs
    |> List.map (fun pkg ->
           let name = OpamPackage.name_to_string pkg in
           let version = OpamPackage.version_to_string pkg in
           Printf.sprintf "packages/%s/%s.%s" name name version)
  in
  (* git -C path log -n 1 --format=format:%H from -- paths *)
  let cmd =
    "git"
    :: "-C"
    :: clone_path
    :: "log"
    :: "-n"
    :: "1"
    :: "--format=format:%H"
    :: from
    :: "--"
    :: paths
  in
  Log.info log "oldest_commit_with %a" (Fmt.list ~sep:Fmt.sp Fmt.string) cmd;
  let cmd = ("", Array.of_list cmd) in
  Process.pread cmd >|= String.trim

let fetch () =
  Process.exec ("", [| "git"; "-C"; clone_path; "fetch"; "origin" |])
