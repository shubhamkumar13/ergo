(*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *)

(** Ergo is a language for expressing contract logic. *)

(** * Abstract Syntax *)

Require Import String.
Require Import List.
Require Import ErgoSpec.Backend.ErgoBackend.
Require Import ErgoSpec.Common.Utils.EProvenance.
Require Import ErgoSpec.Common.Utils.ENames.
Require Import ErgoSpec.Common.Utils.EResult.
Require Import ErgoSpec.Common.Utils.EAstUtil.
Require Import ErgoSpec.Common.CTO.CTO.
Require Import ErgoSpec.Common.Types.ErgoType.
Require Import ErgoSpec.Common.Pattern.EPattern.
Require Import ErgoSpec.Ergo.Lang.Ergo.
Require Import ErgoSpec.Translation.CTOtoErgo.

Section ErgoNameResolution.

  (** There are three phases to the name resolution in ErgoType files/modules:
- build a per-namespace table containing all the local names mapped to their namespace resolve names
- for a module, resolve imports using the per-namespace table to build a full namespace mapping for that module
- resolve the names within a given module using the full namespace mapping for that module *)

  Definition no_namespace : string := "".
    
  Section NamespaceTable.
    (** Maps local names to absolute names for a given ErgoType module *)
    Definition name_table : Set := list (local_name * absolute_name).

    (** Maps namespaces to the names tables for that namespace *)
    Record namespace_table : Set :=
      mkNamespaceTable
        { namespace_table_types : name_table;
          namespace_table_constants : name_table;
          namespace_table_functions : name_table;
          namespace_table_contracts : name_table; }.

    Definition empty_namespace_table : namespace_table :=
      mkNamespaceTable nil nil nil nil.

    Definition one_type_to_namespace_table (ln:local_name) (an:absolute_name) : namespace_table :=
      mkNamespaceTable ((ln,an)::nil) nil nil nil.
    Definition one_constant_to_namespace_table (ln:local_name) (an:absolute_name) : namespace_table :=
      mkNamespaceTable nil ((ln,an)::nil) nil nil.
    Definition one_function_to_namespace_table (ln:local_name) (an:absolute_name) : namespace_table :=
      mkNamespaceTable nil nil ((ln,an)::nil) nil.
    Definition one_contract_to_namespace_table (ln:local_name) (an:absolute_name) : namespace_table :=
      mkNamespaceTable nil nil nil ((ln,an)::nil).

    Definition namespace_table_app (tbl1 tbl2:namespace_table) : namespace_table :=
      mkNamespaceTable
        (app tbl1.(namespace_table_types) tbl2.(namespace_table_types))
        (app tbl1.(namespace_table_constants) tbl2.(namespace_table_constants))
        (app tbl1.(namespace_table_functions) tbl2.(namespace_table_functions))
        (app tbl1.(namespace_table_contracts) tbl2.(namespace_table_contracts)).

    Definition lookup_type_name (prov:provenance) (tbl:namespace_table) (ln:local_name) : eresult absolute_name :=
      match lookup string_dec tbl.(namespace_table_types) ln with
      | None => type_name_not_found_error prov ln
      | Some an => esuccess an
      end.
    Definition lookup_constant_name (prov:provenance) (tbl:namespace_table) (ln:local_name) : eresult absolute_name :=
      match lookup string_dec tbl.(namespace_table_constants) ln with
      | None => variable_name_not_found_error prov ln
      | Some an => esuccess an
      end.
    Definition lookup_function_name (prov:provenance) (tbl:namespace_table) (ln:local_name) : eresult absolute_name :=
      match lookup string_dec tbl.(namespace_table_functions) ln with
      | None => function_name_not_found_error prov ln
      | Some an => esuccess an
      end.
    Definition lookup_contract_name (prov:provenance) (tbl:namespace_table) (ln:local_name) : eresult absolute_name :=
      match lookup string_dec tbl.(namespace_table_contracts) ln with
      | None => contract_name_not_found_error prov ln
      | Some an => esuccess an
      end.

    Definition resolve_type_name (prov:provenance) (tbl:namespace_table) (rn:relative_name) :=
      match fst rn with
      | None => lookup_type_name prov tbl (snd rn)
      | Some ns => esuccess (absolute_name_of_local_name ns (snd rn))
      end.
    Definition resolve_constant_name (prov:provenance) (tbl:namespace_table) (rn:relative_name) :=
      match fst rn with
      | None => lookup_constant_name prov tbl (snd rn)
      | Some ns => esuccess (absolute_name_of_local_name ns (snd rn))
      end.
    Definition resolve_function_name (prov:provenance) (tbl:namespace_table) (rn:relative_name) :=
      match fst rn with
      | None => lookup_function_name prov tbl (snd rn)
      | Some ns => esuccess (absolute_name_of_local_name ns (snd rn))
      end.
    Definition resolve_contract_name (prov:provenance) (tbl:namespace_table) (rn:relative_name) :=
      match fst rn with
      | None => lookup_contract_name prov tbl (snd rn)
      | Some ns => esuccess (absolute_name_of_local_name ns (snd rn))
      end.

    Definition add_type_to_namespace_table (ln:local_name) (an:absolute_name) (tbl:namespace_table) :=
      mkNamespaceTable
        ((ln,an)::tbl.(namespace_table_types))
        tbl.(namespace_table_constants)
        tbl.(namespace_table_functions)
        tbl.(namespace_table_contracts).
    Definition add_constant_to_namespace_table (ln:local_name) (an:absolute_name) (tbl:namespace_table) :=
      mkNamespaceTable
        tbl.(namespace_table_types)
        ((ln,an)::tbl.(namespace_table_constants))
        tbl.(namespace_table_functions)
        tbl.(namespace_table_contracts).
    Definition add_function_to_namespace_table (ln:local_name) (an:absolute_name) (tbl:namespace_table) :=
      mkNamespaceTable
        tbl.(namespace_table_types)
        tbl.(namespace_table_constants)
        ((ln,an)::tbl.(namespace_table_functions))
        tbl.(namespace_table_contracts).
    Definition add_contract_to_namespace_table (ln:local_name) (an:absolute_name) (tbl:namespace_table) :=
      mkNamespaceTable
        tbl.(namespace_table_types)
        tbl.(namespace_table_constants)
        tbl.(namespace_table_functions)
        ((ln,an)::tbl.(namespace_table_contracts)).

  End NamespaceTable.

  Section NamespaceContext.
    Record namespace_ctxt : Set :=
      mkNamespaceCtxt {
          namespace_ctxt_modules : list (namespace_name * namespace_table);
          namespace_ctxt_namespace : namespace_name;
          namespace_ctxt_current : namespace_table;
        }.

    Definition empty_namespace_ctxt (ns:namespace_name) : namespace_ctxt :=
      mkNamespaceCtxt nil ns empty_namespace_table.

    Definition update_namespace_context_modules
               (ctxt:namespace_ctxt)
               (ns:namespace_name)
               (update:namespace_table -> namespace_table) : namespace_ctxt :=
      match lookup string_dec ctxt.(namespace_ctxt_modules) ns with
      | Some t =>
        mkNamespaceCtxt (update_first string_dec ctxt.(namespace_ctxt_modules) ns (update t))
                        ctxt.(namespace_ctxt_namespace)
                        ctxt.(namespace_ctxt_current)
      | None =>
        mkNamespaceCtxt ((ns, update empty_namespace_table) :: ctxt.(namespace_ctxt_modules))
                        ctxt.(namespace_ctxt_namespace)
                        ctxt.(namespace_ctxt_current)
      end.

    Definition update_namespace_context_current
               (ctxt:namespace_ctxt)
               (update:namespace_table -> namespace_table) : namespace_ctxt :=
      mkNamespaceCtxt ctxt.(namespace_ctxt_modules)
                      ctxt.(namespace_ctxt_namespace)
                      (update ctxt.(namespace_ctxt_current)).

    Definition add_type_to_namespace_ctxt
               (ctxt:namespace_ctxt) (ns:namespace_name) (ln:local_name) (an:absolute_name) :=
      update_namespace_context_modules ctxt ns (add_type_to_namespace_table ln an).
  
    Definition add_constant_to_namespace_ctxt
               (ctxt:namespace_ctxt) (ns:namespace_name) (ln:local_name) (an:absolute_name) :=
      update_namespace_context_modules ctxt ns (add_constant_to_namespace_table ln an).
  
    Definition add_function_to_namespace_ctxt
               (ctxt:namespace_ctxt) (ns:namespace_name) (ln:local_name) (an:absolute_name) :=
      update_namespace_context_modules ctxt ns (add_function_to_namespace_table ln an).

    Definition add_contract_to_namespace_ctxt
               (ctxt:namespace_ctxt) (ns:namespace_name) (ln:local_name) (an:absolute_name) :=
      update_namespace_context_modules ctxt ns (add_contract_to_namespace_table ln an).

    Definition add_type_to_namespace_ctxt_current
               (ctxt:namespace_ctxt) (ln:local_name) (an:absolute_name) :=
      update_namespace_context_current ctxt (add_type_to_namespace_table ln an).
    
    Definition add_constant_to_namespace_ctxt_current
               (ctxt:namespace_ctxt) (ln:local_name) (an:absolute_name) :=
      update_namespace_context_current ctxt (add_constant_to_namespace_table ln an).
  
    Definition add_function_to_namespace_ctxt_current
               (ctxt:namespace_ctxt) (ln:local_name) (an:absolute_name) :=
      update_namespace_context_current ctxt (add_function_to_namespace_table ln an).

    Definition add_contract_to_namespace_ctxt_current
               (ctxt:namespace_ctxt) (ln:local_name) (an:absolute_name) :=
      update_namespace_context_current ctxt (add_contract_to_namespace_table ln an).

    Definition new_namespace_scope (ctxt:namespace_ctxt) (ns:namespace_name) : namespace_ctxt :=
      let prev_ns := ctxt.(namespace_ctxt_namespace) in
      let prev_tbl := ctxt.(namespace_ctxt_current) in
      let prev_modules := ctxt.(namespace_ctxt_modules) in
      if string_dec prev_ns no_namespace (* Do not push empty namespace to stack *)
      then
        mkNamespaceCtxt
          prev_modules
          ns
          empty_namespace_table
      else
        match lookup string_dec prev_modules prev_ns with
        | Some t =>
          mkNamespaceCtxt
            (update_first string_dec prev_modules prev_ns (namespace_table_app prev_tbl t))
            ns
            empty_namespace_table
        | None =>
          mkNamespaceCtxt
            ((prev_ns, prev_tbl) :: prev_modules)
            ns
            empty_namespace_table
        end.

    Fixpoint namespace_ctxt_of_ergo_decls
             (ctxt:namespace_ctxt)
             (ns:namespace_name)
             (dls:list lrergo_declaration) : namespace_ctxt :=
      match dls with
      | nil => ctxt
      | DImport _ _ :: rest =>
        let ctxt := namespace_ctxt_of_ergo_decls ctxt ns rest in
        ctxt
      | DType _ td :: rest =>
        let ctxt := namespace_ctxt_of_ergo_decls ctxt ns rest in
        let ln := td.(type_declaration_name) in
        let an := absolute_name_of_local_name ns ln in
        add_type_to_namespace_ctxt ctxt ns ln an
      | DStmt _ _ :: rest =>
        let ctxt := namespace_ctxt_of_ergo_decls ctxt ns rest in
        ctxt
      | DConstant _ ln cd :: rest =>
        let ctxt := namespace_ctxt_of_ergo_decls ctxt ns rest in
        let an := absolute_name_of_local_name ns ln in
        add_constant_to_namespace_ctxt ctxt ns ln an
      | DFunc _ ln fd :: rest =>
        let ctxt := namespace_ctxt_of_ergo_decls ctxt ns rest in
        let an := absolute_name_of_local_name ns ln in
        add_function_to_namespace_ctxt ctxt ns ln an
      | DContract _ ln _ :: rest =>
        let ctxt := namespace_ctxt_of_ergo_decls ctxt ns rest in
        let an := absolute_name_of_local_name ns ln in
        add_contract_to_namespace_ctxt ctxt ns ln an
      | DSetContract _ ln _ :: rest =>
        let ctxt := namespace_ctxt_of_ergo_decls ctxt ns rest in
        ctxt
      end.

    Definition namespace_ctxt_of_ergo_module (ctxt:namespace_ctxt) (m:lrergo_module) : namespace_ctxt :=
      namespace_ctxt_of_ergo_decls ctxt m.(module_namespace) m.(module_declarations).

    Definition namespace_ctxt_of_ergo_modules (ctxt:namespace_ctxt) (ml:list lrergo_module) : namespace_ctxt :=
      fold_left namespace_ctxt_of_ergo_module ml ctxt.

    Definition namespace_ctxt_of_cto_packages (ctxt:namespace_ctxt) (ctos:list cto_package) : namespace_ctxt :=
      let mls := map cto_package_to_ergo_module ctos in
      fold_left namespace_ctxt_of_ergo_module mls ctxt.

  End NamespaceContext.

  Section ResolveImports.
    (** This applies imports *)
    Definition lookup_one_import
               (ctxt:namespace_ctxt)
               (ic:limport_decl) : eresult namespace_table :=
      match ic with
      | ImportAll prov ns =>
        match lookup string_dec ctxt.(namespace_ctxt_modules) ns with
        | Some tbl => esuccess tbl
        | None => import_not_found_error prov ns
        end
      | ImportSelf prov ns =>
        match lookup string_dec ctxt.(namespace_ctxt_modules) ns with
        | Some tbl => esuccess tbl
        | None => esuccess empty_namespace_table
        end
      | ImportName prov ns ln =>
        match lookup string_dec ctxt.(namespace_ctxt_modules) ns with
        | Some tbl =>
          match lookup string_dec tbl.(namespace_table_types) ln with
          | None => import_name_not_found_error prov ns ln
          | Some an => esuccess (one_type_to_namespace_table ln an)
          end
        | None => import_not_found_error prov ns
        end
      end.

    Definition resolve_one_import
               (ctxt:namespace_ctxt)
               (ic:limport_decl) : eresult namespace_ctxt :=
      elift (fun tbl =>
               mkNamespaceCtxt
                 ctxt.(namespace_ctxt_modules)
                 ctxt.(namespace_ctxt_namespace)
                 (namespace_table_app ctxt.(namespace_ctxt_current) tbl))
            (lookup_one_import ctxt ic).
    
    (* Resolve imports for CTO *)
    Definition is_builtin_import (ns:namespace_name) : bool :=
      if string_dec ns hyperledger_namespace
      then true
      else if string_dec ns stdlib_namespace
           then true
           else false.

  End ResolveImports.

  Section NameResolution.
    (** Name resolution for type declarations *)
    Fixpoint resolve_ergo_type
             (tbl:namespace_table)
             (t:lrergo_type) : eresult laergo_type :=
      match t with
      | ErgoTypeAny prov => esuccess (ErgoTypeAny prov)
      | ErgoTypeNone prov => esuccess (ErgoTypeNone prov)
      | ErgoTypeBoolean prov => esuccess (ErgoTypeBoolean prov)
      | ErgoTypeString prov => esuccess (ErgoTypeString prov)
      | ErgoTypeDouble prov => esuccess (ErgoTypeDouble prov)
      | ErgoTypeLong prov => esuccess (ErgoTypeLong prov)
      | ErgoTypeInteger prov => esuccess (ErgoTypeInteger prov)
      | ErgoTypeDateTime prov => esuccess (ErgoTypeDateTime prov)
      | ErgoTypeClassRef prov rn =>
        elift (ErgoTypeClassRef prov)
              (resolve_type_name prov tbl rn)
      | ErgoTypeOption prov t =>
        elift (ErgoTypeOption prov) (resolve_ergo_type tbl t)
      | ErgoTypeRecord prov r =>
        let initial_map := map (fun xy => (fst xy, resolve_ergo_type tbl (snd xy))) r in
        let lifted_map := emaplift (fun xy => elift (fun t => (fst xy, t)) (snd xy)) initial_map in
        elift (ErgoTypeRecord prov) lifted_map
      | ErgoTypeArray prov t =>
        elift (ErgoTypeArray prov) (resolve_ergo_type tbl t)
      | ErgoTypeSum prov t1 t2 =>
        elift2 (ErgoTypeSum prov)
               (resolve_ergo_type tbl t1)
               (resolve_ergo_type tbl t2)
      end.

    Definition resolve_ergo_type_struct
               (tbl:namespace_table)
               (t:list (string * lrergo_type)) : eresult (list (string * laergo_type)) :=
      emaplift (fun xy =>
                  elift (fun t => (fst xy, t)) (resolve_ergo_type tbl (snd xy))) t.

    Definition resolve_type_annotation
               (prov:provenance)
               (tbl:namespace_table)
               (en:option relative_name) : eresult (option absolute_name) :=
      match en with
      | None => esuccess None
      | Some rn => elift Some (resolve_type_name prov tbl rn)
      end.

    Definition resolve_extends
               (prov:provenance)
               (tbl:namespace_table)
               (en:rextends) : eresult aextends :=
      resolve_type_annotation prov tbl en.

    Definition resolve_ergo_type_signature
               (tbl:namespace_table)
               (sig:lrergo_type_signature) : eresult laergo_type_signature :=
      let params_types := resolve_ergo_type_struct tbl (sig.(type_signature_params)) in
      let output_type : eresult laergo_type := resolve_ergo_type tbl sig.(type_signature_output) in
      let throws_type : eresult (option laergo_type) :=
          match sig.(type_signature_throws) with
          | None => esuccess None
          | Some throw_ty =>
            elift Some (resolve_ergo_type tbl throw_ty)
          end
      in
      let emits_type : eresult (option laergo_type) :=
          match sig.(type_signature_emits) with
          | None => esuccess None
          | Some emits_ty =>
            elift Some (resolve_ergo_type tbl emits_ty)
          end
      in
      elift4 (mkErgoTypeSignature
                sig.(type_signature_annot))
             params_types
             output_type
             throws_type
           emits_type.

    Definition resolve_ergo_type_clauses
               (tbl:namespace_table)
               (cls:list (string * lrergo_type_signature)) : eresult (list (string * laergo_type_signature)) :=
      emaplift (fun xy => elift (fun r => (fst xy, r))
                                (resolve_ergo_type_signature tbl (snd xy))) cls.

    Definition resolve_ergo_type_declaration_desc
               (prov:provenance)
               (tbl:namespace_table)
               (d:lrergo_type_declaration_desc) : eresult laergo_type_declaration_desc :=
      match d with
      | ErgoTypeEnum l => esuccess (ErgoTypeEnum l)
      | ErgoTypeTransaction extends_name ergo_type_struct =>
        elift2 ErgoTypeTransaction
               (resolve_extends prov tbl extends_name)
               (resolve_ergo_type_struct tbl ergo_type_struct)
      | ErgoTypeConcept extends_name ergo_type_struct =>
        elift2 ErgoTypeConcept
               (resolve_extends prov tbl extends_name)
               (resolve_ergo_type_struct tbl ergo_type_struct)
      | ErgoTypeEvent extends_name ergo_type_struct =>
        elift2 ErgoTypeEvent
               (resolve_extends prov tbl extends_name)
               (resolve_ergo_type_struct tbl ergo_type_struct)
      | ErgoTypeAsset extends_name ergo_type_struct =>
        elift2 ErgoTypeAsset
               (resolve_extends prov tbl extends_name)
               (resolve_ergo_type_struct tbl ergo_type_struct)
      | ErgoTypeParticipant extends_name ergo_type_struct =>
        elift2 ErgoTypeParticipant
               (resolve_extends prov tbl extends_name)
               (resolve_ergo_type_struct tbl ergo_type_struct)
      | ErgoTypeGlobal ergo_type =>
        elift ErgoTypeGlobal (resolve_ergo_type tbl ergo_type)
      | ErgoTypeFunction ergo_type_signature =>
        elift ErgoTypeFunction
              (resolve_ergo_type_signature tbl ergo_type_signature)
      | ErgoTypeContract template_type state_type clauses_sigs =>
        elift3 ErgoTypeContract
               (resolve_ergo_type tbl template_type)
               (resolve_ergo_type tbl state_type)
               (resolve_ergo_type_clauses tbl clauses_sigs)
      end.

    Definition resolve_ergo_type_declaration
               (module_ns:namespace_name)
               (tbl:namespace_table)
               (decl: lrergo_type_declaration) : eresult laergo_type_declaration :=
      let name := absolute_name_of_local_name module_ns decl.(type_declaration_name) in
      let edecl_desc :=
          resolve_ergo_type_declaration_desc
            decl.(type_declaration_annot) tbl decl.(type_declaration_type)
      in
      elift (fun k => mkErgoTypeDeclaration decl.(type_declaration_annot) name k) edecl_desc.

    Definition resolve_ergo_pattern
               (tbl:namespace_table)
               (p:lrergo_pattern) : eresult (laergo_pattern) :=
      match p with
      | CaseData prov d => esuccess (CaseData prov d)
      | CaseWildcard prov ta => elift (CaseWildcard prov) (resolve_type_annotation prov tbl ta)
      | CaseLet prov v ta => elift (CaseLet prov v) (resolve_type_annotation prov tbl ta)
      | CaseLetOption prov v ta => elift (CaseLetOption prov v) (resolve_type_annotation prov tbl ta)
      end.
    
    (** Name resolution for expressions *)
    Fixpoint resolve_ergo_expr
             (tbl:namespace_table)
             (e:lrergo_expr) : eresult laergo_expr :=
      match e with
      | EThisContract prov => esuccess (EThisContract prov)
      | EThisClause prov => esuccess (EThisClause prov)
      | EThisState prov => esuccess (EThisState prov)
      | EVar prov v => esuccess (EVar prov v)
      | EConst prov d => esuccess (EConst prov d)
      | EArray prov el =>
        let init_el := esuccess nil in
        let proc_one (e:lrergo_expr) (acc:eresult (list laergo_expr)) : eresult (list laergo_expr) :=
            elift2
              cons
              (resolve_ergo_expr tbl e)
              acc
        in
        elift (EArray prov) (fold_right proc_one init_el el)
      | EUnaryOp prov u e =>
        elift (EUnaryOp prov u)
              (resolve_ergo_expr tbl e)
      | EBinaryOp prov b e1 e2 =>
        elift2 (EBinaryOp prov b)
               (resolve_ergo_expr tbl e1)
               (resolve_ergo_expr tbl e2)
      | EIf prov e1 e2 e3 =>
        elift3 (EIf prov)
               (resolve_ergo_expr tbl e1)
               (resolve_ergo_expr tbl e2)
               (resolve_ergo_expr tbl e3)
      | ELet prov v ta e1 e2 =>
        let rta :=
            match ta with
            | None => esuccess None
            | Some ta => elift Some (resolve_ergo_type tbl ta)
            end
        in
        elift3 (ELet prov v)
               rta
               (resolve_ergo_expr tbl e1)
               (resolve_ergo_expr tbl e2)
      | ENew prov cr el =>
        let rcr := resolve_type_name prov tbl cr in
        let init_rec := esuccess nil in
        let proc_one (att:string * lrergo_expr) (acc:eresult (list (string * laergo_expr))) :=
            let attname := fst att in
            let e := resolve_ergo_expr tbl (snd att) in
            elift2 (fun e => fun acc => (attname,e)::acc) e acc
        in
        elift2 (ENew prov) rcr (fold_right proc_one init_rec el)
      | ERecord prov el =>
        let init_rec := esuccess nil in
        let proc_one (att:string * lrergo_expr) (acc:eresult (list (string * laergo_expr))) :=
            let attname := fst att in
            let e := resolve_ergo_expr tbl (snd att) in
            elift2 (fun e => fun acc => (attname,e)::acc) e acc
        in
        elift (ERecord prov) (fold_right proc_one init_rec el)
      | ECallFun prov fname el =>
        let rfname := resolve_function_name prov tbl (None,fname) in
        let init_el := esuccess nil in
        let proc_one (e:lrergo_expr) (acc:eresult (list laergo_expr)) : eresult (list laergo_expr) :=
            elift2
              cons
              (resolve_ergo_expr tbl e)
              acc
        in
        elift2 (ECallFun prov) rfname (fold_right proc_one init_el el)
      | ECallFunInGroup prov gname fname el =>
        let rgname := resolve_contract_name prov tbl gname in
        let init_el := esuccess nil in
        let proc_one (e:lrergo_expr) (acc:eresult (list laergo_expr)) : eresult (list laergo_expr) :=
            elift2
              cons
              (resolve_ergo_expr tbl e)
              acc
        in
        elift3 (ECallFunInGroup prov) rgname (esuccess fname) (fold_right proc_one init_el el)
      | EMatch prov e0 ecases edefault =>
        let ec0 := resolve_ergo_expr tbl e0 in
        let eccases :=
            let proc_one acc (ecase : lrergo_pattern * lrergo_expr) :=
                let (pcase, pe) := ecase in
                let apcase := resolve_ergo_pattern tbl pcase in
                eolift (fun apcase =>
                          eolift
                            (fun acc =>
                               elift (fun x => (apcase, x)::acc)
                                     (resolve_ergo_expr tbl pe)) acc)
                       apcase
            in
            fold_left proc_one ecases (esuccess nil)
        in
        let ecdefault := resolve_ergo_expr tbl edefault in
        eolift
          (fun ec0 : laergo_expr =>
             eolift
               (fun eccases : list (laergo_pattern * laergo_expr) =>
                  elift
                    (fun ecdefault : laergo_expr =>
                    EMatch prov ec0 eccases ecdefault)
                    ecdefault) eccases) ec0
      | EForeach prov foreachs econd e2 =>
        let re2 := resolve_ergo_expr tbl e2 in
        let recond :=
            match econd with
            | None => esuccess None
            | Some econd => elift Some (resolve_ergo_expr tbl econd)
            end
        in
        let init_e := esuccess nil in
        let proc_one
              (foreach:string * lrergo_expr)
              (acc:eresult (list (string * laergo_expr)))
            : eresult (list (string * laergo_expr)) :=
            let v := fst foreach in
            let e := resolve_ergo_expr tbl (snd foreach) in
            elift2 (fun e => fun acc => (v,e)::acc)
                 e
                 acc
        in
        elift3 (EForeach prov)
               (fold_right proc_one init_e foreachs)
               recond
               re2
      end.

    (** Name resolution for statements *)
    Fixpoint resolve_ergo_stmt
             (tbl:namespace_table)
             (e:lrergo_stmt) : eresult laergo_stmt :=
      match e with
      | SReturn prov e => elift (SReturn prov) (resolve_ergo_expr tbl e)
      | SFunReturn prov e => elift (SFunReturn prov) (resolve_ergo_expr tbl e)
      | SThrow prov e =>  elift (SThrow prov) (resolve_ergo_expr tbl e)
      | SCallClause prov e0 fname el =>
        let init_el := esuccess nil in
        let proc_one (e:lrergo_expr) (acc:eresult (list laergo_expr)) : eresult (list laergo_expr) :=
            elift2
              cons
              (resolve_ergo_expr tbl e)
              acc
        in
        elift3 (SCallClause prov)
               (resolve_ergo_expr tbl e0)
               (esuccess fname)
               (fold_right proc_one init_el el)
      | SSetState prov e1 s2 =>
        elift2 (SSetState prov)
               (resolve_ergo_expr tbl e1)
               (resolve_ergo_stmt tbl s2)
      | SEmit prov e1 s2 =>
        elift2 (SEmit prov)
               (resolve_ergo_expr tbl e1)
               (resolve_ergo_stmt tbl s2)
      | SLet prov v ta e1 s2 =>
        let rta :=
            match ta with
            | None => esuccess None
            | Some ta => elift Some (resolve_ergo_type tbl ta)
            end
        in
        elift3 (SLet prov v)
               rta
               (resolve_ergo_expr tbl e1)
               (resolve_ergo_stmt tbl s2)
      | SIf prov e1 s2 s3 =>
        elift3 (SIf prov)
               (resolve_ergo_expr tbl e1)
               (resolve_ergo_stmt tbl s2)
               (resolve_ergo_stmt tbl s3)
      | SEnforce prov e1 os2 s3 =>
        let rs2 :=
            match os2 with
            | None => esuccess None
            | Some s2 => elift Some (resolve_ergo_stmt tbl s2)
            end
        in
        elift3 (SEnforce prov)
               (resolve_ergo_expr tbl e1)
               rs2
               (resolve_ergo_stmt tbl s3)
      | SMatch prov e0 scases sdefault =>
        let ec0 := resolve_ergo_expr tbl e0 in
        let sccases :=
            let proc_one acc (scase : lrergo_pattern * lrergo_stmt) :=
                let (pcase, pe) := scase in
                let apcase := resolve_ergo_pattern tbl pcase in
                eolift (fun apcase =>
                          eolift
                            (fun acc =>
                               elift (fun x => (apcase, x)::acc)
                                     (resolve_ergo_stmt tbl pe)) acc)
                       apcase
            in
            fold_left proc_one scases (esuccess nil)
        in
        let scdefault := resolve_ergo_stmt tbl sdefault in
        eolift
          (fun ec0 : laergo_expr =>
             eolift
               (fun sccases : list (laergo_pattern * laergo_stmt) =>
                  elift
                    (fun scdefault : laergo_stmt =>
                    SMatch prov ec0 sccases scdefault)
                    scdefault) sccases) ec0
      end.

    (** Name resolution for lambdas *)

    Definition resolve_ergo_function
               (module_ns:namespace_name)
               (tbl:namespace_table)
               (f:lrergo_function) : eresult laergo_function :=
      let prov := f.(function_annot) in
      let rbody :=
          match f.(function_body) with
          | None => esuccess None
          | Some body => elift Some (resolve_ergo_expr tbl body)
          end
      in
      elift2 (mkFunc prov)
             (resolve_ergo_type_signature tbl f.(function_sig))
             rbody.
    
    Definition resolve_ergo_clause
               (module_ns:namespace_name)
               (tbl:namespace_table)
               (c:ergo_clause) : eresult laergo_clause :=
      let prov := c.(clause_annot) in
      let rcname := c.(clause_name) in
      let rbody :=
          match c.(clause_body) with
          | None => esuccess None
          | Some body => elift Some (resolve_ergo_stmt tbl body)
          end
      in
      elift2 (mkClause prov rcname)
             (resolve_ergo_type_signature tbl c.(clause_sig))
             rbody.

    Definition resolve_ergo_clauses
               (module_ns:namespace_name)
               (tbl:namespace_table)
               (cl:list ergo_clause) : eresult (list laergo_clause) :=
      emaplift (resolve_ergo_clause module_ns tbl) cl.

    Definition resolve_ergo_contract
               (module_ns:namespace_name)
               (tbl:namespace_table)
               (c:lrergo_contract) : eresult laergo_contract :=
      let prov := c.(contract_annot) in
      let rtemplate := resolve_ergo_type tbl c.(contract_template) in
      let rstate :=
          match c.(contract_state) with
          | None => esuccess None
          | Some state => elift Some (resolve_ergo_type tbl state)
          end
      in
      elift3 (mkContract prov)
             rtemplate
             rstate
             (resolve_ergo_clauses module_ns tbl c.(contract_clauses)).

    Definition resolve_ergo_declaration
               (ctxt:namespace_ctxt)
               (d:lrergo_declaration)
      : eresult (laergo_declaration * namespace_ctxt) :=
      let module_ns : namespace_name := ctxt.(namespace_ctxt_namespace) in
      let tbl : namespace_table := ctxt.(namespace_ctxt_current) in
      match d with
      | DImport prov id =>
        elift (fun x => (DImport prov id, x)) (resolve_one_import ctxt id)
      | DType prov td =>
        let ln := td.(type_declaration_name) in
        let an := absolute_name_of_local_name module_ns ln in
        let ctxt := add_type_to_namespace_ctxt_current ctxt ln an in
        elift (fun x => (DType prov x, ctxt)) (resolve_ergo_type_declaration module_ns tbl td)
      | DStmt prov st =>
        elift (fun x => (DStmt prov x, ctxt)) (resolve_ergo_stmt tbl st)
      | DConstant prov ln e =>
        let an := absolute_name_of_local_name module_ns ln in
        let ctxt := add_constant_to_namespace_ctxt_current ctxt ln an in
        elift (fun x => (DConstant prov ln x, ctxt)) (resolve_ergo_expr tbl e)
      | DFunc prov ln fd =>
        let an := absolute_name_of_local_name module_ns ln in
        let ctxt := add_function_to_namespace_ctxt_current ctxt ln an in
        elift (fun x => (DFunc prov an x, ctxt)) (resolve_ergo_function module_ns tbl fd)
      | DContract prov ln c  =>
        let an := absolute_name_of_local_name module_ns ln in
        let ctxt := add_contract_to_namespace_ctxt_current ctxt ln an in
        elift (fun x => (DContract prov an x, ctxt)) (resolve_ergo_contract module_ns tbl c)
      | DSetContract prov rn e1  =>
        eolift (fun an =>
                  elift (fun x => (DSetContract prov an x, ctxt))
                        (resolve_ergo_expr tbl e1))
               (resolve_contract_name prov tbl rn)
      end.

    Definition resolve_ergo_declarations
               (ctxt:namespace_ctxt)
               (decls: list lrergo_declaration)
      : eresult (list ergo_declaration * namespace_ctxt) :=
      elift_context_fold_left
        resolve_ergo_declaration
        decls
        ctxt.

    Definition silently_resolve_ergo_declarations
               (ctxt:namespace_ctxt)
               (decls: list lrergo_declaration)
      : eresult namespace_ctxt :=
      elift snd (resolve_ergo_declarations ctxt decls).

  End NameResolution.

  Section Top.
    Definition init_namespace_ctxt : namespace_ctxt :=
      empty_namespace_ctxt no_namespace.

    Definition patch_cto_imports
               (ctxt_ns:namespace_name)
               (decls: list lrergo_declaration) : list lrergo_declaration :=
      if is_builtin_import ctxt_ns
      then (DImport dummy_provenance (ImportSelf dummy_provenance ctxt_ns)) :: decls
      else
        (* Add built-in modules to import, first.
           Make sure to add current namespace to the list of imports - i.e., import self. *)
        (DImport dummy_provenance (ImportAll dummy_provenance hyperledger_namespace))
          :: (DImport dummy_provenance (ImportSelf dummy_provenance ctxt_ns))
          :: decls.

    (* Resolve imports for Ergo *)
    Definition patch_ergo_imports
               (ctxt_ns:namespace_name)
               (decls: list lrergo_declaration) : list lrergo_declaration :=
      if is_builtin_import ctxt_ns
      then app decls (DImport dummy_provenance (ImportSelf dummy_provenance ctxt_ns) :: nil)
      else
        (* Add built-in modules to import, first.
           Make sure to add current namespace to the list of imports - i.e., import self. *)
        (DImport dummy_provenance (ImportAll dummy_provenance hyperledger_namespace))
          ::(DImport dummy_provenance (ImportAll dummy_provenance stdlib_namespace))
          ::(DImport dummy_provenance (ImportSelf dummy_provenance ctxt_ns))
          :: decls.
      
    (* New namespace *)
    Definition new_cto_package_namespace
               (ctxt:namespace_ctxt)
               (ns:namespace_name)
               (m:lrergo_module)
      : eresult namespace_ctxt :=
      if is_builtin_import ns
      then esuccess ctxt
      else
        let builtin_cto_imports :=
            (DImport dummy_provenance (ImportAll dummy_provenance hyperledger_namespace))
              :: (DImport dummy_provenance (ImportSelf dummy_provenance ns))
              :: nil
        in
        let ctxt := new_namespace_scope ctxt ns in
        let ctxt := namespace_ctxt_of_ergo_module ctxt m in (* XXX Pre-populate namespace for CTO modules to handle not-yet-declared names *)
        silently_resolve_ergo_declarations ctxt builtin_cto_imports.

    Definition new_ergo_module_namespace
               (ctxt:namespace_ctxt)
               (ns:namespace_name)
      : eresult namespace_ctxt :=
      if is_builtin_import ns
      then esuccess ctxt
      else
        let builtin_cto_imports :=
            (DImport dummy_provenance (ImportAll dummy_provenance hyperledger_namespace))
              ::(DImport dummy_provenance (ImportAll dummy_provenance stdlib_namespace))
              ::(DImport dummy_provenance (ImportSelf dummy_provenance ns))
              :: nil
        in
        let ctxt := new_namespace_scope ctxt ns in
        silently_resolve_ergo_declarations ctxt builtin_cto_imports.

    (* Resolve a CTO package *)
    Definition resolve_cto_package
               (ctxt:namespace_ctxt)
               (cto:lrcto_package) : eresult (laergo_module * namespace_ctxt) :=
      let m := cto_package_to_ergo_module cto in
      let module_ns := m.(module_namespace) in
      let ctxt := new_namespace_scope ctxt module_ns in
      let ctxt := namespace_ctxt_of_ergo_module ctxt m in (* XXX Pre-populate namespace for CTO modules to handle not-yet-declared names *)
      let declarations := m.(module_declarations) in
      let ctxt_ns := ctxt.(namespace_ctxt_namespace) in
      elift
        (fun nc =>
           (mkModule
              m.(module_annot)
                  module_ns
                  (fst nc), snd nc))
        (resolve_ergo_declarations
           ctxt
           (patch_cto_imports module_ns declarations)).

    Definition resolve_ergo_module
               (ctxt:namespace_ctxt)
               (m:lrergo_module) : eresult (laergo_module * namespace_ctxt) :=
      let module_ns := m.(module_namespace) in
      let ctxt := new_namespace_scope ctxt module_ns in
      let declarations := m.(module_declarations) in
      let ctxt_ns := ctxt.(namespace_ctxt_namespace) in
      elift
        (fun nc =>
           (mkModule
              m.(module_annot)
                  module_ns
                  (fst nc), snd nc))
        (resolve_ergo_declarations
           ctxt
           (patch_ergo_imports module_ns declarations)).

    Definition resolve_ergo_modules
               (ctxt:namespace_ctxt)
               (ml:list lrergo_module) : eresult (list laergo_module * namespace_ctxt) :=
      elift_context_fold_left
        resolve_ergo_module
        ml
        ctxt.

    Definition resolve_cto_packages
               (ctxt:namespace_ctxt)
               (ctos:list lrcto_package) : eresult (list laergo_module * namespace_ctxt) :=
      let ctxt := namespace_ctxt_of_cto_packages ctxt ctos in (* XXX Pre-populate namespace for CTO modules to handle not-yet-declared names *)
      elift_context_fold_left
        resolve_cto_package
        ctos
        ctxt.

    Definition resolve_ergo_input
               (ctxt:namespace_ctxt)
               (input:lrergo_input) : eresult (laergo_module * namespace_ctxt) :=
      match input with
      | InputCTO cto =>
        resolve_cto_package ctxt cto
      | InputErgo m =>
        resolve_ergo_module ctxt m
      end.

    Fixpoint split_ctos_and_ergos (inputs:list lrergo_input)
      : (list lrcto_package * list lrergo_module) :=
      match inputs with
      | nil => (nil, nil)
      | InputCTO cto :: rest =>
        let split_rest := split_ctos_and_ergos rest in
        (cto :: (fst split_rest), snd split_rest)
      | InputErgo ml :: rest =>
        let split_rest := split_ctos_and_ergos rest in
        (fst split_rest, ml :: (snd split_rest))
      end.

    Definition resolve_ergo_inputs
               (ctxt:namespace_ctxt)
               (il:list lrergo_input) : eresult (list laergo_module * namespace_ctxt) :=
      elift_context_fold_left
        resolve_ergo_input
        il
        ctxt.

    Definition resolve_ergo_inputs_ctos_first
               (ctxt:namespace_ctxt)
               (inputs:list lrergo_input) : eresult (list laergo_module * namespace_ctxt) :=
      let (ctos, mls) := split_ctos_and_ergos inputs in
      let rctos := resolve_cto_packages ctxt ctos in
      eolift (fun ectos =>
                let mlctos := fst ectos in
                let rmls := resolve_ergo_modules (snd ectos) mls in
                elift (fun emls => (mlctos ++ (fst emls), snd emls)) rmls)
             rctos.

  End Top.

  Section Examples.
    Local Open Scope string.
    Definition ergo_typed1 : lrergo_type_declaration :=
      mkErgoTypeDeclaration
        dummy_provenance
        "c1"
        (ErgoTypeConcept
           None
           (("a", ErgoTypeBoolean dummy_provenance)
              ::("b", (ErgoTypeClassRef dummy_provenance (None, "c3")))::nil)).

    Definition ergo_typed2 : lrergo_type_declaration :=
      mkErgoTypeDeclaration
        dummy_provenance
        "c2"
        (ErgoTypeConcept
           None
           (("c", ErgoTypeBoolean dummy_provenance)
              ::("d", (ErgoTypeClassRef dummy_provenance (None, "c1")))::nil)).

    Definition ergo_funcd1 : lrergo_function :=
      mkFunc
        dummy_provenance
        (mkErgoTypeSignature
           dummy_provenance
           nil
           (ErgoTypeBoolean dummy_provenance)
           None
           None)
        None.
    
    Definition ergo_funcd2 : lrergo_function :=
      mkFunc
        dummy_provenance
        (mkErgoTypeSignature
           dummy_provenance
           nil
           (ErgoTypeBoolean dummy_provenance)
           None
           None)
        (Some (ECallFun dummy_provenance "addFee" nil)).

    Definition ergo_clause2 : lrergo_clause :=
      mkClause
        dummy_provenance
        "addFee2"
        (mkErgoTypeSignature
           dummy_provenance
           nil
           (ErgoTypeBoolean dummy_provenance)
           None
           None)
        (Some (SReturn dummy_provenance (ECallFun dummy_provenance "addFee" nil))).

    Definition ergo_contractd1 : lrergo_contract :=
      mkContract
        dummy_provenance
        (ErgoTypeBoolean dummy_provenance)
        None
        (ergo_clause2::nil).
    
    Definition ergo_module1 : lrergo_module :=
      mkModule
        dummy_provenance
        "n1"
        (DImport dummy_provenance (ImportAll dummy_provenance "n2")
        ::DFunc dummy_provenance "addFee" ergo_funcd1
        ::DContract dummy_provenance "MyContract" ergo_contractd1
        ::DType dummy_provenance ergo_typed1
        ::DType dummy_provenance ergo_typed2::nil).
    
    Definition ergo_typed3 : lrergo_type_declaration :=
      mkErgoTypeDeclaration
        dummy_provenance
        "c3"
        (ErgoTypeConcept
           None
           (("a", ErgoTypeBoolean dummy_provenance)
              ::("b", ErgoTypeString dummy_provenance)::nil)).

    Definition ergo_typed_top : lrergo_type_declaration :=
      mkErgoTypeDeclaration
        dummy_provenance
        "top"
        (ErgoTypeGlobal
           (ErgoTypeAny dummy_provenance)).

    Definition ergo_module2 : lrergo_module :=
      mkModule
        dummy_provenance "n2" (DType dummy_provenance ergo_typed3::nil).

    Definition ergo_hl : lrergo_module :=
      mkModule
        dummy_provenance hyperledger_namespace (DType dummy_provenance ergo_typed_top::nil).

    Definition ergo_stdlib : lrergo_module :=
      mkModule
        dummy_provenance stdlib_namespace (DType dummy_provenance ergo_typed_top::nil).

    Definition ml1 : list lrergo_module := ergo_hl :: ergo_stdlib :: ergo_module2 :: ergo_module1 :: nil.
    Definition aml1 := resolve_ergo_modules (empty_namespace_ctxt "TEST") ml1.
    (* Eval vm_compute in aml1. *)

    Definition ml2 : list lrergo_module := ergo_hl :: ergo_stdlib :: ergo_module2 :: nil.
    Definition aml2 := resolve_ergo_modules (empty_namespace_ctxt "TEST") ml2.
    (* Eval vm_compute in aml2. *)

    Definition aml3 := elift (fun mc => resolve_ergo_module (snd mc) ergo_module1) aml2.
    (* Eval vm_compute in aml3. *)
  End Examples.
  
End ErgoNameResolution.
