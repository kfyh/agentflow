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

    # --- Per-mode container stdin/TTY contract ---
    # Interactive modes need a PTY; the streamed mode pipes stdout into the
    # formatter and reads stdin from $null, so it must not ask for one.
    StdinInteractive   = @("-i", "-t")
    StdinTui           = @("-i", "-t")
    StdinHeadless      = @("-i")
    StdinStream        = @("-i")

    EnvVars            = @("GEMINI_API_KEY")
    Volumes            = @(
        "agentic-coder-gemini:/home/node/.gemini",
        "agentic-coder-config:/home/node/.config"
    )
    LogPath            = "antigravity-cli/log/cli-*.log"
    TroubleshootingTip = "Since you are using Google One OAuth (no GEMINI_API_KEY detected), the session token inside the Docker volume may have expired or is missing. Please run the agent in interactive TUI mode first to complete the authentication flow: powershell -File .\run-agent.ps1 -c gemini ."
}
