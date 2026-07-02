# run-agent.ps1 - Centralized Startup script for Windows (PowerShell)
param (
    [Parameter(Position = 0, Mandatory = $false)]
    [string]$ProjectPath,

    [Alias("c", "engine")]
    [string]$Container = "gemini",

    [Alias("r", "mode")]
    [string]$Role = "coder",

    [Alias("p")]
    [string]$Prompt = "",

    [Alias("v", "verbose")]
    [switch]$VerboseMode,

    [Alias("t", "tui")]
    [switch]$Tui,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

# Locate Script Directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Load Pluggable Engine Driver Config
$ConfFile = Join-Path $ScriptDir "config\${Container}.psd1"
if (-not (Test-Path -Path $ConfFile -PathType Leaf)) {
    Write-Error "Engine '${Container}' is not a valid driver config (file not found: $ConfFile)."
    Write-Host "💡 Available engines: gemini, mistral, claude"
    exit 1
}

$Config = Import-PowerShellDataFile -Path $ConfFile

# --- Docker Check ---
docker info > $null 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker daemon is not running. Please start Docker Desktop or your Docker environment."
    exit 1
}

# Resolve Workspace Folder
if ($ProjectPath) {
    if (Test-Path -Path $ProjectPath -PathType Container) {
        $ResolvedPath = (Get-Item $ProjectPath).FullName
    } else {
        Write-Error "Provided path is not a valid directory: $ProjectPath"
        exit 1
    }
} else {
    $ResolvedPath = (Get-Location).Path
    Write-Host "ℹ️ No project path specified. Defaulting to current directory: $ResolvedPath"
}

# Parse Prompt
$RawPrompt = $Prompt
$HasPrompt = $false
if ($RawPrompt -ne "") {
    $HasPrompt = $true
} elseif ($RemainingArgs) {
    if ($RemainingArgs[0] -eq "-p" -or $RemainingArgs[0] -eq "--prompt") {
        if ($RemainingArgs.Count -gt 1) {
            $RawPrompt = $RemainingArgs[1]
            $HasPrompt = $true
        }
    } else {
        $RawPrompt = $RemainingArgs -join " "
        $HasPrompt = $true
    }
}

# Check for prompt.txt or prompt.md if no prompt was provided
if (-not $HasPrompt) {
    if (Test-Path -Path "${ResolvedPath}\prompt.txt" -PathType Leaf) {
        $RawPrompt = Get-Content -Raw -Path "${ResolvedPath}\prompt.txt"
        $HasPrompt = $true
        Write-Host "📄 Found prompt.txt in project directory: ${ResolvedPath}\prompt.txt"
    } elseif (Test-Path -Path "${ResolvedPath}\prompt.md" -PathType Leaf) {
        $RawPrompt = Get-Content -Raw -Path "${ResolvedPath}\prompt.md"
        $HasPrompt = $true
        Write-Host "📄 Found prompt.md in project directory: ${ResolvedPath}\prompt.md"
    } elseif (Test-Path -Path "prompt.txt" -PathType Leaf) {
        $RawPrompt = Get-Content -Raw -Path "prompt.txt"
        $HasPrompt = $true
        Write-Host "📄 Found prompt.txt in current working directory: prompt.txt"
    } elseif (Test-Path -Path "prompt.md" -PathType Leaf) {
        $RawPrompt = Get-Content -Raw -Path "prompt.md"
        $HasPrompt = $true
        Write-Host "📄 Found prompt.md in current working directory: prompt.md"
    }
}


# --- Resolve Guidelines and Roles ---
$FinalPrompt = $RawPrompt
$WorkspaceMountFlag = "rw"

if ($HasPrompt) {
    # Load guidelines.txt
    $Guidelines = ""
    $GuidelinesPath = Join-Path $ScriptDir "guidelines.txt"
    if (Test-Path -Path $GuidelinesPath -PathType Leaf) {
        $Guidelines = Get-Content -Raw -Path $GuidelinesPath
    }

    # Load role instructions
    $RoleInstructions = ""
    if ($Role -eq "design" -or $Role -eq "spec") {
        $WorkspaceMountFlag = "ro"
        $RoleInstructions = "### Specification Writing Mode`nYou are running in DESIGN & SPECIFICATION mode. The workspace is mounted as READ-ONLY. You cannot edit files or compile code. Your task is to analyze the codebase and write specifications, prompt designs, or plan drafts. Deliver all your findings as markdown outputs in the chat."
        Write-Host "🛡️  Role: Design & Specification (Workspace mounted as READ-ONLY)"
    } else {
        Write-Host "🛠️  Role: Coder (Workspace mounted as Read-Write)"
    }

    # Combine guidelines
    $CombinedGuidelines = ""
    if ($Guidelines) {
        $CombinedGuidelines = $Guidelines
    }
    if ($RoleInstructions) {
        if ($CombinedGuidelines) {
            $CombinedGuidelines = "${CombinedGuidelines}`n`n${RoleInstructions}"
        } else {
            $CombinedGuidelines = $RoleInstructions
        }
    }

    if ($CombinedGuidelines) {
        $FinalPrompt = "${RawPrompt}`n`n---`n`n### Global Guidelines & Execution Rules`n`n${CombinedGuidelines}"
        Write-Host "📜 Appended safety guidelines and role rules."
    }
}

