(* Phase 1 - compilation *)

(* First round of resolving only attempts to resolve paths and fragments, and then only those
   that don't contain forward paths *)

open Odoc_model
open Lang
module Id = Paths.Identifier

module Opt = struct
  let map f = function Some x -> Some (f x) | None -> None
end

let type_path : Env.t -> Paths.Path.Type.t -> Paths.Path.Type.t =
 fun env p ->
  match p with
  | `Resolved _ -> p
  | _ ->
    let cp = Component.Of_Lang.(type_path empty p) in
    match Tools.resolve_type_path env cp with
    | Ok p' -> `Resolved (Cpath.resolved_type_path_of_cpath p')
    | Error _ -> p

and module_type_path :
    Env.t -> Paths.Path.ModuleType.t -> Paths.Path.ModuleType.t =
 fun env p ->
  match p with
  | `Resolved _ -> p
  | _ ->
    let cp = Component.Of_Lang.(module_type_path empty p) in
    match Tools.resolve_module_type_path env cp with
    | Ok p' -> `Resolved (Cpath.resolved_module_type_path_of_cpath p')
    | Error _ -> p

and module_path : Env.t -> Paths.Path.Module.t -> Paths.Path.Module.t =
 fun env p ->
  match p with
  | `Resolved _ -> p
  | _ ->
    let cp = Component.Of_Lang.(module_path empty p) in
    match Tools.resolve_module_path env cp with
    | Ok p' -> `Resolved (Cpath.resolved_module_path_of_cpath p')
    | Error _ -> p

and class_type_path : Env.t -> Paths.Path.ClassType.t -> Paths.Path.ClassType.t
    =
 fun env p ->
  match p with
  | `Resolved _ -> p
  | _ ->
    let cp = Component.Of_Lang.(class_type_path empty p) in
    match Tools.resolve_class_type_path env cp with
    | Ok p' -> `Resolved (Cpath.resolved_class_type_path_of_cpath p')
    | Error _ -> Cpath.class_type_path_of_cpath cp

let rec unit (resolver : Env.resolver) t =
  let open Compilation_unit in
  let imports, env = Env.initial_env t resolver in
  { t with content = content env t.id t.content; imports }

and content env id =
  let open Compilation_unit in
  function
  | Module m -> Module (signature env (id :> Id.Signature.t) m)
  | Pack _ -> failwith "Unhandled content"

and value_ env parent t =
  let open Value in
  let container = (parent :> Id.Parent.t) in
  try { t with type_ = type_expression env container t.type_ }
  with _ ->
    Errors.report ~what:(`Value t.id) `Compile;
    t

and exception_ env parent e =
  let open Exception in
  let container = (parent :> Id.Parent.t) in
  let res = Opt.map (type_expression env container) e.res in
  let args = type_decl_constructor_argument env container e.args in
  { e with res; args }

and extension env parent t =
  let open Extension in
  let container = (parent :> Id.Parent.t) in
  let constructor c =
    let open Constructor in
    {
      c with
      args = type_decl_constructor_argument env container c.args;
      res = Opt.map (type_expression env container) c.res;
    }
  in
  let type_path = type_path env t.type_path in
  let constructors = List.map constructor t.constructors in
  { t with type_path; constructors }

and external_ env parent e =
  let open External in
  let container = (parent :> Id.Parent.t) in
  { e with type_ = type_expression env container e.type_ }

and class_type_expr env parent =
  let open ClassType in
  let container = (parent :> Id.Parent.t) in
  function
  | Constr (path, texps) ->
      Constr
        ( class_type_path env path,
          List.map (type_expression env container) texps )
  | Signature s -> Signature (class_signature env parent s)

and class_type env c =
  let open ClassType in
  let expansion =
    match
      let open Utils.OptionMonad in
      Env.(lookup_by_id s_class_type) c.id env >>= fun (`ClassType (_, c')) ->
      Tools.class_signature_of_class_type env c' >>= fun sg ->
      let cs =
        Lang_of.class_signature Lang_of.empty
          (c.id :> Paths_types.Identifier.path_class_type)
          sg
      in
      let compiled = class_signature env (c.id :> Id.ClassSignature.t) cs in
      Some compiled
    with
    | Some _ as exp -> exp
    | None ->
        Errors.report ~what:(`Class_type c.id) `Expand;
        c.expansion
  in
  {
    c with
    expr = class_type_expr env (c.id :> Id.ClassSignature.t) c.expr;
    expansion;
  }

and class_signature env parent c =
  let open ClassSignature in
  let container = (parent : Id.ClassSignature.t :> Id.Parent.t) in
  let env = Env.open_class_signature c env in
  let map_item = function
    | Method m -> Method (method_ env parent m)
    | InstanceVariable i -> InstanceVariable (instance_variable env parent i)
    | Constraint (t1, t2) ->
        Constraint
          (type_expression env container t1, type_expression env container t2)
    | Inherit c -> Inherit (class_type_expr env parent c)
    | Comment c -> Comment c
  in
  {
    self = Opt.map (type_expression env container) c.self;
    items = List.map map_item c.items;
  }

and method_ env parent m =
  let open Method in
  let container = (parent :> Id.Parent.t) in
  { m with type_ = type_expression env container m.type_ }

and instance_variable env parent i =
  let open InstanceVariable in
  let container = (parent :> Id.Parent.t) in
  { i with type_ = type_expression env container i.type_ }

and class_ env parent c =
  let open Class in
  let container = (parent :> Id.Parent.t) in
  let expansion =
    match
      let open Utils.OptionMonad in
      Env.(lookup_by_id s_class) c.id env >>= fun (`Class (_, c')) ->
      Tools.class_signature_of_class env c' >>= fun sg ->
      let cs =
        Lang_of.class_signature Lang_of.empty
          (c.id :> Paths_types.Identifier.path_class_type)
          sg
      in
      Some (class_signature env (c.id :> Id.ClassSignature.t) cs)
    with
    | Some _ as exp -> exp
    | None ->
        Errors.report ~what:(`Class c.id) `Expand;
        c.expansion
  in
  let rec map_decl = function
    | ClassType expr ->
        ClassType (class_type_expr env (c.id :> Id.ClassSignature.t) expr)
    | Arrow (lbl, expr, decl) ->
        Arrow (lbl, type_expression env container expr, map_decl decl)
  in
  { c with type_ = map_decl c.type_; expansion }

and module_substitution env m =
  let open ModuleSubstitution in
  { m with manifest = module_path env m.manifest }

and signature_items : Env.t -> Id.Signature.t -> Signature.t -> _ =
 fun env id s ->
  let open Signature in
  List.map
    (fun item ->
      match item with
      | Module (r, m) -> Module (r, module_ env m)
      | ModuleSubstitution m -> ModuleSubstitution (module_substitution env m)
      | Type (r, t) -> Type (r, type_decl env t)
      | TypeSubstitution t -> TypeSubstitution (type_decl env t)
      | ModuleType mt -> ModuleType (module_type env mt)
      | Value v -> Value (value_ env id v)
      | Comment c -> Comment c
      | TypExt t -> TypExt (extension env id t)
      | Exception e -> Exception (exception_ env id e)
      | External e -> External (external_ env id e)
      | Class (r, c) -> Class (r, class_ env id c)
      | ClassType (r, c) -> ClassType (r, class_type env c)
      | Include i -> Include (include_ env i)
      | Open o -> Open o)
    s

and signature : Env.t -> Id.Signature.t -> Signature.t -> _ =
 fun env id s ->
  let env = Env.open_signature s env in
  signature_items env id s

and module_ : Env.t -> Module.t -> Module.t =
 fun env m ->
  let open Module in
  if m.hidden then m
  else
    let extra_expansion_needed =
      match m.type_ with
      | ModuleType (Signature _) -> false (* AlreadyASig *)
      | ModuleType _ -> true
      | Alias _ -> false
      (* Aliases are expanded if necessary during link *)
    in
    (* Format.fprintf Format.err_formatter "Handling module: %a\n" Component.Fmt.model_identifier (m.id :> Id.t); *)
    match Env.(lookup_by_id s_module) m.id env with
    | None ->
        Errors.report ~what:(`Module m.id) `Lookup;
        m
    | Some (`Module (_, m')) ->
        let m' = Component.Delayed.get m' in
        let env' =
          Env.add_module_functor_args m' (m.id :> Id.Path.Module.t) env
        in
        let expansion =
          let sg_id = (m.id :> Id.Signature.t) in
          if not extra_expansion_needed then m.expansion
          else
            match
              Expand_tools.expansion_of_module env m.id ~strengthen:true m'
            with
            | Ok (env, _, ce) ->
                let e = Lang_of.(module_expansion empty sg_id ce) in
                Some (expansion env sg_id e)
            | Error `OpaqueModule -> None
            | Error e ->
                Errors.report ~what:(`Module m.id) ~tools_error:e `Expand;
                m.expansion
        in
        {
          m with
          type_ = module_decl env' (m.id :> Id.Signature.t) m.type_;
          expansion;
        }

and module_decl : Env.t -> Id.Signature.t -> Module.decl -> Module.decl =
 fun env id decl ->
  let open Module in
  match decl with
  | ModuleType expr -> ModuleType (module_type_expr env id expr)
  | Alias p -> (
      let cp' = Component.Of_Lang.(module_path empty p) in
      let cp = Cpath.unresolve_module_path cp' in
      match Tools.resolve_module_path env cp with
      | Ok p' ->
          Alias (`Resolved (Cpath.resolved_module_path_of_cpath p'))
      | Error _ -> Alias p )

and module_type : Env.t -> ModuleType.t -> ModuleType.t =
 fun env m ->
  let open ModuleType in
  let open Utils.ResultMonad in
  let sg_id = (m.id :> Id.Signature.t) in
  (* Format.fprintf Format.err_formatter "Handling module type: %a\n" Component.Fmt.model_identifier (m.id :> Id.t); *)
  let expand m' env =
    match m.expr with
    | None -> Ok (None, None)
    | Some (Signature sg) ->
        let sg' = signature env (m.id :> Id.Signature.t) sg in
        Ok (Some Module.AlreadyASig, Some (Signature sg'))
    | Some expr ->
        ( match Expand_tools.expansion_of_module_type env m.id m' with
        | Ok (env, _, ce) ->
            let e = Lang_of.(module_expansion empty sg_id ce) in
            Ok (env, Some e)
        | Error `OpaqueModule -> Ok (env, None)
        | Error e -> Error (Some e, `Expand) )
        >>= fun (env, expansion') ->
        Ok
          ( Opt.map (expansion env sg_id) expansion',
            Some (module_type_expr env (m.id :> Id.Signature.t) expr) )
  in
  match
    Env.(lookup_by_id s_module_type) m.id env |> of_option ~error:(None, `Lookup)
    >>= fun (`ModuleType (_, m')) ->
    let env = Env.add_module_type_functor_args m' m.id env in
    expand m' env
  with
  | Ok (expansion, expr') -> { m with expr = expr'; expansion }
  | Error (tools_error, action) ->
      Errors.report ~what:(`Module_type m.id) ?tools_error action;
      m

and include_ : Env.t -> Include.t -> Include.t =
 fun env i ->
  let open Include in
  let remove_top_doc_from_signature =
    let open Signature in
    function Comment (`Docs _) :: xs -> xs | xs -> xs
  in
  let decl = Component.Of_Lang.(module_decl empty i.decl) in
  match
    let open Utils.ResultMonad in
    Expand_tools.aux_expansion_of_module_decl env ~strengthen:true decl
    >>= Expand_tools.handle_expansion env i.parent
  with
  | Error e ->
      Errors.report ~what:(`Include decl) ~tools_error:e `Expand;
      i
  | Ok (_, ce) ->

      let map = { Lang_of.empty with shadowed = i.expansion.shadowed } in

      let e = Lang_of.(module_expansion map i.parent ce) in

      let expansion_sg =
        match e with
        | Module.Signature sg -> sg
        | _ -> failwith "Expansion shouldn't be anything other than a signature"
      in
      let expansion =
        {
          resolved = true;
          shadowed = i.expansion.shadowed;
          content =
            remove_top_doc_from_signature (signature env i.parent expansion_sg);
        }
      in

      { i with decl = module_decl env i.parent i.decl; expansion }

and expansion : Env.t -> Id.Signature.t -> Module.expansion -> Module.expansion
    =
  let open Module in
  fun env id e ->
    match e with
    | AlreadyASig -> AlreadyASig
    | Signature sg -> Signature (signature env id sg)
    | Functor (args, sg) ->
        Functor (List.map (functor_parameter env) args, signature env id sg)

and functor_parameter : Env.t -> FunctorParameter.t -> FunctorParameter.t =
 fun env param ->
  match param with
  | Unit -> Unit
  | Named arg -> Named (functor_parameter_parameter env arg)

and functor_parameter_parameter :
    Env.t -> FunctorParameter.parameter -> FunctorParameter.parameter =
 fun env' a ->
  let open Utils.ResultMonad in
  let sg_id = (a.id :> Id.Signature.t) in
  let get_module_type_expr = function
    | Component.Module.ModuleType expr -> Ok expr
    | _ -> Error `Resolve_module_type
  in
  match
    Env.(lookup_by_id s_module) a.id env' |> of_option ~error:`Lookup
    >>= fun (`Module (_, functor_arg)) ->
    let functor_arg = Component.Delayed.get functor_arg in
    let env =
      Env.add_module_functor_args functor_arg (a.id :> Id.Path.Module.t) env'
    in
    get_module_type_expr functor_arg.type_ >>= fun expr ->
    match Expand_tools.expansion_of_module_type_expr env sg_id expr with
    | Ok (env, _, ce) ->
        let e = Lang_of.(module_expansion empty sg_id ce) in
        Ok (env, Some e)
    | Error `OpaqueModule -> Ok (env, None)
    | Error e ->
        Errors.report ~what:(`Functor_parameter a.id) ~tools_error:e `Expand;
        Ok (env, None)
  with
  | Ok (env, expn) ->
      {
        a with
        expr = module_type_expr env (a.id :> Id.Signature.t) a.expr;
        expansion = Component.Opt.map (expansion env sg_id) expn;
      }
  | Error e ->
      Errors.report ~what:(`Functor_parameter a.id) e;
      a

and module_type_expr :
    Env.t -> Id.Signature.t -> ModuleType.expr -> ModuleType.expr =
 fun env id expr ->
  let open ModuleType in
  let open Utils.ResultMonad in
  let resolve_sub ~fragment_root (sg_res, env, subs) lsub =
    match sg_res with
    | Error _ -> (sg_res, env, lsub :: subs)
    | Ok sg -> (
        (* Format.eprintf "compile.module_type_expr: sig=%a\n%!" Component.Fmt.signature sg; *)
        let lang_of_map = Lang_of.with_fragment_root fragment_root in
        let env = Env.add_fragment_root sg env in
        let sg_and_sub =
          match lsub with
          | ModuleEq (frag, decl) ->
              let cfrag = Component.Of_Lang.(module_fragment empty frag) in
              let cfrag', frag' =
                match
                  Tools.resolve_module_fragment env (fragment_root, sg) cfrag
                with
                | Some cfrag' ->
                    ( `Resolved cfrag',
                      `Resolved
                        (Lang_of.Path.resolved_module_fragment lang_of_map
                           cfrag') )
                | None ->
                    Errors.report ~what:(`With_module cfrag) `Resolve;
                    (cfrag, frag)
              in
              let decl' = module_decl env id decl in
              let cdecl' = Component.Of_Lang.(module_decl empty decl') in
              let resolved_csub =
                Component.ModuleType.ModuleEq (cfrag', cdecl')
              in
              Tools.fragmap ~mark_substituted:true env resolved_csub sg
              >>= fun sg' -> Ok (sg', ModuleEq (frag', decl'))
          | TypeEq (frag, eqn) ->
              let cfrag = Component.Of_Lang.(type_fragment empty frag) in
              let cfrag', frag' =
                match
                  Tools.resolve_type_fragment env (fragment_root, sg) cfrag
                with
                | Some cfrag' ->
                    ( `Resolved cfrag',
                      `Resolved
                        (Lang_of.Path.resolved_type_fragment lang_of_map cfrag')
                    )
                | None ->
                    Errors.report ~what:(`With_type cfrag) `Compile;
                    (cfrag, frag)
              in
              let eqn' = type_decl_equation env (id :> Id.Parent.t) eqn in
              let ceqn' = Component.Of_Lang.(type_equation empty eqn') in
              Tools.fragmap ~mark_substituted:true env
                (Component.ModuleType.TypeEq (cfrag', ceqn'))
                sg
              >>= fun sg' -> Ok (sg', TypeEq (frag', eqn'))
          | ModuleSubst (frag, mpath) ->
              let cfrag = Component.Of_Lang.(module_fragment empty frag) in
              let cfrag', frag' =
                match
                  Tools.resolve_module_fragment env (fragment_root, sg) cfrag
                with
                | Some cfrag ->
                    ( `Resolved cfrag,
                      `Resolved
                        (Lang_of.Path.resolved_module_fragment lang_of_map
                           cfrag) )
                | None ->
                    Errors.report ~what:(`With_module cfrag) `Resolve;
                    (cfrag, frag)
              in
              let mpath' = module_path env mpath in
              let cmpath' = Component.Of_Lang.(module_path empty mpath') in
              Tools.fragmap ~mark_substituted:true env
                (Component.ModuleType.ModuleSubst (cfrag', cmpath'))
                sg
              >>= fun sg' -> Ok (sg', ModuleSubst (frag', mpath'))
          | TypeSubst (frag, eqn) ->
              let cfrag = Component.Of_Lang.(type_fragment empty frag) in
              let cfrag', frag' =
                match
                  Tools.resolve_type_fragment env (fragment_root, sg) cfrag
                with
                | Some cfrag ->
                    ( `Resolved cfrag,
                      `Resolved
                        (Lang_of.Path.resolved_type_fragment lang_of_map cfrag)
                    )
                | None ->
                    Errors.report ~what:(`With_type cfrag) `Compile;
                    (cfrag, frag)
              in
              let eqn' = type_decl_equation env (id :> Id.Parent.t) eqn in
              let ceqn' = Component.Of_Lang.(type_equation empty eqn') in
              Tools.fragmap ~mark_substituted:true env
                (Component.ModuleType.TypeSubst (cfrag', ceqn'))
                sg
              >>= fun sg' -> Ok (sg', TypeSubst (frag', eqn'))
        in
        match sg_and_sub with
        | Ok (sg', sub') -> (Ok sg', env, sub' :: subs)
        | Error _ -> (sg_res, env, lsub :: subs) )
  in

  let rec inner resolve_signatures = function
    | Signature s ->
        if resolve_signatures then Signature (signature env id s)
        else Signature s
    | Path p -> Path (module_type_path env p)
    | With (expr, subs) -> (
        let expr = inner false expr in
        let cexpr = Component.Of_Lang.(module_type_expr empty expr) in
        let rec find_parent : Component.ModuleType.expr -> Cfrag.root option =
         fun expr ->
          match expr with
          | Component.ModuleType.Signature _ -> None
          | Path (`Resolved p) -> Some (`ModuleType p)
          | Path _ -> None
          | With (e, _) -> find_parent e
          | Functor _ -> failwith "Impossible"
          | TypeOf (MPath (`Resolved p)) 
          | TypeOf (Struct_include (`Resolved p)) -> Some (`Module p)
          | TypeOf _ -> None
        in
        match find_parent cexpr with
        | None -> With (expr, subs)
        | Some parent -> (
            match
              Tools.signature_of_module_type_expr ~mark_substituted:true env
                cexpr
            with
            | Error e ->
                Errors.report ~what:(`Module_type id) ~tools_error:e `Lookup;
                With (expr, subs)
            | Ok sg ->
                let fragment_root =
                  match parent with (`ModuleType _ | `Module _) as x -> x
                in
                let _, _, subs =
                  List.fold_left
                    (resolve_sub ~fragment_root)
                    (Ok sg, env, []) subs
                in
                let subs = List.rev subs in
                With (expr, subs) ) )
    | Functor (param, res) ->
        let param' = functor_parameter env param in
        let res' = module_type_expr env id res in
        Functor (param', res')
    | TypeOf (MPath p) -> TypeOf (MPath (module_path env p))
    | TypeOf (Struct_include p) -> TypeOf (Struct_include (module_path env p))
  in
  inner true expr

and type_decl : Env.t -> TypeDecl.t -> TypeDecl.t =
 fun env t ->
  let open TypeDecl in
  let container =
    match t.id with
    | `Type (parent, _) -> (parent :> Id.Parent.t)
    | `CoreType _ -> assert false
  in
  let equation = type_decl_equation env container t.equation in
  let representation =
    Opt.map (type_decl_representation env container) t.representation
  in
  { t with equation; representation }

and type_decl_equation :
    Env.t -> Id.Parent.t -> TypeDecl.Equation.t -> TypeDecl.Equation.t =
 fun env parent t ->
  let open TypeDecl.Equation in
  let manifest = Opt.map (type_expression env parent) t.manifest in
  let constraints =
    List.map
      (fun (tex1, tex2) ->
        (type_expression env parent tex1, type_expression env parent tex2))
      t.constraints
  in
  { t with manifest; constraints }

and type_decl_representation :
    Env.t ->
    Id.Parent.t ->
    TypeDecl.Representation.t ->
    TypeDecl.Representation.t =
 fun env parent r ->
  let open TypeDecl.Representation in
  match r with
  | Variant cs -> Variant (List.map (type_decl_constructor env parent) cs)
  | Record fs -> Record (List.map (type_decl_field env parent) fs)
  | Extensible -> Extensible

and type_decl_field env parent f =
  let open TypeDecl.Field in
  { f with type_ = type_expression env parent f.type_ }

and type_decl_constructor_argument env parent c =
  let open TypeDecl.Constructor in
  match c with
  | Tuple ts -> Tuple (List.map (type_expression env parent) ts)
  | Record fs -> Record (List.map (type_decl_field env parent) fs)

and type_decl_constructor :
    Env.t -> Id.Parent.t -> TypeDecl.Constructor.t -> TypeDecl.Constructor.t =
 fun env parent c ->
  let open TypeDecl.Constructor in
  let args = type_decl_constructor_argument env parent c.args in
  let res = Opt.map (type_expression env parent) c.res in
  { c with args; res }

and type_expression_polyvar env parent v =
  let open TypeExpr.Polymorphic_variant in
  let constructor c =
    let open Constructor in
    { c with arguments = List.map (type_expression env parent) c.arguments }
  in
  let element = function
    | Type t -> Type (type_expression env parent t)
    | Constructor c -> Constructor (constructor c)
  in
  { v with elements = List.map element v.elements }

and type_expression_object env parent o =
  let open TypeExpr.Object in
  let method_ m = { m with type_ = type_expression env parent m.type_ } in
  let field = function
    | Method m -> Method (method_ m)
    | Inherit t -> Inherit (type_expression env parent t)
  in
  { o with fields = List.map field o.fields }

and type_expression_package env parent p =
  let open TypeExpr.Package in
  let cp' = Component.Of_Lang.(module_type_path empty p.path) in
  let cp = Cpath.unresolve_module_type_path cp' in
  match Tools.resolve_module_type ~mark_substituted:true env cp with
  | Ok (path, mt) -> (
      match Tools.signature_of_module_type env mt with
      | Error e ->
          Errors.report ~what:(`Package cp) ~tools_error:e `Lookup;
          p
      | Ok sg ->
          let substitution (frag, t) =
            let cfrag = Component.Of_Lang.(type_fragment empty frag) in
            let frag' =
              match
                Tools.resolve_type_fragment env (`ModuleType path, sg) cfrag
              with
              | Some cfrag' ->
                  `Resolved (Lang_of.(Path.resolved_type_fragment empty) cfrag')
              | None ->
                  Errors.report ~what:(`Type cfrag) `Compile;
                  frag
            in
            (frag', type_expression env parent t)
          in
          {
            path = module_type_path env p.path;
            substitutions = List.map substitution p.substitutions;
          } )
  | Error _ -> { p with path = Cpath.module_type_path_of_cpath cp }

and type_expression : Env.t -> Id.Parent.t -> _ -> _ =
 fun env parent texpr ->
  let open TypeExpr in
  match texpr with
  | Var _ | Any -> texpr
  | Alias (t, str) -> Alias (type_expression env parent t, str)
  | Arrow (lbl, t1, t2) ->
      Arrow (lbl, type_expression env parent t1, type_expression env parent t2)
  | Tuple ts -> Tuple (List.map (type_expression env parent) ts)
  | Constr (path, ts') -> (
      let cp' = Component.Of_Lang.(type_path empty path) in
      let cp = Cpath.unresolve_type_path cp' in
      let ts = List.map (type_expression env parent) ts' in
      match Tools.resolve_type env cp with
      | Ok (cp, Found _t) ->
          let p = Cpath.resolved_type_path_of_cpath cp in
          Constr (`Resolved p, ts)
      | Ok (_cp, Replaced x) -> Lang_of.(type_expr empty parent x)
      | Error _ -> Constr (Cpath.type_path_of_cpath cp, ts) )
  | Polymorphic_variant v ->
      Polymorphic_variant (type_expression_polyvar env parent v)
  | Object o -> Object (type_expression_object env parent o)
  | Class (path, ts) -> Class (path, List.map (type_expression env parent) ts)
  | Poly (strs, t) -> Poly (strs, type_expression env parent t)
  | Package p -> Package (type_expression_package env parent p)

type msg = [ `Msg of string ]

exception Fetch_failed of msg

let build_resolver :
    ?equal:(Root.t -> Root.t -> bool) ->
    ?hash:(Root.t -> int) ->
    string list ->
    (string -> Env.lookup_unit_result) ->
    (Root.t -> (Compilation_unit.t, _) Result.result) ->
    (string -> Root.t option) ->
    (Root.t -> (Page.t, _) Result.result) ->
    Env.resolver =
 fun ?equal:_ ?hash:_ open_units lookup_unit resolve_unit lookup_page
     resolve_page ->
  let resolve_unit root =
    match resolve_unit root with
    | Ok unit -> unit
    | Error e -> raise (Fetch_failed e)
  and resolve_page root =
    match resolve_page root with
    | Ok page -> page
    | Error e -> raise (Fetch_failed e)
  in
  { Env.lookup_unit; resolve_unit; lookup_page; resolve_page; open_units }

let compile x y = Lookup_failures.catch_failures (fun () -> unit x y)

let resolve_page _resolver y = y
