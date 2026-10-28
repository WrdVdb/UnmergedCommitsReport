<#
.SYNOPSIS
    Lists commits that are not in a base branch (default: main), grouped per branch.
    Also writes the result to a standalone HTML file (unless -NoHtml is used).

.DESCRIPTION
    Defaults can be set in a config file, UnmergedCommitsReport.config.psd1, next to this
    script (or pass another file with -ConfigPath). Copy UnmergedCommitsReport.config.example.psd1
    to get started. Priority: command-line parameter > config file > built-in default.

.PARAMETER RepoPath
    Folder of the git repository to report on (any folder inside the repository works).
    Default: the current directory. This lets the script and its reports live in
    one folder outside the repositories themselves.

.PARAMETER Base
    The branch to compare against. Default: main

.PARAMETER Branch
    Only compare these branches with the base (one or more, wildcards allowed,
    e.g. -Branch feature/login, 'release/*'). Without it, every branch with
    commits missing from the base is listed. A name like feature/login also
    matches origin/feature/login when -IncludeRemote is used.

.PARAMETER IncludeRemote
    Also include remote-tracking branches (e.g. origin/feature-x).

.PARAMETER IncludeMerges
    Include merge commits. By default they are hidden.

.PARAMETER Reverse
    Show the oldest commit first within each branch.

.PARAMETER HtmlPath
    Where to write the HTML report (a relative path is relative to the current directory).
    Default: <repo>-<base>-unmerged-commits-yyyy-MM-dd.html in the output folder (see -OutputDir),
    where <repo> is the repository name from the git remote and <base> the base branch,
    both in lowercase with dots, slashes and other special characters replaced by dashes.

.PARAMETER NoHtml
    Do not write an HTML report; only print the list to the console.

.PARAMETER NoOpen
    Do not open the HTML report in the default browser after it is written.
    By default the report is opened.

.PARAMETER Quiet
    Do not print the list to the console (only write the HTML report).

.PARAMETER WorkItemUrl
    URL template used to link work item references such as #1234 (or AB#1234)
    in commit messages and branch names in the HTML report. {0} is replaced by
    the number.
    Pass an empty string to turn linking off.
    Default: none (no links). Set it in the config file to enable linking, e.g.
    https://dev.azure.com/<organization>/<project>/_workitems/edit/{0}/

.PARAMETER CommitUrl
    URL template used to link commit ids in the HTML report. {0} is replaced by the
    full commit hash and {repo} by the repository name taken from the git remote
    (origin, or the first remote), so one template works for every repository in the
    same Azure DevOps project. Pass an empty string to turn commit links off.
    Default: none (no links). Set it in the config file to enable linking, e.g.
    https://dev.azure.com/<organization>/<project>/_git/{repo}/commit/{0}

.PARAMETER OutputDir
    Folder for the HTML report when -HtmlPath is not given.
    Default: the folder of this script.

.PARAMETER ConfigPath
    Config file to read the defaults from.
    Default: UnmergedCommitsReport.config.psd1 in the folder of this script (optional).

.EXAMPLE
    .\UnmergedCommitsReport.ps1 -RepoPath C:\git\Repo.Name
    Reports on that repository and writes repo-name-branchname-unmerged-commits-<today>.html
    next to the script.

.EXAMPLE
    .\UnmergedCommitsReport.ps1
    Reports on the repository in the current directory.

.EXAMPLE
    .\UnmergedCommitsReport.ps1 -NoHtml

.EXAMPLE
    .\UnmergedCommitsReport.ps1 -ConfigPath C:\reports\team-a.config.psd1

.EXAMPLE
    .\UnmergedCommitsReport.ps1 -Branch feature/login, 'release/*'

.EXAMPLE
    .\UnmergedCommitsReport.ps1 -NoOpen
    Writes the report but does not open it in the browser.

.EXAMPLE
    .\UnmergedCommitsReport.ps1 -HtmlPath .\report.html

.EXAMPLE
    .\UnmergedCommitsReport.ps1 -Base develop -IncludeRemote -Reverse -HtmlPath C:\temp\report.html -Quiet
