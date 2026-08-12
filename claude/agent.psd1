@{
    ImageName          = "claude-coder"
    Tag                = "latest"
    CliCommand         = "claude"
    VerboseFlag        = "--verbose"
    StreamFormatter    = "stream-formatter.py"

    # --- Per-mode CLI argument contract ---
    # ArgsCommon is prepended in every mode. The {{PROMPT}} token in a mode
    # array is replaced with the final prompt text; a mode without the token
    # never receives a prompt.
    ArgsCommon         = @("--permission-mode", "bypassPermissions")
    ArgsInteractive    = @()
    ArgsTui            = @("{{PROMPT}}")
    ArgsHeadless       = @("-p", "{{PROMPT}}")
    ArgsStream         = @("-p", "{{PROMPT}}", "--output-format", "stream-json", "--verbose")

    EnvVars            = @("ANTHROPIC_API_KEY")
    Volumes            = @(
        "agentic-coder-claude:/home/node/.claude"
    )
    LogPath            = "debug/*.txt"
    TroubleshootingTip = "Since you are using Google/Anthropic OAuth (no ANTHROPIC_API_KEY detected), the session token inside the Docker volume may have expired or is missing. Please run the agent in interactive TUI mode first to complete the authentication flow: powershell -File .\run-agent.ps1 -c claude ."
}
