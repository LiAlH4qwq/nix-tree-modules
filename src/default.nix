# arbor: strict-tree switch system.
#
# Pure utilities implementing the `here` DSL: a directory tree of modules where
# every leaf is a node with a switch, options and/or gated config.  No settings
# live here; the scope registry is passed in by the caller (see `<root>/scopes`).
{ lib }:
let
  switch = import ./switch.nix { inherit lib; };
  tree = import ./tree.nix { inherit lib; };
in
{
  inherit (switch)
    mkSwitchRefType
    mkPremiseType
    mkSwitchOptionType
    evalPremise
    translateModule
    ;
  inherit (tree) mkTree;
}
