#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Source,
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')][string]$BookId,
    [string]$AssetBaseUrl
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$registry = $null
if ([string]::IsNullOrWhiteSpace($Source)) {
    $registryPath = Join-Path $repoRoot 'books.local.json'
    if (-not (Test-Path -LiteralPath $registryPath)) { throw 'Provide -Source or register the book in books.local.json.' }
    $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json -AsHashtable
    if (-not $registry.ContainsKey($BookId)) { throw "No source registered for book: $BookId" }
    $Source = $registry[$BookId].source
    if ([string]::IsNullOrWhiteSpace($Source)) { throw "Empty source for book: $BookId" }
}
# Source manuscripts keep relative image paths; published HTML can use an R2 prefix.
if ([string]::IsNullOrWhiteSpace($AssetBaseUrl) -and $null -ne $registry) {
    $AssetBaseUrl = $registry[$BookId].assetBaseUrl
}
if (-not [string]::IsNullOrWhiteSpace($AssetBaseUrl)) {
    $assetUri = [uri]$AssetBaseUrl
    if (-not $assetUri.IsAbsoluteUri -or $assetUri.Scheme -ne 'https' -or $assetUri.Query -or $assetUri.Fragment -or $assetUri.UserInfo) {
        throw 'AssetBaseUrl must be an absolute HTTPS URL without credentials, query, or fragment.'
    }
    $AssetBaseUrl = $assetUri.AbsoluteUri.TrimEnd('/') + '/'
}
$sourceRoot = (Resolve-Path -LiteralPath $Source).Path
if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot '_quarto.yml'))) {
    throw 'Source must be a Quarto project containing _quarto.yml.'
}

# Build a copy so that preview/publishing does not rewrite the author's source project.
$runRoot = Join-Path $repoRoot ('.site-work/book-' + [guid]::NewGuid().ToString('N'))
$staging = Join-Path $runRoot 'source'
if ($runRoot.StartsWith($sourceRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Source may not contain the website staging directory.'
}
New-Item -ItemType Directory -Path $staging -Force | Out-Null
$excluded = @('.git', '.github', '.vscode', '.quarto', 'docs', '_book', '_publish', '_site')
foreach ($entry in Get-ChildItem -LiteralPath $sourceRoot -Force) {
    if ($entry.Name -in $excluded -or $entry.Name -like '*_files' -or $entry.Name -like '*_cache') { continue }
    if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        ($entry.PSIsContainer -and @(Get-ChildItem -LiteralPath $entry.FullName -Recurse -Force -Attributes ReparsePoint).Count)) {
        throw "Linked files/directories require manual review: $($entry.FullName)"
    }
    Copy-Item -LiteralPath $entry.FullName -Destination $staging -Recurse -Force
}
Push-Location $staging
try {
    & quarto render --to html --output-dir _publish
    if ($LASTEXITCODE -ne 0) { throw 'Quarto failed; the website book directory has not been changed.' }
} finally {
    Pop-Location
}
$output = Join-Path $staging '_publish'
if (-not (Test-Path -LiteralPath (Join-Path $output 'index.html'))) {
    throw 'No index.html in generated output; the website has not been changed.'
}
if (-not [string]::IsNullOrWhiteSpace($AssetBaseUrl)) {
    $assetRoot = [IO.Path]::GetFullPath((Join-Path $output 'assets'))
    $attributePattern = '(?i)(?<start>\b(?:src|href)\s*=\s*["''])(?<url>[^"'']+)(?<end>["''])'
    $rewrittenCount = 0
    foreach ($htmlFile in Get-ChildItem -LiteralPath $output -Filter '*.html' -Recurse -File) {
        $html = [IO.File]::ReadAllText($htmlFile.FullName)
        $rewritten = [regex]::Replace($html, $attributePattern, {
            param($match)
            $url = $match.Groups['url'].Value
            if ($url -match '^(?:[a-z][a-z0-9+.-]*:|//|#)') { return $match.Value }
            $parts = [regex]::Match($url, '^(?<path>[^?#]+)(?<tail>[?#].*)?$')
            if (-not $parts.Success) { return $match.Value }
            $localPath = [uri]::UnescapeDataString($parts.Groups['path'].Value).Replace('/', [IO.Path]::DirectorySeparatorChar)
            $resolved = [IO.Path]::GetFullPath($localPath, $htmlFile.DirectoryName)
            if (-not $resolved.StartsWith($assetRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                return $match.Value
            }
            if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Missing published asset: $resolved" }
            $relative = [IO.Path]::GetRelativePath($assetRoot, $resolved).Replace('\', '/')
            $encoded = (($relative -split '/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
            return $match.Groups['start'].Value + $AssetBaseUrl + $encoded + $parts.Groups['tail'].Value + $match.Groups['end'].Value
        })
        if ($rewritten -cne $html) {
            [IO.File]::WriteAllText($htmlFile.FullName, $rewritten, [Text.UTF8Encoding]::new($false))
            $rewrittenCount++
        }
    }
    Write-Host "Mapped assets to $AssetBaseUrl in $rewrittenCount HTML pages."
}
$booksRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'static/books'))
$target = [IO.Path]::GetFullPath((Join-Path $booksRoot $BookId))
$backup = [IO.Path]::GetFullPath((Join-Path $runRoot 'previous-website-book'))
if (-not $target.StartsWith($booksRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
    -not $backup.StartsWith($runRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Book target/backup is outside the expected directory.'
}
foreach ($path in @((Join-Path $repoRoot 'static'), $booksRoot, $target)) {
    if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Book target may not be a linked directory: $path"
    }
}
New-Item -ItemType Directory -Path $booksRoot -Force | Out-Null
$hadPrevious = Test-Path -LiteralPath $target
if ($hadPrevious) { Move-Item -LiteralPath $target -Destination $backup }
try {
    Move-Item -LiteralPath $output -Destination $target
} catch {
    if ($hadPrevious -and -not (Test-Path -LiteralPath $target)) {
        Move-Item -LiteralPath $backup -Destination $target
    }
    throw
}
Write-Host "Updated website book: $target"
if ($hadPrevious) { Write-Host "Previous files retained at: $backup" }
Write-Host "Preview path: /books/$BookId/"
Write-Host 'For a new book, add its link to the study index. Run the site Check/Preview before publishing.'
