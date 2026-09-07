# Dependency documentation

Upstream documentation for this project's dependencies, vendored so that agents
and humans can read the spec for the version this project actually runs.

**Nothing in the subdirectories is authored here.** Each one is a verbatim copy
of an upstream docs tree, kept under the upstream license, with its provenance
recorded in [`manifest.jsonc`](manifest.jsonc): repository, tag, commit, the
upstream subdirectory it came from, and the date it was synced.

## Keeping it current

Each entry records `pinnedBy` — where the running version is declared. When that
version moves, the vendored docs are stale. Re-sync by hand for now, using the
`repo`, `version`, `docsPath`, and `releaseAssets` fields; a script to do it
from the manifest can come later.

## Contents

| Dependency | Version | Upstream |
|---|---|---|
| [`rulesync/`](rulesync/) | v16.24.1 | [dyoshikawa/rulesync](https://github.com/dyoshikawa/rulesync) (MIT) |
