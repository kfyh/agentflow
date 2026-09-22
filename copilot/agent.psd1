@{
    ImageName          = "copilot-coder"
    Tag                = "latest"
    CliCommand         = "copilot"
    VerboseFlag        = "--verbose"

    # --- Per-mode CLI argument contract ---
    # ArgsCommon is prepended in every mode.
    # --allow-all grants full permission to tools, paths, and shell execution in the isolated sandbox.
    # --no-ask-user suppresses clarifying questions during automated runs.
    ArgsCommon         = @("--allow-all", "--no-ask-user")
    ArgsInteractive    = @()
    ArgsTui            = @("{{PROMPT}}")
    ArgsHeadless       = @("-p", "{{PROMPT}}")

    # --- Per-mode container stdin/TTY contract ---
    StdinInteractive   = @("-i", "-t")
    StdinTui           = @("-i", "-t")
    StdinHeadless      = @("-i")

    EnvVars            = @("COPILOT_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN")
    Volumes            = @(
        "agentic-coder-copilot:/home/node/.copilot"
    )
    LogPath            = "logs/*.log"
    TroubleshootingTip = "Since you are using GitHub OAuth (no COPILOT_GITHUB_TOKEN, GH_TOKEN, or GITHUB_TOKEN detected), the session token inside the Docker volume may have expired or is missing. Please run the agent in interactive TUI mode first to complete the authentication flow: powershell -File .\run-agent.ps1 -c copilot ."
}
