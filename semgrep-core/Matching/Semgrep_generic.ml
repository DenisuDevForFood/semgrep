(*s: semgrep/matching/Semgrep_generic.ml *)
(* Yoann Padioleau
 *
 * Copyright (C) 2011 Facebook
 * Copyright (C) 2019, 2020 r2c
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file license.txt.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * license.txt for more details.
*)
open AST_generic

module V = Visitor_AST
module AST = AST_generic
module Err = Error_code
module PI = Parse_info
module R = Mini_rule
module Eq = Equivalence
module PM = Pattern_match
module GG = Generic_vs_generic
module MV = Metavariable
module Flag = Flag_semgrep
module MG = Matching_generic

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* Main matching engine behind sgrep. This module implements mainly
 * the expr/stmt visitor, while generic_vs_generic does the matching.
 *
 * history: this file was split in sgrep_generic.ml for -e/-f and
 * sgrep_lint_generic.ml for -rules_file. The -e/-f returns results as
 * it goes and takes a single pattern while -rules_file applies a list
 * of patterns and return a result just at the end. We have now factorized
 * the two files because of many bugs and discrepancies between the
 * two operating modes. It was easy to forget to add a new feature in
 * one of the file. Now -rules_file and -e/-f work mostly the same.
*)

(*****************************************************************************)
(* Types *)
(*****************************************************************************)

(*s: type [[Semgrep_generic.matcher]] *)
type ('a, 'b) matcher = 'a -> 'b -> Matching_generic.tout
(*e: type [[Semgrep_generic.matcher]] *)

(*****************************************************************************)
(* Debugging *)
(*****************************************************************************)

(* This is used to let the user know which rule the engine was using when
 * a Timeout or OutOfMemory exn occured.
*)
let (last_matched_rule: Mini_rule.t option ref) = ref None

let set_last_matched_rule rule f =
  last_matched_rule := Some rule;
  (* note that if this raise an exn, last_matched_rule will not be
   * reset to None and that's what we want!
  *)
  let res = f() in
  last_matched_rule := None;
  res


(*****************************************************************************)
(* Matchers *)
(*****************************************************************************)

(*s: function [[Semgrep_generic.match_e_e]] *)
let match_e_e2 cache pattern e =
  let env = MG.empty_environment cache in
  GG.m_expr pattern e env
(*e: function [[Semgrep_generic.match_e_e]] *)
let match_e_e rule cache a b =
  Common.profile_code ("rule:" ^ rule.R.id) (fun () ->
    set_last_matched_rule rule (fun () ->
      match_e_e2 cache a b))
[@@profiling]

(*s: function [[Semgrep_generic.match_st_st]] *)
let match_st_st2 cache pattern e =
  let env = MG.empty_environment cache in
  GG.m_stmt pattern e env
(*e: function [[Semgrep_generic.match_st_st]] *)
let match_st_st rule cache a b =
  Common.profile_code ("rule:" ^ rule.R.id) (fun () ->
    set_last_matched_rule rule (fun () ->
      match_st_st2 cache a b))
[@@profiling]

(*s: function [[Semgrep_generic.match_sts_sts]] *)
let match_sts_sts2 cache pattern e =
  let env = MG.empty_environment cache in
  (* When matching statements, we need not only to report whether
   * there is match, but also the actual statements that were matched.
   * Indeed, even if we want the implicit '...' at the end of
   * a sequence of statements pattern (AST_generic.Ss) to match all
   * the rest, we don't want to report the whole Ss as a match but just
   * the actually matched subset.
   *
   * TODO? do we need to generate unique key? we don't want
   * nested calls to m_stmts_deep to pollute our metavar? We need
   * to pass the key to m_stmts_deep?
  *)
  let env =
    match e with
    | [] -> env
    | stmt :: _ -> MG.extend_stmts_match_span stmt env
  in
  GG.m_stmts_deep ~less_is_ok:true pattern e env
