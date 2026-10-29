# Unmerged commits report

Lists commits that are not in a base branch (default: main), grouped per branch.
Also writes the result to a standalone HTML file (unless -NoHtml is used).

## Defaults
Defaults can be set in a config file, UnmergedCommitsReport.config.psd1, next to this script (or pass another file with -ConfigPath). Copy UnmergedCommitsReport.config.example.psd1     to get started. Priority: command-line > config file > built-in default.

## Parameters

### RepoPath
Folder of the git repository to report on (any folder inside the repository works).
Default: ./reports. This lets the script and its reports live in one folder outside the repositories themselves.

### Base
The branch to compare against. Default: main

### Branch
Only compare these branches with the base (one or more, wildcards allowed, e.g. -Branch feature/login, 'release/*'). Without it, every branch with commits missing from the base is listed. A name like feature/login also matches origin/feature/login when -IncludeRemote is used.

### IncludeRemote
Also include remote-tracking branches (e.g. origin/feature-x).

### IncludeMerges
Include merge commits. By default they are hidden.

### Reverse
Show the oldest commit first within each branch.

### HtmlPath
Where to write the HTML report (a relative path is relative to the current directory).
Default: <repo>-<base>-unmerged-commits-yyyy-MM-dd.html in the output folder (see -OutputDir), where <repo> is the repository name from the git remote and <base> the base branch, both in lowercase with dots, slashes and other special characters replaced by dashes.

### Html
Write an HTML report; only print the list to the console.
By default the html is generated

### Open
Open the HTML report in the default browser after it is written.
By default the report is opened.

### Quiet
Do not print the list to the console (only write the HTML report).

### WorkItemUrl
URL template used to link work item references such as #1234 (or AB#1234) in commit messages and branch names in the HTML report. {0} is replaced by the number.
Pass an empty string to turn linking off.
Default: none (no links). Set it in the config file to enable linking, e.g.
```
https://dev.azure.com/[organization]/[project]/_workitems/edit/{0}/
https://github.com/[organization]/[project]/_workitems/edit/{0}/
```

### CommitUrl
URL template used to link commit ids in the HTML report. {0} is replaced by the full commit hash and {repo} by the repository name taken from the git remote (origin, or the first remote), so one template works for every repository in the same Azure DevOps project. Pass an empty string to turn commit links off.
Default: none (no links). Set it in the config file to enable linking, e.g.
https://dev.azure.com/[organization]/[project]/_git/{repo}/commit/{0}
https://github.com/[organization]/[project]/commit/{0}

### OutputDir
Folder for the HTML report when -HtmlPath is not given.
Default: reports subfolder.

### ConfigPath
Config file to read the defaults from.
Default: UnmergedCommitsReport.config.psd1 in the folder of this script (optional).

## Examples
Reports on specific repository and writes [repo-name]-[base-branch-name]-unmerged-commits-[today].html next to the script:
```
.\UnmergedCommitsReport.ps1 -RepoPath C:\git\Repo.Name
```
or shorter
```
.\UnmergedCommitsReport.ps1 C:\git\Repo.Name
```

Reports on the repository in the current directory:
```
.\UnmergedCommitsReport.ps1
```

```
.\UnmergedCommitsReport.ps1 -NoHtml
```
```
.\UnmergedCommitsReport.ps1 -ConfigPath C:\reports\team-a.config.psd1
```
```
.\UnmergedCommitsReport.ps1 -Branch feature/login, 'release/*'
```
Writes the report but does not open it in the browser:
```
.\UnmergedCommitsReport.ps1 -NoOpen
```

```
.\UnmergedCommitsReport.ps1 -HtmlPath .\report.html
```

```
.\UnmergedCommitsReport.ps1 -Base develop -IncludeRemote -Reverse -HtmlPath C:\temp\report.html -Quiet
```