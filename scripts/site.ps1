#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Check', 'Preview', 'Publish')]
    [string]$Action = 'Check',
    [string[]]$Paths = @(),
    [string]$Message,
    [ValidateRange(1024, 65535)]
    [int]$Port = 1313
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent

function Invoke-Git {
    & git @args
    if ($LASTEXITCODE -ne 0) { throw "Git failed (exit $LASTEXITCODE)." }
}

function Test-Site {
    $destination = Join-Path $repoRoot ('.site-work/build-' + [guid]::NewGuid().ToString('N'))
    & hugo --destination $destination --cacheDir (Join-Path $repoRoot '.site-work/hugo-cache')
    if ($LASTEXITCODE -ne 0) { throw 'Hugo build failed; nothing will be committed or pushed.' }
    if (-not (Test-Path -LiteralPath (Join-Path $destination 'index.html'))) {
        throw 'Hugo did not produce index.html.'
    }
    Write-Host "Build passed: $destination"
}

Push-Location $repoRoot
try {
    if ($Action -eq 'Check') {
        Test-Site
    } elseif ($Action -eq 'Preview') {
        Write-Host "Preview: http://localhost:$Port/ (includes drafts; Ctrl+C to stop)"
        & hugo server --bind 127.0.0.1 --port $Port --buildDrafts --disableFastRender --cacheDir (Join-Path $repoRoot '.site-work/hugo-cache')
        if ($LASTEXITCODE -ne 0) { throw 'Hugo preview stopped with an error.' }
    } else {
        if (-not $Paths.Count -or [string]::IsNullOrWhiteSpace($Message)) {
            throw 'Publish requires explicit -Paths and a -Message describing the reviewed changes.'
        }
        $branch = (Invoke-Git branch --show-current).Trim()
        if ($branch -ne 'main') { throw "Publish expects main; current branch is '$branch'." }
        if (@(Invoke-Git diff --cached --name-only).Count) {
            throw 'There are already staged changes. Review them before running Publish.'
        }
        $selected = @(foreach ($path in $Paths) {
            if ($path -match '[*?\[\]]') { throw 'Use literal file/directory paths, not wildcards.' }
            $absolute = [IO.Path]::GetFullPath($path, $repoRoot)
            if (-not $absolute.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Path must be inside this repository: $path"
            }
            $relative = [IO.Path]::GetRelativePath($repoRoot, $absolute).Replace('\', '/').TrimEnd('/')
            if ($relative -match '^(\.git|\.site-work|public)(/|$)') { throw "Not a publishable source path: $path" }
            $relative
        })
        $changed = @(
            Invoke-Git -c core.quotepath=false diff --name-only HEAD
            Invoke-Git -c core.quotepath=false ls-files --others --exclude-standard
        ) | Sort-Object -Unique
        if (-not $changed.Count) { throw 'No local changes to publish.' }
        foreach ($item in $changed) {
            $included = @($selected | Where-Object { $item -ceq $_ -or $item.StartsWith($_ + '/', [StringComparison]::Ordinal) })
            if (-not $included.Count) {
                throw "Unselected change exists: $item. Review it before publishing; no automatic staging of unrelated work."
            }
        }
        Invoke-Git fetch origin main
        $localHead = Invoke-Git rev-parse HEAD
        $remoteHead = Invoke-Git rev-parse refs/remotes/origin/main
        if ($localHead -ne $remoteHead) {
            throw 'Local main differs from origin/main. Review incoming/unpushed commits before publishing.'
        }
        Test-Site
        Write-Host 'Publishing these reviewed changes:'
        $changed | ForEach-Object { Write-Host "  $_" }
        Invoke-Git --literal-pathspecs add '--' @selected
        Invoke-Git commit -m $Message
        Invoke-Git push origin HEAD:main
        $commit = Invoke-Git rev-parse HEAD
        Write-Host "Pushed commit: $commit"
        Write-Host 'GitHub push succeeded. Cloudflare deployment is a separate step; inspect this commit before reporting the site live.'
    }
} finally {
    Pop-Location
}
