(**
 * Copyright (c) 2013-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the "flow" directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *
 *)

type position = {
  line: int;
  column: int;
  offset: int;
}

type filename =
  | LibFile of string
  | SourceFile of string
  | JsonFile of string
  (* A resource that might get required, like .css, .jpg, etc. We don't parse
     these, just check that they exist *)
  | ResourceFile of string
  | Builtins

type t = {
  source: filename option;
  start: position;
  _end: position;
}

let none = {
  source = None;
  start = { line = 0; column = 0; offset = 0; };
  _end = { line = 0; column = 0; offset = 0; };
}

let btwn loc1 loc2 = {
  source = loc1.source;
  start = loc1.start;
  _end = loc2._end;
}

let btwn_exclusive loc1 loc2 = {
  source = loc1.source;
  start = loc1._end;
  _end = loc2.start;
}

let string_of_filename = function
  | LibFile x | SourceFile x | JsonFile x | ResourceFile x -> x
  | Builtins -> "(global)"

(* Returns the position immediately before the start of the given loc. If the
   given loc is at the beginning of a line, return the position of the first
   char on the same line. *)
let char_before loc =
  let start =
    let { line; column; offset } = loc.start in
    let column, offset = if column > 0
    then column - 1, offset - 1
    else column, offset in
    { line; column; offset }
  in
  let _end = loc.start in
  { loc with start; _end }

(* Returns the location of the first character in the given loc. Not accurate if the
 * first line is a newline character, but is still consistent with loc orderings. *)
let first_char loc =
  let start = loc.start in
  let _end = {start with column = start.column + 1; offset = start.offset + 1} in
  {loc with _end}

let source_cmp =
  (* builtins, then libs, then source and json files at the same priority since
     JSON files are basically source files. We don't actually read resource
     files so they come last *)
  let order_of_filename = function
  | Builtins -> 1
  | LibFile _ -> 2
  | SourceFile _ -> 3
  | JsonFile _ -> 3
  | ResourceFile _ -> 4
  in
  fun a b -> match a, b with
  | Some _, None -> -1
  | None, Some _ -> 1
  | None, None -> 0
  | Some fn1, Some fn2 ->
    let k = (order_of_filename fn1) - (order_of_filename fn2) in
    if k <> 0 then k
    else String.compare (string_of_filename fn1) (string_of_filename fn2)

let pos_cmp a b =
  let k = a.line - b.line in if k = 0 then a.column - b.column else k

(**
 * If `a` spans (completely contains) `b`, then returns 0.
 * If `b` starts before `a` (even if it ends inside), returns < 0.
 * If `b` ends after `a` (even if it starts inside), returns > 0.
 *)
let span_compare a b =
  let k = source_cmp a.source b.source in
  if k = 0 then
    let k = pos_cmp a.start b.start in
    if k <= 0 then
      let k = pos_cmp a._end b._end in
      if k >= 0 then 0 else -1
    else 1
  else k

(* Returns true if loc1 entirely overlaps loc2 *)
let contains loc1 loc2 = span_compare loc1 loc2 = 0

let compare loc1 loc2 =
  let k = source_cmp loc1.source loc2.source in
  if k = 0 then
    let k = pos_cmp loc1.start loc2.start in
    if k = 0 then pos_cmp loc1._end loc2._end
    else k
  else k

(**
 * This is mostly useful for debugging purposes.
 * Please don't dead-code delete this!
 *)
let to_string ?(include_source=false) loc =
  let source =
    if include_source
    then Printf.sprintf "%S: " (
      match loc.source with
      | Some src -> string_of_filename src
      | None -> "<NONE>"
    ) else ""
  in
  let pos = Printf.sprintf "(%d, %d) to (%d, %d)"
    loc.start.line
    loc.start.column
    loc._end.line
    loc._end.column
  in
  source ^ pos

let source loc = loc.source

let source_is_lib_file = function
| LibFile _ -> true
| Builtins -> true
| SourceFile _ -> false
| JsonFile _ -> false
| ResourceFile _ -> false

let filename_map f = function
  | LibFile filename -> LibFile (f filename)
  | SourceFile filename -> SourceFile (f filename)
  | JsonFile filename -> JsonFile (f filename)
  | ResourceFile filename -> ResourceFile (f filename)
  | Builtins -> Builtins

let filename_exists f = function
  | LibFile filename
  | SourceFile filename
  | JsonFile filename
  | ResourceFile filename -> f filename
  | Builtins -> false

let check_suffix filename suffix =
  filename_exists (fun fn -> Filename.check_suffix fn suffix) filename

let chop_suffix filename suffix =
  filename_map (fun fn -> Filename.chop_suffix fn suffix) filename

let with_suffix filename suffix =
  filename_map (fun fn -> fn ^ suffix) filename

(* implements OrderedType and SharedMem.UserKeyType *)
module FilenameKey = struct
  type t = filename
  let to_string = string_of_filename
  let compare = Pervasives.compare
end

module LocSet = Set.Make(struct
  type nonrec t = t
  let compare = compare
end)
