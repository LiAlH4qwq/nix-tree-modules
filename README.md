# nix-tree-modules

A strict directory tree of switchable NixOS-style modules — the **`here` DSL**.

Every module lives at `a/b/.../z/default.nix`, and its option path equals its
directory path under a scope root. A module may take an injected read-only
`here` handle, and may return a `here` attribute that declares its switch
metadata, sub-options and gated config. The library walks the tree and
translates each module into a plain Nix module with a generated public
`enable`, a computed read-only final, and (optionally) premise gating over
other switches in the same or a related scope.

It has no concrete scope settings: the scope registry schema and evaluator are
provided, while the actual namespace, scope roots and dependency DAG are
supplied by the caller.

## Outputs

- `lib` — the library (`mkTree`, `translateModule`, `evalPremise`,
  `mkSwitchRefType`, `mkPremiseType`, `mkSwitchOptionType`, `scopeModule`,
  `mkScopes`).
- `checks.<system>.switch` — regression tests for the switch machinery.
- `formatter.<system>` — `nixfmt`.

Consume it as a flake input and expose the library through your own `lib`:

```nix
# flake.nix
inputs.nix-tree-modules.url = "github:lialh4qwq/nix-tree-modules";

outputs = { nixpkgs, nix-tree-modules, ... }: {
  lib = nixpkgs.lib.extend (_: _: {
    nix-tree-modules = nix-tree-modules.lib;
  });
};
```

```sh
nix flake check   # run the regression tests
nix fmt           # format
```

## The `here` DSL

A module may take an injected read-only `here` handle (its file/path/own-subtree
config) and may return a `here` attribute declaring its switch metadata, options
and gated config:

```nix
{ here, lib, ... }:
{
  here.switch = {
    generate    = true;          # explicit bool; true generates the public <path>.enable
    default     = false;         # default of the generated enable
    description = "…";           # description of the generated enable
    premise     = <premise>;     # boolean over other switches
  };
  here.options = { /* sub-options, placed at <scope-root>.<path>.* */ };
  here.option  = <option>;       # an option at <scope-root>.<path> itself
  here.apply   = { /* gated config */ };

  # normal module surface is also honoured: `imports`, `options`, `config`.
}
```

Injected handle (read only): `here.file`, `here.path`, `here.config` (the config
at this node's own subtree), `here.options`.

### Semantics

- Generated per module at path `p` in scope with root `R`:
  - `R.<p>.enable` — public, only when `generate = true`.
  - `R.<p>.switch` — internal metadata, only when `generate = true`.
  - `R.internal.final.<p>.enable` — read-only computed final (always generated).
- Gating (there is no `configGating`): config is gated iff `generate` is true or
  `premise` is non-empty; `final = (if generate then <p>.enable else true) && premiseOk`.
- No switch and empty premise → a transparent/support node: config unconditional.
- `premise` is a boolean algebra over switch references:
  - `[ "a" "b" ]` — a path (one switch); a leading `"here"` makes it relative to
    the current node; `"a/b/c"` is equivalent. A list is never an AND.
  - `{ scope ? <self>; path = [ … ]; quant = "any" | "all"; }` — explicit ref.
  - `{ all = [ … ]; }` / `{ any = [ … ]; }` / `{ not = …; }` — combinators.
  A cross-scope ref is legal only along the scope DAG and reads the target's
  computed `internal.final`; a missing target errors immediately.
- `here.option` declares the node path itself as a leaf option (for modules whose
  own path is an attrset/submodule); it cannot be combined with `generate`.

A module without `here` is imported as-is (plain module).

### Strict tree rules

- Every module is a directory module at `a/b/.../z/default.nix`.
- Only a file named `default.nix` is a module. Any other `*.nix` in a module
  tree is an error.
- A directory may be **both** a module (`default.nix`) and a parent of child
  modules.
- Names starting with `_` are skipped by the walker.
- The option path equals the directory path under the scope root, e.g.
  `home/modules/gui/niri/default.nix` → `liuxu.home.gui.niri.*`.
- Do not add local `imports = [ ./child ]` inside a walked tree — the walker
  collects children.
- If a module lives at a different path than its options, either move the file
  (preferred) or give the walker a matching `base`.

### Scope registry

The library ships the registry *schema* and evaluator, not a registry. The
caller supplies ordinary modules setting `config.namespace` and
`config.scopes`; `mkScopes` merges them with `scopeModule` and evaluates them:

```nix
{
  config.namespace = [ "liuxu" ];
  config.scopes.nixos = {
    root = config.namespace ++ [ "nixos" ];
    deps.home = {
      cardinality = "many";
      instances = args: builtins.attrValues args.config.home-manager.users;
    };
  };
}
```

```nix
lib.nix-tree-modules.mkScopes {
  modules = [ ./scopes ];
}
```

`mkScopes` returns the evaluated `scopes` registry; `scopeModule` is exported
for callers that want to compose it into their own `lib.evalModules` call.

- `scopes.<name>.root` — option path prefix of the scope (required).
- `scopes.<name>.deps.<to>` — allowed premise edges with `cardinality`
  (`one`/`many`), `defaultQuant` (`any`/`all`), optional `prefix`, and
  `instances` (`args -> [ instanceConfig ]`, required for `many`).
- `scopes.<name>.switches` — set to `false` to disable switch generation in a
  scope (options-only scopes).

`mkTree` takes the resulting registry and forwards it verbatim; it is never
reinterpreted here.

## Layout

```
src/default.nix   public entry point (re-exports)
src/scopes.nix    scope registry schema + evaluator
src/switch.nix    switch translation + cross-scope premise resolution
src/tree.nix      strict tree walker
src/tests/        regression tests (a small example tree + assertions)
```

## License

MIT — see [LICENSE](./LICENSE).