(*e: function [[Semgrep_generic.match_sts_sts]] *)
let match_sts_sts rule cache a b =
  Common.profile_code ("rule:" ^ rule.R.id) (fun () ->
    set_last_matched_rule rule (fun () ->
      match_sts_sts2 cache a b))
[@@profiling]

(*s: function [[Semgrep_generic.match_any_any]] *)
(* for unit testing *)
let match_any_any cache pattern e =
  let env = MG.empty_environment cache in
  GG.m_any pattern e env
(*e: function [[Semgrep_generic.match_any_any]] *)

let match_t_t2 cache pattern e =
  let env = MG.empty_environment cache in
  GG.m_type_ pattern e env
let match_t_t rule cache a b =
  Common.profile_code ("rule:" ^ rule.R.id) (fun () ->
    set_last_matched_rule rule (fun () ->
      match_t_t2 cache a b))
[@@profiling]

let match_p_p2 cache pattern e =
  let env = MG.empty_environment cache in
  GG.m_pattern pattern e env
let match_p_p rule cache a b =
  Common.profile_code ("rule:" ^ rule.R.id) (fun () ->
    set_last_matched_rule rule (fun () ->
      match_p_p2 cache a b))
[@@profiling]

let match_partial_partial2 cache pattern e =
  let env = MG.empty_environment cache in
  GG.m_partial pattern e env
let match_partial_partial rule cache a b =
  Common.profile_code ("rule:" ^ rule.R.id) (fun () ->
    set_last_matched_rule rule (fun () ->
      match_partial_partial2 cache a b))
[@@profiling]

let match_at_at2 cache pattern e =
  let env = MG.empty_environment cache in
  GG.m_attribute pattern e env
let match_at_at rule cache a b =
  Common.profile_code ("rule:" ^ rule.R.id) (fun () ->
    set_last_matched_rule rule (fun () ->
      match_at_at2 cache a b))
[@@profiling]

let match_fld_fld2 cache pattern e =
  let env = MG.empty_environment cache in
  GG.m_field pattern e env
let match_fld_fld rule cache a b =
  Common.profile_code ("rule:" ^ rule.R.id) (fun () ->
    set_last_matched_rule rule (fun () ->
      match_fld_fld2 cache a b))
[@@profiling]

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

let match_rules_and_recurse (file, hook, matches) rules matcher k any x =
  rules |> List.iter (fun (pattern, rule, cache) ->
    let matches_with_env = matcher rule cache pattern x in
    if matches_with_env <> []
    then (* Found a match *)
      matches_with_env |> List.iter (fun (env : MG.tin) ->
        let env = env.mv.full_env in
        let location = Lib_AST.range_of_any (any x) in
        let tokens = lazy (Lib_AST.ii_of_any (any x)) in
        Common.push { PM. rule; file; env; location; tokens } matches;
        hook env tokens
      )
  );
  (* try the rules on substatements and subexpressions *)
  k x

let must_analyze_statement_bloom_opti_failed bf1 st =
  (* if it's empty, meaning we were not able to extract any useful specific
   * identifiers or strings from the pattern, then the pattern is too general
   * and we must analyze the stmt
  *)
  Bloom_filter.is_empty bf1
  ||
  match st.s_bf with
  (* No bloom filter, probably forgot calls to Bloom_annotation.annotate *)
  | None -> true
  (* only when the Bloom_filter says No we can skip the stmt *)
  | Some bf2 -> Bloom_filter.is_subset bf1 bf2 = Bloom_filter.Maybe

(*****************************************************************************)
(* Main entry point *)
(*****************************************************************************)