#>
[CmdletBinding()]
param(
    [string]$RepoPath = '.',
    [string]$Base = 'main',
    [string[]]$Branch,
    [switch]$IncludeRemote,
    [switch]$IncludeMerges,
    [switch]$Reverse,
    [string]$HtmlPath,
    [switch]$NoHtml,
    [switch]$NoOpen,
    [switch]$Quiet,
    [string]$WorkItemUrl,
    [string]$CommitUrl,
    [string]$OutputDir,
    [string]$ConfigPath
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# --- Settings from the config file -----------------------------------------
# Priority: command-line parameter > config file > built-in default.
$scriptDir  = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$configFile = if ($ConfigPath) { $ConfigPath } else { Join-Path $scriptDir 'UnmergedCommitsReport.config.psd1' }

if ($ConfigPath -and -not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    Write-Error "Config file '$ConfigPath' does not exist."
    exit 1
}

if (Test-Path -LiteralPath $configFile -PathType Leaf) {
    $configFile = (Resolve-Path -LiteralPath $configFile).ProviderPath
    $configDir  = Split-Path $configFile -Parent

    try { $config = Import-PowerShellDataFile -LiteralPath $configFile }
    catch {
        Write-Error "Could not read config file '$configFile': $($_.Exception.Message)"
        exit 1
    }
    Write-Verbose "Using config file '$configFile'."

    # setting name -> kind. Paths may use %ENVVARS% and are relative to the config file's folder.
    $settingKinds = @{
        RepoPath      = 'path';   OutputDir     = 'path'
        Base          = 'string'; WorkItemUrl   = 'string'; CommitUrl = 'string'
        Branch        = 'list'
        IncludeRemote = 'switch'; IncludeMerges = 'switch'; Reverse   = 'switch'
        NoHtml        = 'switch'; NoOpen        = 'switch'; Quiet     = 'switch'
    }

    foreach ($key in @($config.Keys)) {
        if (-not $settingKinds.ContainsKey($key)) {
            Write-Warning "Unknown setting '$key' in '$configFile' (ignored)."
            continue
        }
        if ($PSBoundParameters.ContainsKey($key)) { continue }   # the command line wins
        if ($key -eq 'NoHtml' -and $PSBoundParameters.ContainsKey('HtmlPath')) { continue }

        $value = $config[$key]
        $kind  = $settingKinds[$key]

        if ($kind -eq 'switch') {
            if ($value -isnot [bool]) {
                Write-Warning "Setting '$key' in '$configFile' must be `$true or `$false (ignored)."
                continue
            }
        }
        elseif ($kind -eq 'list') {
            $value = @($value | ForEach-Object { [string]$_ })
        }
        else {
            if ($value -isnot [string]) {
                Write-Warning "Setting '$key' in '$configFile' must be text (ignored)."
                continue
            }
            if ($kind -eq 'path') {
                if (-not $value) { continue }
                $value = [Environment]::ExpandEnvironmentVariables($value)
                if (-not [System.IO.Path]::IsPathRooted($value)) { $value = Join-Path $configDir $value }
            }
        }

        Set-Variable -Name $key -Value $value
    }
}

$Branch = @($Branch | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

if ($NoHtml -and $HtmlPath) {
    Write-Error '-NoHtml cannot be combined with -HtmlPath.'
    exit 1
}

# --- Sanity checks ---------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Error 'git was not found in PATH.'
    exit 1
}

if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
    Write-Error "Repository folder '$RepoPath' does not exist."
    exit 1
}

$script:RepoFullPath = (Resolve-Path -LiteralPath $RepoPath).ProviderPath
if ($script:RepoFullPath.Length -gt 3) { $script:RepoFullPath = $script:RepoFullPath.TrimEnd('\', '/') }

# Every git call goes through this helper so it always targets the repository from -RepoPath.
function Invoke-Git { & git -C $script:RepoFullPath @args }

Invoke-Git rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "'$script:RepoFullPath' is not inside a git repository."
    exit 1
}

Invoke-Git rev-parse --verify --quiet $Base 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Base branch '$Base' does not exist."
    exit 1
}

