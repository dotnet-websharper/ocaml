open WebSharper_JavaScript
open WebSharper_UI
open WebSharper_UI.Html
open WebSharper_Server

(* `open WebSharper_JavaScript` shadows the OCaml `String`; keep it. *)
module String = Stdlib.String

(* WS.UI template (adapted from the TodoMVC app template). Nested templates
   (`body`, `todoItem`) are submodules; the codegen compiles each to its own
   source (see docs/templates.md). *)
module Tmpl = [%template "views/todomvc.html"]

(* --- model ---------------------------------------------------------------- *)

type todo = { id : int; title : string; completed : bool }
type filter = All | Active | Completed
type state = { todos : todo list; editing : int option; filter : filter }

(* --- server: serve the shell; the app runs client-side -------------------- *)

type endpoint = Home [@endpoint "GET /"]

let[@website] main =
  Sitelet.infer (fun (_ : endpoint context) _ ->
    Content.page ~title:"TodoMVC · wsocaml"
      ~head:"<link rel=\"stylesheet\" href=\"/css/app.css\">"
      [ div [ Attr.create "id" "root" ] [] ])

(* Everything below lives in a single top-level `let ()`: it is dropped from the
   native server (a non-`Ppat_var` binding) and runs only in the client bundle. *)
let () =
  let key = "todos-ocaml" in
  let storage () = Window.localStorage (Window.self ()) in

  (* --- persistence: `[{ "id", "title", "completed" }, …]` ------------------ *)

  let json_escape s =
    let b = Buffer.create (String.length s) in
    String.iter
      (fun c ->
        match c with
        | '"' -> Buffer.add_string b "\\\""
        | '\\' -> Buffer.add_string b "\\\\"
        | '\n' -> Buffer.add_string b "\\n"
        | '\r' -> Buffer.add_string b "\\r"
        | '\t' -> Buffer.add_string b "\\t"
        | c when Char.code c < 0x20 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
        | c -> Buffer.add_char b c)
      s;
    Buffer.contents b
  in
  let encode (ts : todo list) =
    "["
    ^ String.concat ","
        (List.map
           (fun t ->
             Printf.sprintf "{\"id\":%d,\"title\":\"%s\",\"completed\":%b}" t.id
               (json_escape t.title) t.completed)
           ts)
    ^ "]"
  in
  let decode (s : string) : todo list =
    if String.trim s = "" then []
    else
      let arr : Js.t = JSON.parse s in
      let n : int = Js.to_js (Js.get arr "length") in
      List.init n (fun i ->
          let o : Js.t = Js.get_index arr i in
          { id = (Js.to_js (Js.get o "id") : int);
            title = (Js.to_js (Js.get o "title") : string);
            completed = (Js.to_js (Js.get o "completed") : bool) })
  in
  let load () =
    try decode (WebSharper_JavaScript.Storage.getItem (storage ()) key) with _ -> []
  in
  let save ts = WebSharper_JavaScript.Storage.setItem (storage ()) key (encode ts) in

  (* --- state -------------------------------------------------------------- *)

  let state = Var.create { todos = load (); editing = None; filter = All } in
  let commit s =
    Var.set state s;
    save s.todos
  in

  (* --- mutations ---------------------------------------------------------- *)

  let add (v : string Var.t) =
    let title = String.trim (Var.get v) in
    if title <> "" then begin
      let s = Var.get state in
      let next_id = List.fold_left (fun m t -> max m t.id) 0 s.todos + 1 in
      Var.set v "";
      commit { s with todos = s.todos @ [ { id = next_id; title; completed = false } ] }
    end
  in
  let edit_todo id f =
    let s = Var.get state in
    commit { s with todos = List.map (fun t -> if t.id = id then f t else t) s.todos }
  in
  let toggle id = edit_todo id (fun t -> { t with completed = not t.completed }) in
  let destroy id =
    let s = Var.get state in
    commit { s with todos = List.filter (fun t -> t.id <> id) s.todos }
  in
  let clear_completed () =
    let s = Var.get state in
    commit { s with todos = List.filter (fun t -> not t.completed) s.todos }
  in
  let toggle_all () =
    let s = Var.get state in
    let all_done = s.todos <> [] && List.for_all (fun t -> t.completed) s.todos in
    let target = not all_done in
    commit { s with todos = List.map (fun t -> { t with completed = target }) s.todos }
  in
  let start_edit id =
    let s = Var.get state in
    commit { s with editing = Some id }
  in
  let stop_edit () =
    let s = Var.get state in
    commit { s with editing = None }
  in
  let commit_edit id (v : string Var.t) =
    let s = Var.get state in
    match s.editing with
    | Some eid when eid = id ->
        let title = String.trim (Var.get v) in
        let todos =
          if title = "" then List.filter (fun t -> t.id <> id) s.todos
          else List.map (fun t -> if t.id = id then { t with title } else t) s.todos
        in
        commit { s with todos; editing = None }
    | _ -> ()
  in
  let set_filter f =
    let s = Var.get state in
    if s.filter <> f then commit { s with filter = f }
  in

  (* --- helpers ------------------------------------------------------------ *)

  let is_enter (ev : KeyboardEvent.t) =
    KeyboardEvent.key ev = "Enter" || KeyboardEvent.keyCode ev = 13 || KeyboardEvent.which ev = 13
  in
  let is_escape (ev : KeyboardEvent.t) =
    KeyboardEvent.key ev = "Escape" || KeyboardEvent.key ev = "Esc"
    || KeyboardEvent.keyCode ev = 27 || KeyboardEvent.which ev = 27
  in
  let focus (el : Element.t) =
    let el : HTMLElement.t = Js.to_js (Js.of_js el) in
    HTMLElement.focus el
  in

  (* --- view (the template's holes) ---------------------------------------- *)

  let render_item (s : state) (t : todo) =
    let editing = s.editing = Some t.id in
    let inst = Tmpl.TodoItem.create () in
    Var.set inst.vars.editText t.title;
    inst
    |> Tmpl.TodoItem.itemClass
         ((if t.completed then "completed " else "") ^ (if editing then "editing" else ""))
    |> Tmpl.TodoItem.title t.title
    |> Tmpl.TodoItem.toggleAttr
         (if t.completed then Attr.create "checked" "checked" else Attr.empty ())
    |> Tmpl.TodoItem.toggle (fun _ _ -> toggle t.id)
    |> Tmpl.TodoItem.editStart (fun _ _ -> start_edit t.id)
    |> Tmpl.TodoItem.destroy (fun _ _ -> destroy t.id)
    |> Tmpl.TodoItem.editCommit_withModel (fun e -> commit_edit t.id e.vars.editText)
    |> Tmpl.TodoItem.editKey_withModel (fun e ->
           if is_enter e.event then commit_edit t.id e.vars.editText
           else if is_escape e.event then stop_edit ())
    |> Tmpl.TodoItem.doc
  in

  let render (s : state) =
    let remaining = List.length (List.filter (fun t -> not t.completed) s.todos) in
    let completed = List.length s.todos - remaining in
    let empty = s.todos = [] in
    let visible t =
      match s.filter with All -> true | Active -> not t.completed | Completed -> t.completed
    in
    Tmpl.create ()
    |> Tmpl.newTodoKey_withModel (fun e -> if is_enter e.event then add e.vars.newTodo)
    |> Tmpl.newTodoFocus focus
    |> Tmpl.mainClass (if empty then "hidden" else "")
    |> Tmpl.footerClass (if empty then "hidden" else "")
    |> Tmpl.toggleAttr
         (if (not empty) && remaining = 0 then Attr.create "checked" "checked" else Attr.empty ())
    |> Tmpl.toggleAll (fun _ _ -> toggle_all ())
    |> Tmpl.todos (Doc.concat (List.map (render_item s) (List.filter visible s.todos)))
    |> Tmpl.count
         (Doc.concat
            [ strong [] [ Doc.text (string_of_int remaining) ];
              Doc.text (" " ^ (if remaining = 1 then "item" else "items") ^ " left") ])
    |> Tmpl.allClass (if s.filter = All then "selected" else "")
    |> Tmpl.activeClass (if s.filter = Active then "selected" else "")
    |> Tmpl.completedClass (if s.filter = Completed then "selected" else "")
    |> Tmpl.filterAll (fun _ _ -> set_filter All)
    |> Tmpl.filterActive (fun _ _ -> set_filter Active)
    |> Tmpl.filterCompleted (fun _ _ -> set_filter Completed)
    |> Tmpl.clearClass (if completed > 0 then "" else "hidden")
    |> Tmpl.clearCompleted (fun _ _ -> clear_completed ())
    |> Tmpl.doc
  in

  (* --- start -------------------------------------------------------------- *)

  let filter_of_hash () =
    match Location.hash (Window.location (Window.self ())) with
    | "#/active" -> Active
    | "#/completed" -> Completed
    | _ -> All
  in
  Var.update state (fun s -> { s with filter = filter_of_hash () });

  (* Not a tail call: a raw DOM listener must drive the trampoline itself. *)
  EventTarget.addEventListener (Window.self ()) "hashchange"
    (Js.of_js (fun (_ : WebSharper_JavaScript.Event.t) ->
         Var.update state (fun s -> { s with filter = filter_of_hash () });
         ()));

  Doc.runById "root" (Doc.bindView render (Var.view state))
