@{
    ImageName          = "agentic-coder"
    Tag                = "latest"
    CliCommand         = "agy"
    StreamFormatter    = "stream-formatter.py"

    # --- Per-mode CLI argument contract ---
    # ArgsCommon is prepended in every mode. The {{PROMPT}} token in a mode
    # array is replaced with the final prompt text; a mode without the token
    # never receives a prompt.
    ArgsCommon         = @()
    ArgsInteractive    = @()
    ArgsTui            = @("{{PROMPT}}")
    ArgsHeadless       = @("-p", "{{PROMPT}}")
    ArgsStream         = @("-p", "{{PROMPT}}", "--output-format", "stream-json")

    EnvVars            = @("GEMINI_API_KEY")
    Volumes            = @(
        "agentic-coder-gemini:/home/node/.gemini",
        "agentic-coder-config:/home/node/.config"
    )
    LogPath            = "antigravity-cli/log/cli-*.log"
    TroubleshootingTip = "Since you are using Google One OAuth (no GEMINI_API_KEY detected), the session token inside the Docker volume may have expired or is missing. Please run the agent in interactive TUI mode first to complete the authentication flow: powershell -File .\run-agent.ps1 -c gemini ."
}
