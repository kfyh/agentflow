@{
    ImageName          = "claude-coder"
    Tag                = "latest"
    CliCommand         = "claude"
    VerboseFlag        = "--verbose"
    CliArgs            = @("--permission-mode", "bypassPermissions")
    StreamFormatter    = "claude\stream-formatter.py"
    EnvVars            = @("ANTHROPIC_API_KEY")
    Volumes            = @(
        "agentic-coder-claude:/home/node/.claude"
    )
    TroubleshootingTip = "Since you are using Google/Anthropic OAuth (no ANTHROPIC_API_KEY detected), the session token inside the Docker volume may have expired or is missing. Please run the agent in interactive TUI mode first to complete the authentication flow: powershell -File .\run-agent.ps1 -c claude ."
}
