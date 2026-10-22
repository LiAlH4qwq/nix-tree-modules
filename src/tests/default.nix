# Regression tests for the strict-tree switch library.  Returns an attrset of
# booleans; the flake check asserts they are all true.
{ lib }:
let
  L = lib.nix-tree-modules;

  scopes = {
    app = {
      root = [
        "liuxu"
        "app"
      ];
      deps = {
        base = { };
        home = {
          cardinality = "many";
          instances = args: builtins.attrValues args.config.homes;
        };
        other = { };
      };
    };
    base = {
      root = [
        "liuxu"
        "base"
      ];
    };
    home = {
      root = [
        "liuxu"
        "home"
      ];
    };
    other = {
      root = [
        "liuxu"
        "other"
      ];
    };
  };

  scopeData =
    { config, ... }:
    {
      config.namespace = [ "test" ];
      config.scopes = {
        app = {
          root = config.namespace ++ [ "app" ];
          deps.home = {
            cardinality = "many";
            defaultQuant = "all";
            instances = args: builtins.attrValues args.config.homes;
          };
        };
        base.root = [ "test" "base" ];
        off = {
          root = config.namespace ++ [ "off" ];
          switches = false;
        };
      };
    };

  evaluatedScopes = L.mkScopes { modules = [ scopeData ]; };

  evalCfg =
    extra:
    (lib.evalModules {
      modules = [
        (L.mkTree {
          inherit scopes;
          scopeName = "app";
          dir = ./tree;
        })
        extra
      ];
    }).config;

  c0 = evalCfg { };
  c1 = evalCfg { liuxu.app.base.enable = true; };
  c2 = evalCfg { liuxu.app.group.c1.enable = true; };

  resolver = L.evalPremise {
    inherit scopes;
    from = "app";
    path = [ "group" ];
    args = {
      config = {
        liuxu.app.internal.final.a.enable = true;
        liuxu.app.internal.final.group.c1.enable = true;
        liuxu.app.internal.final.group.c2.enable = false;
        homes = {
          u1.liuxu.home.internal.final.x.enable = true;
          u2.liuxu.home.internal.final.x.enable = false;
        };
      };
    };
  };

  try = x: (builtins.tryEval x).success;
in
{
  sameScope = resolver [ "a" ];
  relative = resolver [
    "here"
    "c1"
  ];
  relativeOff =
    !(resolver [
      "here"
      "c2"
    ]);
  homeAny = resolver {
    scope = "home";
    path = [ "x" ];
  };
  homeAll =
    !(resolver {
      scope = "home";
      path = [ "x" ];
      quant = "all";
    });
  orTrue = resolver {
    any = [
      [
        "here"
        "c2"
      ]
      [
        "here"
        "c1"
      ]
    ];
  };
  orFalse =
    !(resolver {
      any = [
        [
          "here"
          "c2"
        ]
        [
          "here"
          "c2"
        ]
      ];
    });
  allTrue = resolver {
    all = [
      [ "a" ]
      [
        "here"
        "c1"
      ]
    ];
  };
  notTrue = resolver {
    not = [
      "here"
      "c2"
    ];
  };
  badEdgeThrows =
    !(try (resolver {
      scope = "other";
      path = [ "a" ];
    }));
  missingSwitchThrows =
    !(try (resolver {
      scope = "base";
      path = [ "nope" ];
    }));

  xFinalOff = !c0.liuxu.app.internal.final.x.enable;
  xMarkerOff = c0.liuxu.app.x.marker == "off";
  xFinalOn = c1.liuxu.app.internal.final.x.enable;
  xMarkerOn = c1.liuxu.app.x.marker == "on";

  groupOff = !c0.liuxu.app.internal.final.group.enable;
  groupMarkerOff = c0.liuxu.app.group.gmark == "off";
  groupOn = c2.liuxu.app.internal.final.group.enable;
  groupMarkerOn = c2.liuxu.app.group.gmark == "on";

  scopeRoot = evaluatedScopes.app.root == [
    "test"
    "app"
  ];
  scopeInternalDefault = evaluatedScopes.app.internal == [
    "test"
    "app"
    "internal"
  ];
  scopeSwitchesDefault = evaluatedScopes.base.switches;
  scopeSwitchesOff = !evaluatedScopes.off.switches;
  scopeDepsDefault = evaluatedScopes.base.deps == { };
  scopeDepCardinality = evaluatedScopes.app.deps.home.cardinality == "many";
  scopeDepDefaultQuant = evaluatedScopes.app.deps.home.defaultQuant == "all";
  scopeDepInstances =
    evaluatedScopes.app.deps.home.instances {
      config.homes = {
        u1 = "one";
        u2 = "two";
      };
    } == [
      "one"
      "two"
    ];
}