# --- Repository name (from the remote) and default report location ---------
# Repository name = last part of the remote URL (https, ssh and visualstudio.com forms alike).
function Get-RemoteRepoName {
    $remotes = @(Invoke-Git remote 2>$null)
    if ($remotes.Count -eq 0) { return $null }
    $remoteName = if ($remotes -contains 'origin') { 'origin' } else { $remotes[0] }
    $url = @(Invoke-Git remote get-url $remoteName 2>$null)[0]
    if (-not $url) { return $null }
    $url = ($url.Trim() -replace '/+$', '') -replace '\.git$', ''
    $segment = ($url -split '[/:]')[-1]
    if (-not $segment) { return $null }
    [uri]::UnescapeDataString($segment)
}

# Lowercase, and everything except letters, digits, _ and - becomes a dash (dots, slashes, spaces...).
function ConvertTo-FileNamePart([string]$Text) {
    ($Text.ToLowerInvariant() -replace '[^a-z0-9_-]+', '-').Trim('-')
}

$remoteRepoName = Get-RemoteRepoName
$repoRoot       = Invoke-Git rev-parse --show-toplevel 2>$null
$repoName       = if ($remoteRepoName) { $remoteRepoName }
                  elseif ($repoRoot)   { Split-Path $repoRoot -Leaf }
                  else                 { 'repository' }

if (-not $NoHtml -and -not $HtmlPath) {
    $outDir    = if ($OutputDir) { $OutputDir } else { $scriptDir }
    $fileRepo  = (ConvertTo-FileNamePart $repoName)
    $fileBase  = (ConvertTo-FileNamePart $Base)
    if (-not $fileRepo) { $fileRepo = 'repo' }
    if (-not $fileBase) { $fileBase = 'base' }
    $HtmlPath  = Join-Path $outDir ('{0}-{1}-unmerged-commits-{2}.html' -f $fileRepo, $fileBase, (Get-Date -Format 'yyyy-MM-dd'))
}

# --- Find branches that contain commits not in $Base -----------------------
$namespaces = @('refs/heads')
if ($IncludeRemote) { $namespaces += 'refs/remotes' }

$branches = @(
    Invoke-Git for-each-ref --no-merged $Base --format='%(refname)' @namespaces |
        Where-Object { $_ -and $_ -notmatch '/HEAD$' } |
        ForEach-Object {
            [pscustomobject]@{
                Ref       = $_
                Name      = $_ -replace '^refs/(heads|remotes)/', ''
                ShortName = $_ -replace '^refs/(heads/|remotes/[^/]+/)', ''
            }
        } |
        Sort-Object Name
)

# --- Limit to the branches given with -Branch ------------------------------
if ($Branch.Count -gt 0) {
    $matchesBranch = {
        param($Candidate, $Pattern)
        $Candidate.Name -like $Pattern -or $Candidate.ShortName -like $Pattern
    }

    foreach ($pattern in $Branch) {
        $hit = $branches | Where-Object { & $matchesBranch $_ $pattern }
        if (-not $hit) {
            Write-Warning "'$pattern' matches no branch with commits missing from '$Base'. It may not exist, may be fully merged, or may be a remote branch (try -IncludeRemote)."
        }
    }

    $branches = @(
        $branches | Where-Object {
            $candidate = $_
            foreach ($pattern in $Branch) {
                if (& $matchesBranch $candidate $pattern) { $true; break }
            }
        }
    )
}

# --- Collect commits per branch --------------------------------------------
$results = foreach ($entry in $branches) {
    $logArgs = @('log', "$Base..$($entry.Ref)", '--date=short', '--format=%H%x09%h%x09%ad%x09%an%x09%s')
    if (-not $IncludeMerges) { $logArgs += '--no-merges' }
    if ($Reverse)            { $logArgs += '--reverse' }

    $lines = @(Invoke-Git @logArgs)
    if ($lines.Count -eq 0) { continue }

    $commits = foreach ($line in $lines) {
        $fullHash, $hash, $date, $author, $subject = $line -split "`t", 5
        [pscustomobject]@{ FullHash = $fullHash; Hash = $hash; Date = $date; Author = $author; Subject = $subject }
    }

    [pscustomobject]@{ Name = $entry.Name; Commits = @($commits) }
}
$results = @($results)

