@{
    # ---------------------------------------------------------------------
    # UnmergedCommitsReport.config.psd1
    #
    # Defaults for UnmergedCommitsReport.ps1.
    # Copy this file to UnmergedCommitsReport.config.psd1 (next to the script),
    # or pass another file with -ConfigPath.
    #
    # Priority: command-line parameter > this file > built-in default.
    #
    # Paths may contain %ENVVARS% and, when relative, are resolved against the
    # folder of this config file. Switch settings must be $true or $false.
    # Remove the leading '#' of a line to activate a setting.
    # ---------------------------------------------------------------------

    # --- Repository and comparison -----------------------------------------

    # Folder of the git repository to report on (any folder inside it works).
    # Built-in default: the current directory.
    # RepoPath = 'C:\git\Repo.Name'

    # Branch to compare against. Built-in default: 'main'.
    Base = 'main'

    # Only compare these branches (wildcards allowed). Without it, every branch
    # with commits missing from the base is listed.
    # Branch = @('feature/login', 'release/*')

    # --- Commit selection ----------------------------------------------------

    # Also include remote-tracking branches (e.g. origin/feature-x).
    IncludeRemote = $true

    # Only include a remote-tracking branch when no local branch with the same name
    # exists (origin/feature-x is skipped if feature-x exists locally), so a branch
    # is never listed twice. Implies IncludeRemote.
    RemoteNotLocal = $false

    # Include merge commits (hidden by default).
    IncludeMerges = $false

    # Show the oldest commit first within each branch.
    Reverse       = $false

    # --- Output --------------------------------------------------------------

    # Folder for the HTML report. Built-in default: the folder of the script.
    OutputDir = 'reports'
    # OutputDir = '%USERPROFILE%\Documents\GitReports'

    # Write an HTML report. Use $false to only print the list to the console.
    Html = $true

    # Open the HTML report in the default browser after writing it.
    Open = $true

    # Do not print the list to the console (only write the HTML report).
    Quiet  = $false

    # --- Links in the HTML report ---------------------------------------------

    # URL template for work item references such as #1234 or AB#1234.
    # {0} is replaced by the number. Use '' to turn linking off (default).
    # WorkItemUrl = 'https://dev.azure.com/<organization>/<project>/_workitems/edit/{0}/'

    # URL template for commit ids. {0} is replaced by the full commit hash and
    # {repo} by the repository name from the git remote. Use '' to turn commit
    # links off (default).
    # CommitUrl = 'https://dev.azure.com/<organization>/<project>/_git/{repo}/commit/{0}'
}