@{
    ImageName          = "mistral-coder"
    Tag                = "latest"
    CliCommand         = "vibe"

    # --- Per-mode CLI argument contract ---
    # ArgsCommon is prepended in every mode. The {{PROMPT}} token in a mode
    # array is replaced with the final prompt text; a mode without the token
    # never receives a prompt. No StreamFormatter is declared, so prompted runs
    # use ArgsHeadless.
    ArgsCommon         = @()
    ArgsInteractive    = @()
    ArgsTui            = @("{{PROMPT}}")
    ArgsHeadless       = @("-p", "{{PROMPT}}")

    # --- Per-mode container stdin/TTY contract ---
    # No StreamFormatter is declared, so StdinStream is never consulted.
    StdinInteractive   = @("-i", "-t")
    StdinTui           = @("-i", "-t")
    StdinHeadless      = @("-i")

    # Loaded before the auth check so keys defined here count as API-key auth.
    # A leading ~ is expanded to the user's home directory.
    EnvFile            = "~/.vibe/.env"

    EnvVars            = @("MISTRAL_API_KEY")
    Volumes            = @(
        "agentic-coder-vibe:/home/node/.vibe"
    )
    LogPath            = "logs/**/*.log"
    TroubleshootingTip = "Since no MISTRAL_API_KEY is detected in your environment, the container relies on config files in the agentic-coder-vibe volume. If this is a new setup or your key is missing/expired, please run the agent in interactive mode first: powershell -File .\run-agent.ps1 -c mistral ."
}
