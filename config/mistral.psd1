@{
    ImageName          = "mistral-coder"
    Tag                = "latest"
    CliCommand         = "vibe"
    EnvVars            = @("MISTRAL_API_KEY")
    Volumes            = @(
        "agentic-coder-vibe:/home/node/.vibe"
    )
    TroubleshootingTip = "Since no MISTRAL_API_KEY is detected in your environment, the container relies on config files in the agentic-coder-vibe volume. If this is a new setup or your key is missing/expired, please run the agent in interactive mode first: powershell -File .\run-agent.ps1 -c mistral ."
}
