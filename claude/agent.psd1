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

    # --- Per-mode container stdin/TTY contract ---
    # The CLI switches itself to --print when stdin is not a terminal, so the
    # two interactive modes must be given a PTY. The streamed mode pipes stdout
    # into the formatter and reads stdin from $null, so it must not ask for one.
    StdinInteractive   = @("-i", "-t")
    StdinTui           = @("-i", "-t")
    StdinHeadless      = @("-i")
    StdinStream        = @("-i")

    EnvVars            = @("ANTHROPIC_API_KEY")
    # Deliberately scoped to ~/.claude, not the whole home directory: the CLI is
    # installed under ~/.local/bin, so a mount at /home/node would shadow it and
    # pin the binary in state that outlives `docker rmi` — a rebuilt image would
    # keep running the old CLI. Rebuilding must be a complete reset.
    #
    # The accepted cost: ~/.claude.json sits beside this directory rather than
    # in it, and holds per-directory trust plus onboarding state, so interactive
    # TUI runs re-prompt for folder trust. Prompted runs are unaffected — print
    # mode skips the gate and reads credentials from ~/.claude/.credentials.json.
    Volumes            = @(
        "agentic-coder-claude:/home/node/.claude"
    )
    LogPath            = "debug/*.txt"
    TroubleshootingTip = "Since you are using Google/Anthropic OAuth (no ANTHROPIC_API_KEY detected), the session token inside the Docker volume may have expired or is missing. Please run the agent in interactive TUI mode first to complete the authentication flow: powershell -File .\run-agent.ps1 -c claude ."
}
