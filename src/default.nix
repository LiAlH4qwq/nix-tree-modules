# arbor: strict-tree switch system.
#
# Pure utilities implementing the `here` DSL: a directory tree of modules where
# every leaf is a node with a switch, options and/or gated config.  The scope
# registry schema/evaluator lives here too, but the concrete registry data
# (namespace, scope roots, and the dependency DAG) is supplied by the caller
# (see `<root>/scopes`).
{ lib }:
let
  scopes = import ./scopes.nix { inherit lib; };
  switch = import ./switch.nix { inherit lib; };
  tree = import ./tree.nix { inherit lib; };
in
{
  inherit (scopes) mkScopes scopeModule;
  inherit (switch)
    mkSwitchRefType
    mkPremiseType
    mkSwitchOptionType
    evalPremise
    translateModule
    ;
  inherit (tree) mkTree;
}
