(* Native, server-side shadow of the `WebSharper.Sitelets` hash router.

   On the server, routes are handled by the sitelet (`[@endpoint]` +
   `Sitelet.infer`) and `ctx.link`, so nothing here performs real hashing: the
   module exists so that app source which builds a hash router (for the client's
   `WebSharper_UI.Router.installHash`) also typechecks against the native shadow.
   `WebSharper_UI.Router.installHash` itself is a no-op server-side.

   The module/type/function names mirror the generated `websharper-sitelets`
   binding: `Router` is the generic router (`WebSharper.Sitelets.Router<'T>`),
   `RouterMatcher` the non-generic route matcher. The router model follows
   WebSharper's: a router yields *all* matches (with the segments each left
   over), and `Route`/`Link` treat a route as a match only when it consumes the
   whole path. *)

let rec drop_prefix pre s =
  match (pre, s) with
  | [], rest -> Some rest
  | p :: ps, x :: xs when p = x -> drop_prefix ps xs
  | _ -> None

module Route = struct
  type t = { segments : string list }

  let split_segments (s : string) =
    String.split_on_char '/' s |> List.filter (fun x -> x <> "")

  (* `Route.FromHash`: the fragment without a leading `#`, split into segments. *)
  let from_hash (h : string) : t =
    let h =
      if String.length h > 0 && h.[0] = '#' then String.sub h 1 (String.length h - 1) else h
    in
    { segments = split_segments h }

  let to_link (r : t) = "/" ^ String.concat "/" r.segments
end

module RouterMatcher = struct
  (* A non-generic router: matches (and consumes) a fixed path. *)
  type t = { segments : string list; match_ : string list -> string list option }

  let empty : t = { segments = []; match_ = (fun s -> Some s) }

  let from_string (s : string) : t =
    let segments = Route.split_segments s in
    { segments; match_ = (fun rest -> drop_prefix segments rest) }

  let fromString = from_string
end

module Router = struct
  (* [link] renders a value to path segments; [parse] returns every match for a
     segment list paired with the segments it left over. *)
  type 'a t = { link : 'a -> string list; parse : string list -> (string list * 'a) list }
end

module RouterModule = struct
  let map_to (v : 'a) (r : RouterMatcher.t) : 'a Router.t =
    {
      Router.link = (fun x -> if x = v then r.RouterMatcher.segments else []);
      parse =
        (fun segs ->
          match r.RouterMatcher.match_ segs with
          | Some rest -> [ (rest, v) ]
          | None -> []);
    }

  let mapTo = map_to

  let empty () : 'a Router.t = { Router.link = (fun _ -> []); parse = (fun _ -> []) }

  let sum (rs : 'a Router.t list) : 'a Router.t =
    {
      Router.link =
        (fun v ->
          match
            List.find_map
              (fun (r : 'a Router.t) -> match r.Router.link v with [] -> None | l -> Some l)
              rs
          with
          | Some l -> l
          | None -> []);
      parse = (fun segs -> List.concat_map (fun (r : 'a Router.t) -> r.Router.parse segs) rs);
    }

  let table (mapping : ('a * string) list) : 'a Router.t =
    sum (List.map (fun (v, s) -> map_to v (RouterMatcher.from_string s)) mapping)

  let single (endpoint : 'a) (route : string) : 'a Router.t =
    map_to endpoint (RouterMatcher.from_string route)

  let filter (predicate : 'a -> bool) (r : 'a Router.t) : 'a Router.t =
    {
      Router.link = (fun v -> if predicate v then r.Router.link v else []);
      parse = (fun segs -> List.filter (fun (_, v) -> predicate v) (r.Router.parse segs));
    }

  let delay (get_router : unit -> 'a Router.t) : 'a Router.t =
    {
      Router.link = (fun v -> (get_router ()).Router.link v);
      parse = (fun segs -> (get_router ()).Router.parse segs);
    }

  let shift (prefix : string) (r : 'a Router.t) : 'a Router.t =
    let pre = Route.split_segments prefix in
    {
      Router.link = (fun v -> pre @ r.Router.link v);
      parse =
        (fun segs ->
          match drop_prefix pre segs with
          | Some rest -> r.Router.parse rest
          | None -> []);
    }

  let map (decode : 'a -> 'b) (encode : 'b -> 'a) (r : 'a Router.t) : 'b Router.t =
    {
      Router.link = (fun v -> r.Router.link (encode v));
      parse = (fun segs -> List.map (fun (rest, a) -> (rest, decode a)) (r.Router.parse segs));
    }

  (* Type-changing casts: the server never links these, so an always-empty router
     is enough to keep shared source typechecking. *)
  let cleared () : 'b Router.t = { Router.link = (fun _ -> []); parse = (fun _ -> []) }
  let cast (_ : 'a Router.t) : 'b Router.t = cleared ()
  let box (_ : 'a Router.t) : Js.t Router.t = cleared ()
  let unbox (_ : Js.t Router.t) : 'a Router.t = cleared ()
  let array (_ : 'a Router.t) : ('a array) Router.t = cleared ()
  let list (_ : 'a Router.t) : ('a list) Router.t = cleared ()
  let option (_ : 'a Router.t) : ('a option) Router.t = cleared ()
  let formData (r : 'a Router.t) : 'a Router.t = r

  let parse (r : 'a Router.t) (path : Route.t) : 'a option =
    r.Router.parse path.Route.segments
    |> List.find_map (fun (rest, v) -> if rest = [] then Some v else None)

  let write (r : 'a Router.t) (v : 'a) : Route.t option =
    match r.Router.link v with [] -> None | l -> Some { Route.segments = l }

  let link (r : 'a Router.t) (v : 'a) : string = "/" ^ String.concat "/" (r.Router.link v)

  let hashLink (r : 'a Router.t) (v : 'a) : string = "#" ^ link r v

  let tryLink (r : 'a Router.t) (v : 'a) : string option =
    match r.Router.link v with [] -> None | l -> Some ("/" ^ String.concat "/" l)

  let castImpl (_ : 'a -> 'b option) (_ : 'b -> 'a option) (_ : 'a Router.t) : 'b Router.t =
    cleared ()

  let tryMap (_ : 'a -> 'b option) (_ : 'b -> 'a option) (_ : 'a Router.t) : 'b Router.t =
    cleared ()

  let embed (_ : 'a -> 'b) (_ : 'b -> 'a option) (_ : 'a Router.t) : 'b Router.t = cleared ()

  let slice (_ : 'a -> 'b option) (_ : 'b -> 'a) (_ : 'a Router.t) : 'b Router.t = cleared ()
end

module RouterExtensions = struct
  let linkHash (r : 'a Router.t) (v : 'a) : string = RouterModule.hashLink r v
end

module IRouter = struct
  type 'a t = 'a Router.t
end
