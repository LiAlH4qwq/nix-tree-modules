# Strict extensible tree walker.
#
# Every module must live at `a/b/.../z/default.nix`; a directory may both be a
# module (it has a `default.nix`) and have child directories.  Any other
# `.nix` file is a hard error.  Names starting with `_` are skipped.
{ lib }:
let
  switch = import ./switch.nix { inherit lib; };
in
{
  mkTree =
    {
      scopes,
      scopeName,
      dir,
      base ? [ ],
      filter ? _: true,
    }:
    let
      walk =
        rel: d:
        let
          modulePath = base ++ rel;
          entries = builtins.readDir d;
          names = builtins.attrNames entries;
          nixFiles = builtins.filter (n: entries.${n} == "regular" && lib.hasSuffix ".nix" n) names;
          bad = builtins.filter (n: n != "default.nix") nixFiles;
          subdirs = builtins.filter (n: entries.${n} == "directory" && !(lib.hasPrefix "_" n)) names;
          leaf =
            lib.optional
              (
                entries ? "default.nix"
                && filter {
                  path = modulePath;
                  file = d + "/default.nix";
                }
              )
              (
                switch.translateModule {
                  inherit scopes scopeName;
                  path = modulePath;
                  file = d + "/default.nix";
                }
              );
        in
        if bad != [ ] then
          throw "liuxu: strict tree violation in ${toString d}: only `default.nix` is allowed, found ${lib.concatStringsSep ", " bad}"
        else
          leaf ++ lib.concatMap (n: walk (rel ++ [ n ]) (d + "/${n}")) subdirs;
    in
    {
      imports = walk [ ] dir;
    };
}