(*s: function [[Semgrep_generic.check2]] *)
let check2 ~hook ~with_caching rules equivs file lang ast =

  let rules =
    (* simple opti using regexps; the bloom filter opti might supersede this *)
    if !Flag.filter_irrelevant_rules
    then Rules_filter.filter_rules_relevant_to_file_using_regexp
        rules lang file
    else rules
  in
  if rules = []
  then []
  else begin

    let matches = ref [] in

    (* old: let prog = Normalize_AST.normalize (Pr ast) lang in
      * we were rewriting code, e.g., A != B was rewritten as !(A == B),
      * which enable some nice semantic matching demo where searching for
      * $X == $X would also find code written as a != a. The problem
      * is that if we don't do the same rewriting on the pattern, then
      * looking for $X != $X would not find anything anymore.
      * In any case, rewriting the source code is less necessary
      * now that we have user-defined code equivalences (see Equivalence.ml)
      * and this will also be less surprising (you can see the set of
      * equivalences in the equivalence file).
    *)
    let prog = (Pr ast) in

    let expr_rules = ref [] in
    let stmt_rules = ref [] in
    let stmts_rules = ref [] in
    let type_rules = ref [] in
    let pattern_rules = ref [] in
    let attribute_rules = ref [] in
    let fld_rules = ref [] in
    let partial_rules = ref [] in
    (*s: [[Semgrep_generic.check2()]] populate [[expr_rules]] and other *)
    rules |> List.iter (fun rule ->
      (* less: normalize the pattern? *)
      let any = rule.R.pattern in
      (*s: [[Semgrep_generic.check2()]] apply equivalences to rule pattern [[any]] *)
      let any = Apply_equivalences.apply equivs any in
      (*e: [[Semgrep_generic.check2()]] apply equivalences to rule pattern [[any]] *)
      let cache =
        if with_caching then
          Some (Caching.Cache.create ())
        else
          None
      in
      match any with
      | E pattern  ->
          let bf = Bloom_annotation.bloom_of_expr pattern in
          Common.push (pattern, bf, rule, cache) expr_rules
      | S pattern ->
          let bf = Bloom_annotation.bloom_of_stmt pattern in
          Common.push (pattern, bf, rule, cache) stmt_rules
      | Ss pattern -> Common.push (pattern, rule, cache) stmts_rules
      | T pattern -> Common.push (pattern, rule, cache) type_rules
      | P pattern -> Common.push (pattern, rule, cache) pattern_rules
      | At pattern -> Common.push (pattern, rule, cache) attribute_rules
      | Fld pattern -> Common.push (pattern, rule, cache) fld_rules
      | Partial pattern -> Common.push (pattern, rule, cache) partial_rules
      | _ -> failwith
               "only expr/stmt/stmts/type/pattern/annotation/field/partial patterns are supported"
    );
    (*e: [[Semgrep_generic.check2()]] populate [[expr_rules]] and other *)

    let hooks =
      { V.default_visitor with
        (*s: [[Semgrep_generic.check2()]] visitor fields *)
        V.kexpr = (fun (k, _) x ->
          (* this could be quite slow ... we match many sgrep patterns
           * against an expression recursively
          *)
          !expr_rules |> List.iter (fun (pattern, _bf, rule, cache) ->
            let matches_with_env = match_e_e rule cache pattern x in
            if matches_with_env <> []
            then (* Found a match *)
              matches_with_env |> List.iter (fun (env : MG.tin) ->
                let env = env.mv.full_env in
                let location = Lib_AST.range_of_any (E x) in
                let tokens = lazy (Lib_AST.ii_of_any (E x)) in
                Common.push { PM. rule; file; env; location; tokens } matches;
                hook env tokens
              )
          );
          (* try the rules on subexpressions *)
          (* this can recurse to find nested matching inside the
           * matched code itself *)
          k x
        );
        (*x: [[Semgrep_generic.check2()]] visitor fields *)
        (* mostly copy paste of expr code but with the _st functions *)
        V.kstmt = (fun (k, _) x ->
          (* old:
           *   match_rules_and_recurse (file, hook, matches)
           *   !stmt_rules match_st_st k (fun x -> S x) x
           * but inlined to handle specially Bloom filter in stmts for now.
          *)
          let new_stmt_rules =
            !stmt_rules |> List.filter (fun (_, bf, _, _cache) ->
              must_analyze_statement_bloom_opti_failed bf x
            )
          in
          let new_expr_rules =
            !expr_rules |> List.filter (fun (_, bf, _, _cache) ->
              must_analyze_statement_bloom_opti_failed bf x
            )
          in
          Common.save_excursion stmt_rules new_stmt_rules (fun () ->
            Common.save_excursion expr_rules new_expr_rules (fun () ->
              !stmt_rules |> List.iter (fun (pattern, _bf, rule, cache) ->
                let matches_with_env = match_st_st rule cache pattern x in
                if matches_with_env <> []
                then (* Found a match *)
                  matches_with_env |> List.iter (fun (env : MG.tin) ->
                    let env = env.mv.full_env in
                    let location = Lib_AST.range_of_any (S x) in
                    let tokens = lazy (Lib_AST.ii_of_any (S x)) in
                    Common.push
                      { PM. rule; file; env; location; tokens } matches;
                    hook env tokens
                  )
              );
              k x
            ))
        );
        (*x: [[Semgrep_generic.check2()]] visitor fields *)
        V.kstmts = (fun (k, _) x ->
          (* this is potentially slower than what we did in Coccinelle with
           * CTL. We try every sequences. Hopefully the first statement in
           * the pattern will filter lots of sequences so we need to do
           * the heavy stuff (e.g., handling '...' between statements) rarely.
           *
           * we can't factorize with match_rules_and_recurse because we
           * do things a little bit different with the matched_statements also
           * in matches_with_env here.
          *)

          !stmts_rules |> List.iter (fun (pattern, rule, cache) ->
            let matches_with_env = match_sts_sts rule cache pattern x in
            if matches_with_env <> []
            then (* Found a match *)
              matches_with_env |> List.iter (fun (env : MG.tin) ->
                let span = env.stmts_match_span in
                match Stmts_match_span.location span with
                | None -> () (* empty sequence or bug *)
                | Some location ->
                    let env = env.mv.full_env in
                    let tokens =
                      lazy (Stmts_match_span.list_original_tokens span) in
                    Common.push
                      { PM. rule; file; env; location; tokens } matches;
                    hook env tokens
              )
          );
          k x
        );
        (*e: [[Semgrep_generic.check2()]] visitor fields *)

        V.ktype_ = (fun (k, _) x ->
          match_rules_and_recurse (file, hook, matches)
            !type_rules match_t_t k (fun x -> T x) x
        );
        V.kpattern = (fun (k, _) x ->
          match_rules_and_recurse (file, hook, matches)
            !pattern_rules match_p_p k (fun x -> P x) x
        );
        V.kattr = (fun (k, _) x ->
          match_rules_and_recurse (file, hook, matches)
            !attribute_rules match_at_at k (fun x -> At x) x
        );
        V.kfield = (fun (k, _) x ->
          match_rules_and_recurse (file, hook, matches)
            !fld_rules match_fld_fld k (fun x -> Fld x) x
        );

        V.kpartial = (fun (k, _) x ->
          match_rules_and_recurse (file, hook, matches)
            !partial_rules match_partial_partial k (fun x -> Partial x) x
        );
      }
    in
    let visitor = V.mk_visitor hooks in
    (* later: opti: dont analyze certain ASTs if they do not contain
     * certain constants that interect with the pattern?
     * But this requires to analyze the pattern to extract those
     * constants (name of function, field, etc.).
    *)
    visitor prog;

    !matches |> List.rev
  end
(*e: function [[Semgrep_generic.check2]] *)

(* TODO: cant use [@@profile] because it does not handle yet label params *)
let check ~hook ~with_caching a b c d e =
  Common.profile_code "Semgrep.check"
    (fun () -> check2 ~hook ~with_caching a b c d e)

(*e: semgrep/matching/Semgrep_generic.ml *)
