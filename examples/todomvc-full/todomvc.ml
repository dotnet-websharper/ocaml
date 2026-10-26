open WebSharper_JavaScript
open WebSharper_Json
open WebSharper_UI
open WebSharper_UI.Html
open WebSharper_Server

(* `open WebSharper_JavaScript` shadows the OCaml `String`; keep it. *)
module String = Stdlib.String
module JsStorage = WebSharper_JavaScript.Storage

(* The official TodoMVC template (a full HTML5 document) with WebSharper.UI
   templating attributes added in place; the row is a nested `<template
   name="todoItem">` (a submodule). The server renders it with `keepUnfilled`
   (a skeleton of `ws-*` markers) and the client binds it (`bind`). *)
module TodoPage = [%template "views/todomvc.html"]

(* --- model ---------------------------------------------------------------- *)

type todo = { id : int; title : string; completed : bool }
type filter = All | Active | Completed

(* The filter lives in a `Var` owned by the hash router (below), not in `state`. *)
type state = { todos : todo list; editing : int option }
type model = state * filter

(* --- server: server-render the template skeleton; the client binds it ------ *)

type endpoint = Home [@endpoint "GET /"]

let[@website] main =
  Sitelet.infer (fun (_ : endpoint context) _ ->
    Content.page ~title:"TodoMVC · wsocaml"
      ~head:"<link rel=\"stylesheet\" href=\"/css/app.css\">"
      [ TodoPage.doc ~keepUnfilled:true (TodoPage.create ()) ])

(* Everything below lives in a single top-level `let ()`: it is dropped from the
   native server (a non-`Ppat_var` binding) and runs only in the client bundle. *)
let () =
  let key = "todos-ocaml" in
  let storage () = Window.localStorage (Window.self ()) in

  (* --- persistence: typed JSON (`[{ "id", "title", "completed" }, …]`) ------
     `WebSharper_Json` describes `todo list` from its OCaml type and marshals it
     in the same external representation `[@rpc]`/`[@export]` use, so the stored
     payload is unchanged. *)
  let load () =
    (* `getItem` is `null` when the key is absent; a malformed/empty payload
       should start from an empty list, not fail at startup. *)
    try (decode (JsStorage.getItem (storage ()) key) : todo list)
    with _ -> []
  in
  let rec save (ts : todo list) =
    JsStorage.setItem (storage ()) key (encode ts)
  in

  (* --- state -------------------------------------------------------------- *)

  let state = Var.create { todos = load (); editing = None } in
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
        commit { todos; editing = None }
    | _ -> ()
  in
  (* --- routing: `#/`, `#/active`, `#/completed` --------------------------- *)

  (* A WebSharper hash router; `installHash` wires `hashchange` + anchor clicks
     and gives a reactive `Var<filter>` (server-side it just holds the default). *)
  let filter_router : filter WebSharper_Sitelets.Router.t =
    WebSharper_Sitelets.RouterModule.table
      [ (All, ""); (Active, "active"); (Completed, "completed") ]
  in
  let filter_var : filter Var.t = Router.installHash All filter_router in

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
    let inst = TodoPage.TodoItem.create () in
    Var.set inst.vars.editText t.title;
    inst
    |> TodoPage.TodoItem.itemClass
        ((if t.completed then "completed " else "") ^ (if editing then "editing" else ""))
    |> TodoPage.TodoItem.title t.title
    |> TodoPage.TodoItem.toggleAttr
        (if t.completed then Attr.create "checked" "checked" else Attr.empty ())
    |> TodoPage.TodoItem.toggle (fun _ _ -> toggle t.id)
    |> TodoPage.TodoItem.editStart (fun _ _ -> start_edit t.id)
    |> TodoPage.TodoItem.destroy (fun _ _ -> destroy t.id)
    |> TodoPage.TodoItem.editCommit_withModel (fun e -> commit_edit t.id e.vars.editText)
    |> TodoPage.TodoItem.editKey_withModel (fun e ->
        if is_enter e.event then commit_edit t.id e.vars.editText
        else if is_escape e.event then stop_edit ())
    |> TodoPage.TodoItem.doc
  in

  (* The document is server-rendered once (a skeleton of `ws-*` markers) and then
     bound on the client with `bind`. The reactive holes are `View`-driven, so
     each state change re-renders only the affected parts. *)
  let view : model View.t =
    View.map2 (fun s f -> (s, f)) (Var.view state) (Var.view filter_var)
  in
  let visible (_, f) t =
    match f with All -> true | Active -> not t.completed | Completed -> t.completed
  in
  let remaining ((s, _) : model) = List.length (List.filter (fun t -> not t.completed) s.todos) in
  let selected f (_, f') = if f = f' then "selected" else "" in
  let hidden_if b = if b then "hidden" else "" in
  let cls f = View.map f view in
  let initial = (Var.get state, Var.get filter_var) in

  let inst =
    TodoPage.create ()
    |> TodoPage.newTodoKey_withModel (fun e -> if is_enter e.event then add e.vars.newTodo; Var.set e.vars.newTodo "")
    |> TodoPage.newTodoFocus focus
    |> TodoPage.mainClass_view (cls (fun (s, _) -> hidden_if (s.todos = [])))
    |> TodoPage.footerClass_view (cls (fun (s, _) -> hidden_if (s.todos = [])))
    |> TodoPage.toggleAttr
         (if (fst initial).todos <> [] && remaining initial = 0 then Attr.create "checked" "checked"
          else Attr.empty ())
    |> TodoPage.toggleAll (fun _ _ -> toggle_all ())
    |> TodoPage.todos
         (Doc.bindView
            (fun m -> Doc.concat (List.map (render_item (fst m)) (List.filter (visible m) (fst m).todos)))
            view)
    |> TodoPage.count
         (Doc.bindView
            (fun m ->
              let n = remaining m in
              Doc.concat
                [ strong [] [ Doc.text (string_of_int n) ];
                  Doc.text (" " ^ (if n = 1 then "item" else "items") ^ " left") ])
            view)
    |> TodoPage.allClass_view (cls (selected All))
    |> TodoPage.activeClass_view (cls (selected Active))
    |> TodoPage.completedClass_view (cls (selected Completed))
    |> TodoPage.clearClass_view
         (cls (fun m -> hidden_if (List.length (fst m).todos = remaining m)))
    |> TodoPage.clearCompleted (fun _ _ -> clear_completed ())
  in

  (* --- start -------------------------------------------------------------- *)

  (* Bind the server-rendered document to the reactive instance. The filter
     links are plain `<a href="#/…">`, intercepted by the hash router. *)
  TodoPage.bind inst
