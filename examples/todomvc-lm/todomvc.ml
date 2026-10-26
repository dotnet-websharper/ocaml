open WebSharper_JavaScript
open WebSharper_Json
open WebSharper_UI
open WebSharper_UI.Html
open WebSharper_Server

(* `open WebSharper_JavaScript` shadows the OCaml `String`; keep it. *)
module String = Stdlib.String
module JsStorage = WebSharper_JavaScript.Storage

(* `ListModel.updateBy`/`updateAll` take an *F#* `option` (WebSharper's
   `FSharpOption`), which is a different type from OCaml's; the binding's
   constructors are the way to build one. *)
module FOpt = WebSharper_StdLib.FSharpOption

(* The official TodoMVC template (a full HTML5 document) with WebSharper.UI
   templating attributes added in place; the row is a nested `<template
   name="todoItem">` (a submodule). The server renders it with `keepUnfilled`
   (a skeleton of `ws-*` markers) and the client binds it (`bind`). *)
module TodoPage = [%template "views/todomvc.html"]

(* --- model ---------------------------------------------------------------- *)

type todo = { id : int; title : string; completed : bool }
type filter = All | Active | Completed

(* The rows live in a WebSharper.UI **`ListModel`**, a reactive *keyed* collection
   (F# `ListModel<'T,'K>`; in OCaml the key comes first, `('k, 't) t`). The key
   is the `id`, so updating or removing a row targets exactly that row — the
   others keep their identity — and every mutation drives the bound view. *)
type todo_model = (int, todo) ListModel.t

(* What the template's holes are filled from: the current rows (a snapshot of
   the model), the row being edited and the filter. `ListModel`'s own
   `view`/`map` members return an `IEnumerable`, which these OCaml bindings
   cannot consume, so the rows are read off the model's backing `Var`. *)
type model = { todos : todo list; editing : int option; filter : filter }

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
  let save (ts : todo list) =
    JsStorage.setItem (storage ()) key (encode ts)
  in

  (* --- state: the rows (`ListModel`, keyed by `id`), the edit, the filter --- *)

  let todos : todo_model = ListModel.create (fun (t : todo) -> t.id) (load ()) in
  let editing : int option Var.t = Var.create None in

  (* A snapshot of the rows — `ListModel.iter` visits each item in order. Used
     for persistence and for the next free `id`. *)
  let rows () : todo list =
    let acc = ref [] in
    ListModel.iter todos (fun t -> acc := t :: !acc);
    List.rev !acc
  in
  let persist () = save (rows ()) in

  (* The reactive rows: the model's backing `Var` holds the items, so mapping it
     gives a `View` the template holes can bind. *)
  let rows_v : todo list View.t =
    View.map (fun (a : todo array) -> Stdlib.Array.to_list a) (Var.view (ListModel.var todos))
  in

  (* --- routing: `#/`, `#/active`, `#/completed` --------------------------- *)

  (* A WebSharper hash router; `installHash` wires `hashchange` + anchor clicks
     and gives a reactive `Var<filter>` (server-side it just holds the default). *)
  let filter_router : filter WebSharper_Sitelets.Router.t =
    WebSharper_Sitelets.RouterModule.table
      [ (All, ""); (Active, "active"); (Completed, "completed") ]
  in
  let filter_var : filter Var.t = Router.installHash All filter_router in

  let view : model View.t =
    View.map3
      (fun ts ed f -> { todos = ts; editing = ed; filter = f })
      rows_v (Var.view editing) (Var.view filter_var)
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

  (* --- mutations: each one goes through the `ListModel`, then re-persists --- *)

  let add (v : string Var.t) =
    let title = String.trim (Var.get v) in
    if title <> "" then begin
      let next_id = List.fold_left (fun m t -> max m t.id) 0 (rows ()) + 1 in
      Var.set v "";
      ListModel.append todos { id = next_id; title; completed = false };
      persist ()
    end
  in
  let toggle id =
    ListModel.updateBy todos (fun t -> FOpt.some { t with completed = not t.completed }) id;
    persist ()
  in
  let destroy id =
    ListModel.removeByKey todos id;
    persist ()
  in
  let clear_completed () =
    ListModel.removeBy todos (fun t -> t.completed);
    persist ()
  in
  let toggle_all () =
    let ts = rows () in
    let all_done = ts <> [] && List.for_all (fun t -> t.completed) ts in
    let target = not all_done in
    ListModel.updateAll todos (fun t -> FOpt.some { t with completed = target });
    persist ()
  in
  let start_edit id = Var.set editing (Some id) in
  let stop_edit () = Var.set editing None in
  let commit_edit id (v : string Var.t) =
    match Var.get editing with
    | Some eid when eid = id ->
        let title = String.trim (Var.get v) in
        (* An empty title destroys the row (a keyed removal, not a list filter). *)
        if title = "" then ListModel.removeByKey todos id
        else ListModel.updateBy todos (fun t -> FOpt.some { t with title }) id;
        persist ();
        Var.set editing None
    | _ -> ()
  in

  (* --- view (the template's holes) ---------------------------------------- *)

  let render_item (m : model) (t : todo) =
    let being_edited = m.editing = Some t.id in
    let inst = TodoPage.TodoItem.create () in
    Var.set inst.vars.editText t.title;
    inst
    |> TodoPage.TodoItem.itemClass
        ((if t.completed then "completed " else "") ^ (if being_edited then "editing" else ""))
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
     each mutation re-renders only the affected parts. *)
  let visible (m : model) t =
    match m.filter with All -> true | Active -> not t.completed | Completed -> t.completed
  in
  let remaining (m : model) = List.length (List.filter (fun t -> not t.completed) m.todos) in
  let selected f (m : model) = if f = m.filter then "selected" else "" in
  let hidden_if b = if b then "hidden" else "" in
  let cls f = View.map f view in
  let initial = { todos = rows (); editing = Var.get editing; filter = Var.get filter_var } in

  let inst =
    TodoPage.create ()
    |> TodoPage.newTodoKey_withModel (fun e ->
           if is_enter e.event then add e.vars.newTodo;
           Var.set e.vars.newTodo "")
    |> TodoPage.newTodoFocus focus
    |> TodoPage.mainClass_view (cls (fun m -> hidden_if (m.todos = [])))
    |> TodoPage.footerClass_view (cls (fun m -> hidden_if (m.todos = [])))
    |> TodoPage.toggleAttr
         (if initial.todos <> [] && remaining initial = 0 then Attr.create "checked" "checked"
          else Attr.empty ())
    |> TodoPage.toggleAll (fun _ _ -> toggle_all ())
    |> TodoPage.todos
         (Doc.bindView
            (fun m -> Doc.concat (List.map (render_item m) (List.filter (visible m) m.todos)))
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
         (cls (fun m -> hidden_if (List.length m.todos = remaining m)))
    |> TodoPage.clearCompleted (fun _ _ -> clear_completed ())
  in

  (* --- start -------------------------------------------------------------- *)

  (* Bind the server-rendered document to the reactive instance. The filter
     links are plain `<a href="#/…">`, intercepted by the hash router. *)
  TodoPage.bind inst