$totalCommits = 0
foreach ($r in $results) { $totalCommits += $r.Commits.Count }

# --- Console output --------------------------------------------------------
if (-not $Quiet) {
    if ($results.Count -eq 0) {
        Write-Host "No commits are missing from '$Base'." -ForegroundColor Green
    }
    else {
        foreach ($r in $results) {
            $n = $r.Commits.Count
            Write-Host ''
            Write-Host "=== $($r.Name) ($n commit$(if ($n -ne 1) { 's' })) ===" -ForegroundColor Cyan

            foreach ($c in $r.Commits) {
                Write-Host '  ' -NoNewline
                Write-Host $c.Hash -ForegroundColor Yellow -NoNewline
                Write-Host "  $($c.Date)  " -ForegroundColor Green -NoNewline
                Write-Host $c.Author.PadRight(20) -ForegroundColor Blue -NoNewline
                Write-Host "  $($c.Subject)"
            }
        }

        Write-Host ''
        Write-Host "$totalCommits commit(s) across $($results.Count) branch(es) not in '$Base'." -ForegroundColor DarkGray
    }
}

# --- HTML output -----------------------------------------------------------
if ($HtmlPath) {
    function Enc([string]$Text) { [System.Net.WebUtility]::HtmlEncode($Text) }

    # Turns #1234 / AB#1234 into a link. Runs on already-encoded text, so the lookbehind
    # skips '&#233;'-style entities. In commit messages it also skips things like 'abc#12'
    # and 'site/#12'; branch names are deliberate, so there only entities are skipped
    # (feature/#1234-login, bug_#77 and so on are linked).
    $messagePattern = '(?<![&\w/])(?:AB)?#(\d+)\b'
    $branchPattern  = '(?<!&)(?:AB)?#(\d+)'
    $workItemReplacement = if ($WorkItemUrl) {
        '<a href="' + (Enc ($WorkItemUrl -f '$1')) + '" target="_blank" rel="noopener">$0</a>'
    }
    function Add-WorkItemLink([string]$EncodedText, [string]$Pattern) {
        if ($workItemReplacement) { [regex]::Replace($EncodedText, $Pattern, $workItemReplacement) }
        else { $EncodedText }
    }
    function Format-Subject([string]$Text)    { Add-WorkItemLink (Enc $Text) $messagePattern }
    function Format-BranchName([string]$Text) { Add-WorkItemLink (Enc $Text) $branchPattern }

    $commitTemplate = $CommitUrl
    if ($commitTemplate -match '\{repo\}') {
        if ($remoteRepoName) {
            $commitTemplate = $commitTemplate.Replace('{repo}', [uri]::EscapeDataString($remoteRepoName))
        }
        else {
            Write-Warning 'Could not build commit links: the repository has no git remote to take the repository name from. Commit ids stay plain text; pass a full -CommitUrl to fix this.'
            $commitTemplate = $null
        }
    }
    function Format-CommitId($Commit) {
        $text = Enc $Commit.Hash
        if ($commitTemplate) {
            '<a href="' + (Enc ($commitTemplate -f $Commit.FullHash)) + '" target="_blank" rel="noopener">' + $text + '</a>'
        }
        else { $text }
    }

    $generated = Get-Date -Format 'yyyy-MM-dd HH:mm'

    $options = @()
    if ($Branch.Count -gt 0) { $options += 'branches: ' + ($Branch -join ', ') }
    if ($IncludeRemote) { $options += 'remote branches included' }
    if ($IncludeMerges) { $options += 'merge commits included' } else { $options += 'merge commits hidden' }
    if ($Reverse)       { $options += 'oldest first' }

    $css = @'
:root {
  color-scheme: light dark;
  --bg: #ffffff; --fg: #1f2328; --muted: #656d76; --border: #d0d7de;
  --head: #f6f8fa; --hash: #9a6700; --badge-bg: #ddf4ff; --badge-fg: #0550ae; --link: #0969da;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0d1117; --fg: #e6edf3; --muted: #8b949e; --border: #30363d;
    --head: #161b22; --hash: #d29922; --badge-bg: #0c2d6b; --badge-fg: #79c0ff; --link: #58a6ff;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0; padding: 2rem 1.25rem 3rem; background: var(--bg); color: var(--fg);
  font: 15px/1.5 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
}
main { max-width: 1000px; margin: 0 auto; }
h1 { margin: 0 0 .25rem; font-size: 1.6rem; }
h2 { margin: 2rem 0 .5rem; font-size: 1.1rem; display: flex; align-items: center; gap: .6rem; flex-wrap: wrap; }
.meta { color: var(--muted); margin: 0 0 1rem; font-size: .9rem; }
.summary { margin: 1rem 0 0; font-weight: 600; }
.badge { background: var(--badge-bg); color: var(--badge-fg); border-radius: 999px; padding: .05rem .6rem; font-size: .8rem; font-weight: 600; }
.branch { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; word-break: break-all; }
.table-wrap { overflow-x: auto; border: 1px solid var(--border); border-radius: 8px; }
table { border-collapse: collapse; width: 100%; }
th, td { text-align: left; padding: .5rem .75rem; border-bottom: 1px solid var(--border); vertical-align: top; }
tr:last-child td { border-bottom: 0; }
th { background: var(--head); font-size: .8rem; text-transform: uppercase; letter-spacing: .04em; color: var(--muted); }
td.hash { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; color: var(--hash); white-space: nowrap; }
td.date, td.author { white-space: nowrap; }
a { color: var(--link); text-decoration: none; }
td.hash a { color: inherit; }
a:hover { text-decoration: underline; }
.empty { margin-top: 2rem; color: var(--muted); }
'@

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="en">')
    [void]$sb.AppendLine('<head>')
    [void]$sb.AppendLine('<meta charset="utf-8">')
    [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1">')
    [void]$sb.AppendLine("<title>$(Enc $repoName) - Commits not in $(Enc $Base)</title>")
    [void]$sb.AppendLine("<style>$css</style>")
    [void]$sb.AppendLine('</head>')
    [void]$sb.AppendLine('<body>')
    [void]$sb.AppendLine('<main>')
    [void]$sb.AppendLine("<h1>$(Enc $repoName) - Commits not in <span class=""branch"">$(Format-BranchName $Base)</span></h1>")
    [void]$sb.AppendLine("<p class=""meta"">Generated: $generated &middot; $(Enc ($options -join ', '))</p>")

    if ($results.Count -eq 0) {
        [void]$sb.AppendLine("<p class=""empty"">No commits are missing from $(Enc $Base).</p>")
    }
    else {
        [void]$sb.AppendLine("<p class=""summary"">$totalCommits commit(s) across $($results.Count) branch(es)</p>")

        foreach ($r in $results) {
            [void]$sb.AppendLine('<section>')
            [void]$sb.AppendLine("<h2><span class=""branch"">$(Format-BranchName $r.Name)</span><span class=""badge"">$($r.Commits.Count)</span></h2>")
            [void]$sb.AppendLine('<div class="table-wrap"><table>')
            [void]$sb.AppendLine('<thead><tr><th>Commit</th><th>Date</th><th>Author</th><th>Message</th></tr></thead>')
            [void]$sb.AppendLine('<tbody>')
            foreach ($c in $r.Commits) {
                [void]$sb.AppendLine("<tr><td class=""hash"">$(Format-CommitId $c)</td><td class=""date"">$(Enc $c.Date)</td><td class=""author"">$(Enc $c.Author)</td><td>$(Format-Subject $c.Subject)</td></tr>")
            }
            [void]$sb.AppendLine('</tbody></table></div>')
            [void]$sb.AppendLine('</section>')
        }
    }

    [void]$sb.AppendLine('</main>')
    [void]$sb.AppendLine('</body>')
    [void]$sb.AppendLine('</html>')

    $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($HtmlPath)
    $dir = Split-Path $fullPath -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }

    [System.IO.File]::WriteAllText($fullPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "HTML report written to $fullPath" -ForegroundColor Green

    if (-not $NoOpen) {
        try { Invoke-Item -LiteralPath $fullPath -ErrorAction Stop }
        catch { Write-Warning "Could not open the report in the browser: $($_.Exception.Message)" }
    }
}