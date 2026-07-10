@{
    ImageName          = "agentic-coder"
    Tag                = "latest"
    CliCommand         = "agy"
    EnvVars            = @("GEMINI_API_KEY")
    Volumes            = @(
        "agentic-coder-gemini:/home/node/.gemini",
        "agentic-coder-config:/home/node/.config"
    )
    LogPath            = "antigravity-cli/log/cli-*.log"
    TroubleshootingTip = "Since you are using Google One OAuth (no GEMINI_API_KEY detected), the session token inside the Docker volume may have expired or is missing. Please run the agent in interactive TUI mode first to complete the authentication flow: powershell -File .\run-agent.ps1 -c gemini ."
}
