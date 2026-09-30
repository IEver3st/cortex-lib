# Maintainer checks

Run from the repository root with Node.js, PowerShell 7 (`pwsh`) and Lua 5.4.
The suite needs no neighboring Cortex repositories, package installation or
running game client.

```powershell
node --test tests/*.test.mjs
Get-ChildItem -LiteralPath tests -Filter '*_spec.lua' | ForEach-Object {
    lua $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "Failed: $($_.Name)" }
}
Get-ChildItem -LiteralPath ui -Recurse -Filter '*.js' | ForEach-Object {
    node --check $_.FullName
    if ($LASTEXITCODE -ne 0) { throw "Invalid JavaScript: $($_.Name)" }
}
pwsh -NoProfile -File scripts/validate-resource.ps1 -Path .
git diff --check
```

The retained checks cover loaders and public API routing, callback validation,
settings persistence and rollback, focus ownership, interaction arbitration and
projection state, native menu handoffs, skill checks, overlay behavior and packaging.
They use deterministic stubs and fixtures; they do not prove FiveM or CEF behavior.

The legacy demo, retired Scaleform bridge, earlier browser preview and tests belonging
to Chat or Death are no longer part of this repository. Source-text checks that
duplicated the retained lifecycle tests or pinned an old visual treatment were
removed. Tests and developer documentation are excluded from customer ZIPs.

The current [browser UI lab](../docs/browser-lab.md) runs with `bun run dev`.
Its HTTP isolation and renderer-family coverage checks are part of the Node
suite. Interactive browser checks exercise fixtures; game callbacks remain mocks.

For runtime acceptance, use [the release checklist](../docs/release.md). The
optional `/cortexdebug` workbench requires `setr cortex_debug 1` before startup;
disable it afterward. Do not add a test script to the production manifest.
