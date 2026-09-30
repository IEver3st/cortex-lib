[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Path
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw "Resource path not found: $Path"
}

$root = (Resolve-Path -LiteralPath $Path).Path
$errors = @()
$warnings = @()
$checked = 0
$manifest = Join-Path $root 'fxmanifest.lua'
$declaredFiles = @{}
$uiPage = $null

if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
    $errors += 'Missing fxmanifest.lua.'
}
else {
    $text = Get-Content -Raw -LiteralPath $manifest
    $checked++

    if ($text -notmatch 'fx_version\s+[''"]cerulean[''"]') {
        $warnings += 'fx_version cerulean not found.'
    }

    if ($text -match 'ui_page\s+[''"]https?://(localhost|127\.0\.0\.1)') {
        $errors += 'Production manifest points ui_page at localhost.'
    }

    $uiPageMatch = [regex]::Match($text, 'ui_page\s+[''"]([^''"]+)[''"]')
    if ($uiPageMatch.Success) {
        $uiPage = $uiPageMatch.Groups[1].Value.Replace('\', '/')
    }

    $filesBlock = [regex]::Match($text, '(?s)\bfiles\s*{(.*?)}')
    if (-not $filesBlock.Success) {
        $errors += 'Manifest does not declare a files block.'
    }
    else {
        [regex]::Matches($filesBlock.Groups[1].Value, '[''"]([^''"]+)[''"]') |
            ForEach-Object {
                $declaredFiles[$_.Groups[1].Value.Replace('\', '/')] = $true
            }
    }

    $quoted = [regex]::Matches($text, '[''"]([^''"]+)[''"]') |
        ForEach-Object { $_.Groups[1].Value } |
        Where-Object {
            $_ -match '[./]' -and
            $_ -notmatch '^(@|https?://)' -and
            $_ -notmatch '[*?{}]'
        }

    foreach ($relativePath in $quoted) {
        if (
            $relativePath -match '\.(lua|js|mjs|cjs|json|html|css|xml|meta)$' -and
            -not (Test-Path -LiteralPath (Join-Path $root $relativePath))
        ) {
            $errors += "Manifest reference missing: $relativePath"
        }
    }

    # Packfile assets include fonts, images and license files, not just scripts.
    foreach ($relativePath in $declaredFiles.Keys) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
            $errors += "Manifest reference missing: $relativePath"
        }
    }

    if ($uiPage -and -not $declaredFiles.ContainsKey($uiPage)) {
        $errors += "NUI page is not listed in files: $uiPage"
    }
}

if ($declaredFiles.Count -gt 0) {
    Get-ChildItem -LiteralPath (Join-Path $root 'imports') -Recurse -File -Filter '*.lua' |
        ForEach-Object {
            $relativePath = [System.IO.Path]::GetRelativePath($root, $_.FullName).Replace('\', '/')
            if (-not $declaredFiles.ContainsKey($relativePath)) {
                $errors += "Lazy-loadable import is not listed in files: $relativePath"
            }
        }
}

if ($uiPage) {
    # Cfx HTTPS resource URLs are local packfile references, not CDN assets.
    foreach ($assetFile in @($declaredFiles.Keys | Where-Object { $_ -match '\.(html|css)$' })) {
        $assetFilePath = Join-Path $root $assetFile
        if (-not (Test-Path -LiteralPath $assetFilePath -PathType Leaf)) { continue }
        $uiDirectory = Split-Path -Parent $assetFile
        $uiText = Get-Content -Raw -LiteralPath $assetFilePath
        $pattern = if ($assetFile -match '\.css$') {
            'url\(\s*[''"]?([^''"\s)]+)[''"]?\s*\)'
        }
        else { '(?:src|href)\s*=\s*[''"]([^''"]+)[''"]' }
        $assetReferences = [regex]::Matches($uiText, $pattern) |
            ForEach-Object { $_.Groups[1].Value } |
            Where-Object { $_ -notmatch '^(?:data:|#)' }

        foreach ($assetReference in $assetReferences) {
            # Cache-busting queries and fragments are URL components, not packfile paths.
            $assetReference = ($assetReference -split '[?#]', 2)[0]
            $relativePath = if ($assetReference -match '^https://cfx-nui-cortex-lib/(.+)$') {
                $Matches[1]
            }
            elseif ($assetReference -match '^(?:https?://|//)') {
                $errors += "NUI asset must be offline and owned by cortex-lib: $assetReference"
                continue
            }
            elseif ($uiDirectory) {
                (Join-Path $uiDirectory $assetReference).Replace('\', '/')
            }
            else {
                $assetReference.Replace('\', '/')
            }

            $absolutePath = [System.IO.Path]::GetFullPath((Join-Path $root $relativePath))
            $relativePath = [System.IO.Path]::GetRelativePath($root, $absolutePath).Replace('\', '/')
            if ($relativePath -match '^\.\.(?:/|$)') {
                $errors += "NUI asset escapes resource: $assetReference"
                continue
            }

            if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
                $errors += "NUI asset reference missing: $relativePath"
            }
            elseif (-not $declaredFiles.ContainsKey($relativePath)) {
                $errors += "NUI asset is not listed in files: $relativePath"
            }
        }
    }
}

Get-ChildItem -LiteralPath $root -Recurse -File |
    Where-Object { $_.FullName -notmatch '[\\/](node_modules|\.git|\.vite)[\\/]' } |
    ForEach-Object {
        $checked++

        if ($_.Extension -eq '.json') {
            try {
                Get-Content -Raw -LiteralPath $_.FullName | ConvertFrom-Json | Out-Null
            }
            catch {
                $errors += "Invalid JSON: $($_.FullName)"
            }
        }

        if ($_.Extension -in @('.xml', '.meta')) {
            try {
                [xml](Get-Content -Raw -LiteralPath $_.FullName) | Out-Null
            }
            catch {
                $errors += "Invalid XML/meta: $($_.FullName)"
            }
        }

        if (
            $_.Extension -in @('.lua', '.js', '.ts', '.html') -and
            (Select-String -LiteralPath $_.FullName -Quiet -Pattern 'AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC )?PRIVATE KEY-----')
        ) {
            $errors += "Potential secret in shipped source: $($_.FullName)"
        }
    }

$result = [ordered]@{
    resource = $root
    filesChecked = $checked
    errors = @($errors | Sort-Object -Unique)
    warnings = @($warnings | Sort-Object -Unique)
    passed = $errors.Count -eq 0
}

$result | ConvertTo-Json -Depth 5

if ($errors.Count) {
    exit 1
}

exit 0
