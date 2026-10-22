# Scope registry schema and evaluator.
#
# Only the registry *shape* lives here: the option types for `namespace` and
# the per-scope `root` / `internal` / `switches` / `deps` fields.  The concrete
# registry data (which scopes exist, their namespace, and their DAG) is settings
# owned by the caller and supplied as ordinary modules.
{ lib }:
let
  inherit (lib) types mkOption;

  depType = types.submodule {
    options = {
      cardinality = mkOption {
        type = types.enum [
          "one"
          "many"
        ];
        default = "one";
        description = "Whether the target scope has one or many instances.";
      };
      defaultQuant = mkOption {
        type = types.enum [
          "any"
          "all"
        ];
        default = "any";
        description = "Default quantifier used when cardinality is many.";
      };
      prefix = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        description = "Override for the path prefix of the target switch inside an instance config.";
      };
      instances = mkOption {
        type = types.nullOr (types.functionTo (types.listOf types.raw));
        default = null;
        description = "args -> list of instance configs; required when cardinality is many.";
      };
    };
  };

  scopeModule = {
    options.namespace = mkOption {
      type = types.listOf types.str;
      description = "Global option namespace all scopes live under.";
    };

    options.scopes = mkOption {
      type = types.attrsOf (
        types.submodule (
          { config, ... }: {
            options = {
              root = mkOption {
                type = types.listOf types.str;
                description = "Option path of this scope (relative to the module system root).";
              };
              internal = mkOption {
                type = types.listOf types.str;
                default = config.root ++ [ "internal" ];
                description = "Option path prefix of this scope's `final` tree.";
              };
              switches = mkOption {
                type = types.bool;
                default = true;
                description = "Whether this scope's nodes generate switches. Disable for pure data scopes.";
              };
              deps = mkOption {
                type = types.attrsOf depType;
                default = { };
                description = "Scopes this scope may premise on.";
              };
            };
          }
        )
      );
      default = { };
    };
  };

  mkScopes =
    {
      modules ? [ ],
      specialArgs ? { },
    }:
    (lib.evalModules {
      modules = [ scopeModule ] ++ modules;
      inherit specialArgs;
    }).config.scopes;
in
{
  inherit mkScopes scopeModule;
}