if ($HasPrompt) {
    Write-Host "📝 Prompt:"
    Write-Host $RawPrompt
    Write-Host ""

    # Set terminal title if the first line is <= 50 characters
    $FirstLine = ($RawPrompt -split "`n")[0].Trim()
    if ($FirstLine.Length -gt 0 -and $FirstLine.Length -le 50) {
        $Host.UI.RawUI.WindowTitle = $FirstLine
    }
}

# --- Authentication Mode Check ---
$IsEnvAuth = $false
$EnvArgs = @()
foreach ($var in $Config.EnvVars) {
    $val = Get-Item -Path "env:$var" -ErrorAction SilentlyContinue
    if ($val) {
        $IsEnvAuth = $true
        $EnvArgs += @("-e", "$var=$($val.Value)")
        Write-Host "🔑 Mode: API Key Authentication ($var detected)"
        break
    }
}

if (-not $IsEnvAuth) {
    Write-Host "👤 Mode: OAuth / Local Credentials Authentication (no API key detected in host environment)"
    Write-Host "ℹ️  Authentication tokens will be securely saved in persistent Docker volumes."
}

# Resolve Volume Arguments
$VolumeArgs = @()
foreach ($vol in $Config.Volumes) {
    $VolumeArgs += @("-v", $vol)
}

Write-Host "🚀 Starting Coder Container [Engine: $($Config.ImageName)]..."
Write-Host "📂 Mounting Host Path: $ResolvedPath -> /workspace ($WorkspaceMountFlag)"
Write-Host "📺 Real-time terminal output active. Type 'exit' to quit."
Write-Host "--------------------------------------------------------"

# Assemble docker execution arguments
$DockerArgs = @("run", "-it", "--rm", "-v", "${ResolvedPath}:/workspace:${WorkspaceMountFlag}")
if ($EnvArgs) { $DockerArgs += $EnvArgs }
if ($VolumeArgs) { $DockerArgs += $VolumeArgs }
$DockerArgs += @("$($Config.ImageName):$($Config.Tag)")

# Assemble engine CLI arguments
$CmdArgs = @()
if ($Config.CliArgs) {
    $CmdArgs += $Config.CliArgs
}
if ($HasPrompt) {
    if ($Tui) {
        $CmdArgs += $FinalPrompt
    } else {
        if ($Config.StreamFormatter) {
            $CmdArgs += @("-p", $FinalPrompt, "--output-format", "stream-json", "--verbose")
        } else {
            $CmdArgs += @("-p", $FinalPrompt)
        }
    }
}
if ($VerboseMode -and $Config.VerboseFlag) {
    $CmdArgs += $Config.VerboseFlag
}

if ($HasPrompt) {
    if ($Tui) {
        if ($VerboseMode -and $Config.VerboseFlag) {
            Write-Host "🤖 Executing: $($Config.CliCommand) [prompt + guidelines] (with $($Config.VerboseFlag))"
        } else {
            Write-Host "🤖 Executing: $($Config.CliCommand) [prompt + guidelines]"
        }
    } else {
        if ($Config.StreamFormatter) {
            Write-Host "🤖 Executing: $($Config.CliCommand) -p [prompt + guidelines] (streaming real-time output)"
        } else {
            if ($VerboseMode -and $Config.VerboseFlag) {
                Write-Host "🤖 Executing: $($Config.CliCommand) -p [prompt + guidelines] (with $($Config.VerboseFlag))"
            } else {
                Write-Host "🤖 Executing: $($Config.CliCommand) -p [prompt + guidelines]"
            }
        }
    }
} else {
    Write-Host "🤖 Launching interactive CLI TUI..."
}

$DockerArgs += @($Config.CliCommand)
$DockerArgs += $CmdArgs

# Run docker
if ($HasPrompt -and -not $Tui -and $Config.StreamFormatter) {
    $FormatterPath = Join-Path $ScriptDir $Config.StreamFormatter
    $DockerArgs[1] = "-i"
    & docker $DockerArgs | python3 -u $FormatterPath
} else {
    & docker $DockerArgs
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "--------------------------------------------------------"
    Write-Host "❌ Container exited with error code $LASTEXITCODE." -ForegroundColor Red
    if (-not $IsEnvAuth) {
        Write-Host "💡 Troubleshooting: $($Config.TroubleshootingTip)" -ForegroundColor Yellow
    }
    exit $LASTEXITCODE
}
