# AGENTS.md

Instructions for AI agents working in **nix-tree-modules**. Read this fully
before editing.

## What this repo is

The `here` DSL: a strict directory tree of switchable NixOS-style modules.
The library walks a module tree and translates each module into a plain Nix
module with a generated public `enable`, a computed read-only final, and
optional premise gating over other switches.

It is **pure utilities**. It must not contain scope definitions, settings, or
option-namespace data — the caller passes a scope registry in. See
[README.md](./README.md) for the full DSL documentation.

## Layout

| Path | Purpose |
| --- | --- |
| `flake.nix` | Flake outputs (`lib`, `checks`, `formatter`). |
| `src/default.nix` | Public entry point; re-exports the utilities. |
| `src/switch.nix` | Switch translation + cross-scope premise resolution. |
| `src/tree.nix` | Strict tree walker. |
| `src/tests/` | Regression tests: a small example tree + assertions. |
| `LICENSE` | MIT. |

## Commands

```sh
nix flake check                 # regression tests (authoritative)
nix fmt                         # format (nixfmt, rfc style) — run before committing
nix eval .#lib                  # inspect the exported library
nix build .#checks.x86_64-linux.switch   # the single test derivation
```

## Design invariants

- **No settings.** `src/` is library code only. The scope registry, option
  namespace, and all policy belong to the caller.
- Keep the strict tree walker strict: only `default.nix` is a module, `_`-prefixed
  entries are skipped, and any other `*.nix` in a walked tree is a hard error.
- `translateModule` output must remain a valid, ordinary Nix module — normal
  `imports`/`options`/`config` are honoured alongside `here`.
- Cross-scope premises are legal only along the caller-declared scope DAG; a
  missing switch must throw immediately, never silently default.

## Style rules (enforced)

- Format with `nixfmt` (rfc style) via `nix fmt`.
- **Do not use `rec`.** Use `let` with the smallest necessary scope.
- Unused function argument → `_:`, not `{ ... }:`.
- Hyphenated attribute names are valid identifiers; do not quote them.
- Prefer `lib`/`builtins` helpers over ad-hoc code.
- Prefer TS/JS or `nu`/`fish` for scripting; never install tools imperatively
  (`nix profile`, `pip install`) — use `nix run` or add a flake output.

## Git workflow (HARD RULES)

1. **Never commit on `main`.** Always create a branch: `git switch -c <type>/<name>`.
2. Keep commits focused; one logical change per commit.
3. Do not push, delete branches, or rewrite history unless the user asks.

## Known issues

- Consumers often reference this repo through a relative `path:./…` flake input.
  Relative path inputs are only resolvable while the referring flake is a local
  path; prefer a `github:` reference in committed locks.
