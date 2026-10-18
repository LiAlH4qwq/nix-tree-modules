# Switch translation + cross-scope premise resolution.
#
# A strict-tree module is a regular module function that may take an injected
# read-only `here` argument and may return a `here` attribute to declare its
# switch metadata, options and gated config:
#
#   { here, lib, ... }: {
#     here.switch = {
#       generate    = true;              # generate a public `enable` option
#       default     = false;             # default of the public enable
#       description = "…";               # description of the public enable
#       premise     = <premise>;         # boolean over other switches
#     };
#     here.options = { … };              # sub-options at <root>.<path>
#     here.option  = <option>;           # option at <root>.<path> itself
#     here.apply   = { … };              # config, gated by the computed final
#   }
#
# Injected handle (read only):
#
#   here.file     absolute path of this default.nix
#   here.path     path components relative to the scope root
#   here.config   config at <root>.<path> (this module's own subtree)
#   here.options  options declared under `here.options`
#
# Gating rule (no `configGating` field): config is gated iff a public switch is
# generated or a premise is given.
#   gated = generate || premise non-empty
#   final = (if generate then <path>.enable else true) && premiseOk
{ lib }:
let
  inherit (lib) types;

  # Type of a cross-scope switch reference.
  mkSwitchRefType =
    scopes:
    types.submodule {
      options = {
        scope = lib.mkOption {
          type = types.enum (builtins.attrNames scopes);
          description = "Scope the referenced switch lives in.";
        };
        path = lib.mkOption {
          type = types.listOf types.str;
          description = "Path of the switch relative to the target scope root.";
        };
        quant = lib.mkOption {
          type = types.enum [
            "any"
            "all"
          ];
          default = "any";
          description = "Quantifier when the target scope is many-valued.";
        };
      };
    };

  # A premise is a boolean algebra over switch references:
  #   "a/b/c"                        path (relative to the target scope root)
  #   { scope; path; quant; }        explicit reference
  #   { all = [ … ]; }               conjunction
  #   { any = [ … ]; }               disjunction
  #   { not = …; }                   negation
  # A path whose first component is `here` is relative to the current node.
  mkPremiseType =
    scopes:
    types.nullOr (
      types.either types.str (
        types.either (types.listOf types.str) (
          types.submodule {
            options = {
              scope = lib.mkOption {
                type = types.nullOr (types.enum (builtins.attrNames scopes));
                default = null;
                description = "Target scope of the reference; defaults to the current scope.";
              };
              path = lib.mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
                description = "Path of the referenced switch (relative to the target scope root).";
              };
              quant = lib.mkOption {
                type = types.nullOr (
                  types.enum [
                    "any"
                    "all"
                  ]
                );
                default = null;
                description = "Quantifier override for many-valued targets.";
              };
              all = lib.mkOption {
                type = types.nullOr (types.listOf types.unspecified);
                default = null;
                description = "Conjunction of premises.";
              };
              any = lib.mkOption {
                type = types.nullOr (types.listOf types.unspecified);
                default = null;
                description = "Disjunction of premises.";
              };
              not = lib.mkOption {
                type = types.nullOr types.unspecified;
                default = null;
                description = "Negated premise.";
              };
            };
          }
        )
      )
    );

  mkSwitchOptionType =
    scopes:
    types.submodule {
      options = {
        generate = lib.mkOption {
          type = types.bool;
          default = false;
          description = "Whether to generate the public `enable` switch option.";
        };
        default = lib.mkOption {
          type = types.bool;
          default = false;
          description = "Default value of the generated public `enable` option.";
        };
        description = lib.mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Description of the generated public `enable` option.";
        };
        premise = lib.mkOption {
          type = mkPremiseType scopes;
          default = null;
          description = "Boolean premise over other switches.";
        };
      };
    };

  # Recursive premise interpreter.  `path` is the current module path relative
  # to its scope root, used to resolve `here`-prefixed relative references.
  evalPremise =
    {
      scopes,
      from,
      args,
      path,
    }:
    let
      resolveRel =
        p:
        if builtins.isList p && p != [ ] && builtins.head p == "here" then path ++ builtins.tail p else p;

      edgeOf =
        { from, to }:
        if from == to then
          { }
        else
          let
            fromScope = scopes.${from} or (throw "liuxu: unknown source scope '${from}'");
          in
          fromScope.deps.${to} or (throw "liuxu: premise ${from} -> ${to} is not in the declared scope DAG");

      switchPath =
        { to, p }:
        let
          target = scopes.${to} or (throw "liuxu: unknown target scope '${to}'");
          edge = edgeOf { inherit from to; };
          prefix =
            if (edge.prefix or null) != null then
              edge.prefix
            else
              target.internal or (target.root ++ [ "internal" ]);
        in
        prefix ++ [ "final" ] ++ p ++ [ "enable" ];

      getFrom =
        cfg:
        { to, p }:
        let
          sp = switchPath { inherit to p; };
        in
        if lib.hasAttrByPath sp cfg then
          lib.attrByPath sp false cfg
        else
          throw "liuxu: premise ${from} -> ${to} references missing switch '${lib.concatStringsSep "." sp}'";

      evalRef =
        {
          scope ? from,
          p,
          quant ? null,
        }:
        let
          edge = edgeOf {
            from = from;
            to = scope;
          };
          cardinality = edge.cardinality or "one";
          q = if quant != null then quant else (edge.defaultQuant or "any");
          instances =
            if (edge.instances or null) != null then
              edge.instances args
            else if cardinality == "many" then
              throw "liuxu: premise ${from} -> ${scope} is many-valued but the edge has no `instances`"
            else
              [ args.config ];
        in
        if cardinality == "many" then
          (if q == "any" then lib.any else lib.all) (
            inst:
            getFrom inst {
              to = scope;
              p = p;
            }
          ) instances
        else
          getFrom (builtins.head instances) {
            to = scope;
            p = p;
          };

      eval =
        prem:
        if builtins.isString prem then
          evalRef { p = lib.splitString "/" prem; }
        else if builtins.isList prem then
          evalRef { p = resolveRel prem; }
        else if builtins.isAttrs prem then
          if (prem.path or null) != null then
            evalRef {
              scope = if (prem.scope or null) != null then prem.scope else from;
              p = resolveRel prem.path;
              quant = prem.quant or null;
            }
          else if (prem.all or null) != null then
            lib.all eval prem.all
          else if (prem.any or null) != null then
            lib.any eval prem.any
          else if (prem.not or null) != null then
            !(eval prem.not)
          else
            throw "liuxu: malformed premise ${builtins.toJSON prem}"
        else
          throw "liuxu: malformed premise ${builtins.toJSON prem}";
    in
    eval;

  # Translate one leaf module into a real module.
  translateModule =
    {
      scopes,
      scopeName,
      path,
      file,
    }:
    let
      scope = scopes.${scopeName} or (throw "liuxu: unknown scope '${scopeName}'");
      switchable = scope.switches or true;
      full = scope.root ++ path;
      internal = scope.internal or (scope.root ++ [ "internal" ]);
      finalPath = internal ++ [ "final" ] ++ path;
      raw = import file;
      inner = if builtins.isFunction raw then raw else _: raw;
      innerArgs = lib.functionArgs inner;
      outerArgs = (builtins.removeAttrs innerArgs [ "here" ]) // {
        config = false;
        options = false;
      };
      takesHere = innerArgs ? here;
    in
    lib.setFunctionArgs (
      args@{ config, ... }:
      let
        result = inner (
          lib.intersectAttrs innerArgs args
          // lib.optionalAttrs takesHere {
            here = {
              inherit file path;
              config = lib.attrByPath full { } config;
              options = if decl == null then { } else (decl.options or { });
            };
          }
        );
        decl = result.here or null;
      in
      if decl == null then
        result
      else
        let
          moduleKeys = [
            "config"
            "options"
            "imports"
            "meta"
            "disabledModules"
            "_class"
            "_file"
            "key"
            "require"
            "freeformType"
          ];
          normalized = {
            imports = result.imports or [ ];
            options = result.options or { };
            config = lib.recursiveUpdate (result.config or { }) (
              builtins.removeAttrs result (moduleKeys ++ [ "here" ])
            );
          };
          sw = decl.switch or { };
          generate = switchable && (sw.generate or false);
          defaultOn = sw.default or false;
          description =
            if (sw.description or null) != null then
              sw.description
            else
              "Whether to enable ${lib.concatStringsSep "." full}.";
          premise = sw.premise or null;
          hasPremise = switchable && premise != null && premise != [ ];
          applyCfg = lib.mkMerge [
            (normalized.config or { })
            (decl.apply or (decl.config or { }))
          ];
          own = if generate then lib.attrByPath (full ++ [ "enable" ]) defaultOn config else true;
          premiseOk =
            if hasPremise then
              evalPremise {
                inherit scopes;
                from = scopeName;
                inherit path args;
              } premise
            else
              true;
          finalOn = own && premiseOk;
          gated = generate || hasPremise;
          ownOptions = if decl ? option then decl.option else (decl.options or { });
          fullOptions = if ownOptions == { } then { } else lib.setAttrByPath full ownOptions;
        in
        if (decl ? option) && (decl ? options) then
          throw "liuxu: ${file} declares both `here.option` and `here.options`"
        else if (decl ? option) && generate then
          throw "liuxu: ${file} declares `here.option` and generates a switch; the option path itself would collide with `enable`"
        else
          {
            imports = normalized.imports or [ ];
            options = lib.recursiveUpdate (normalized.options or { }) (
              lib.recursiveUpdate fullOptions (
                lib.recursiveUpdate
                  (lib.optionalAttrs generate (
                    lib.setAttrByPath full {
                      switch = lib.mkOption {
                        type = mkSwitchOptionType scopes;
                        internal = true;
                        default = { };
                      };
                      enable = lib.mkOption {
                        type = types.bool;
                        default = defaultOn;
                        inherit description;
                      };
                    }
                  ))
                  (
                    lib.optionalAttrs switchable (
                      lib.setAttrByPath (finalPath ++ [ "enable" ]) (
                        lib.mkOption {
                          type = types.bool;
                          internal = true;
                          readOnly = true;
                          default = finalOn;
                        }
                      )
                    )
                  )
              )
            );
            config = lib.mkMerge [
              (lib.optionalAttrs generate (lib.setAttrByPath (full ++ [ "switch" ]) sw))
              (if gated then lib.mkIf finalOn applyCfg else applyCfg)
            ];
          }
    ) outerArgs;
in
{
  inherit
    mkSwitchRefType
    mkPremiseType
    mkSwitchOptionType
    evalPremise
    translateModule
    ;
}
