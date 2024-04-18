# Nixpkgs pkgs/by-name checker

This directory implements a program to check the [validity](#validity-checks) of the [`pkgs/by-name` Nixpkgs directory](https://github.com/NixOS/nixpkgs/tree/master/pkgs/by-name).
This is part of the implementation of [RFC 140](https://github.com/NixOS/rfcs/pull/140).

See [`CONTRIBUTING.md`](./CONTRIBUTING.md) for contributor documentation.
Below is the user documentation.

To see how it is used in Nixpkgs, see the [`check-by-name.yml` workflow](https://github.com/NixOS/nixpkgs/blob/master/.github/workflows/check-by-name.yml).


## Interface

The interface of the tool is shown with `--help`:
```
cargo run -- --help
```

The interface may be changed over time only if the CI workflow making use of it is adjusted to deal with the change appropriately.

## Validity checks

These checks are performed by this tool:

### File structure checks
- `pkgs/by-name` must only contain subdirectories of the form `${shard}/${name}`, called _package directories_.
- The `name`'s of package directories must be unique when lowercased.
- `name` is a string only consisting of the ASCII characters `a-z`, `A-Z`, `0-9`, `-` or `_`.
- `shard` is the lowercased first two letters of `name`, expressed in Nix: `shard = toLower (substring 0 2 name)`.
- Each package directory must contain a `package.nix` file and may contain arbitrary other files.

### Nix parser checks
- Each package directory must not refer to files outside itself using symlinks or Nix path expressions.

### Nix evaluation checks

Evaluate Nixpkgs with `system` set to `x86_64-linux` and check that:
- For each package directory, the `pkgs.${name}` attribute must be defined as `callPackage pkgs/by-name/${shard}/${name}/package.nix args` for some `args`.
- For each package directory, `pkgs.lib.isDerivation pkgs.${name}` must be `true`.

### Ratchet checks

Furthermore, this tool implements certain [ratchet](https://qntm.org/ratchet) checks.
This allows gradually phasing out deprecated patterns without breaking the base branch or having to migrate it all at once.
It works by not allowing new instances of the pattern to be introduced, but allowing already existing instances.
The existing instances are coming from `<BASE_NIXPKGS>`, which is then checked against `<NIXPKGS>` for new instances.
Ratchets should be removed eventually once the pattern is not used anymore.

The current ratchets are:

- New manual definitions of `pkgs.${name}` (e.g. in `pkgs/top-level/all-packages.nix`) with `args = { }`
  (see [nix evaluation checks](#nix-evaluation-checks)) must not be introduced.
- New top-level packages defined using `pkgs.callPackage` must be defined with a package directory.
  - Once a top-level package uses `pkgs/by-name`, it also can't be moved back out of it.
