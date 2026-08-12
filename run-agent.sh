#!/bin/bash

# --- Config & Variables ---
ENGINE="gemini"
ROLE="coder"
RAW_PROMPT=""
HAS_PROMPT=false
PROJECT_PATH=""
VERBOSE=false
TUI=false

# Locate Script Directory
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# --- Parse Command Line Arguments ---
while [ $# -gt 0 ]; do
  case "$1" in
    -c|--container|--engine)
      if [ -n "$2" ]; then
        ENGINE="$2"
      fi
      shift 2
      ;;
    -r|--role|--mode)
      if [ -n "$2" ]; then
        ROLE="$2"
      fi
      shift 2
      ;;
    -p|--prompt)
      if [ -n "$2" ]; then
        RAW_PROMPT="$2"
        HAS_PROMPT=true
      fi
      shift 2
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -t|--tui)
      TUI=true
      shift
      ;;
    *)
      # Non-option argument
      if [ -z "$PROJECT_PATH" ] && [ -d "$1" ]; then
        PROJECT_PATH="$1"
        shift
      else
        # Treat all remaining arguments combined as the prompt
        RAW_PROMPT="$*"
        HAS_PROMPT=true
        break
      fi
      ;;
  esac
done

# Load Pluggable Engine Driver Config (lives alongside the engine's Dockerfile)
VERBOSE_FLAG=""
STREAM_FORMATTER=""
ENV_FILE=""
ARGS_COMMON=()
ARGS_INTERACTIVE=()
ARGS_TUI=()
ARGS_HEADLESS=()
ARGS_STREAM=()
ENGINE_DIR="$SCRIPT_DIR/$ENGINE"
CONF_FILE="$ENGINE_DIR/agent.conf"
if [ ! -f "$CONF_FILE" ]; then
  echo "❌ Error: Engine '$ENGINE' is not a valid driver config (file not found: $CONF_FILE)."
  ENGINE_LIST=""
  for driver in "$SCRIPT_DIR"/*/agent.conf; do
    [ -f "$driver" ] || continue
    ENGINE_LIST="${ENGINE_LIST:+$ENGINE_LIST, }$(basename "$(dirname "$driver")")"
  done
  echo "💡 Available engines: $ENGINE_LIST"
  exit 1
fi

source "$CONF_FILE"

# --- Container Engine Detection ---
CONTAINER_ENGINE="docker"
if command -v podman >/dev/null 2>&1; then
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    if podman info >/dev/null 2>&1; then
      CONTAINER_ENGINE="podman"
    fi
  fi
fi

# --- Load Local Env File if the engine driver declares one (e.g. Mistral's ~/.vibe/.env) ---
if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$line" ]] && continue
    # Parse key=value
    if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
      key="${BASH_REMATCH[1]}"
      val="${BASH_REMATCH[2]}"
      # Strip outer quotes if any
      val="${val#\"}"
      val="${val%\"}"
      val="${val#\'}"
      val="${val%\'}"
      if [ -z "${!key}" ]; then
        export "$key"="$val"
      fi
    fi
  done < "$ENV_FILE"
fi

if [ "$CONTAINER_ENGINE" = "podman" ]; then
  if ! podman info >/dev/null 2>&1; then
    echo "❌ Error: Podman is installed but not running or responsive."
    exit 1
  fi
  echo "🐳 Using Podman container engine."
else
  if ! docker info >/dev/null 2>&1; then
    echo "❌ Error: Docker daemon is not running."
    if command -v colima >/dev/null 2>&1; then
      echo "💡 Colima was detected on your machine. You can start it using:"
      echo "   colima start"
    fi
    exit 1
  fi
fi


# --- Resolve Host Path ---
resolve_path() {
  local target="$1"
  if [ -d "$target" ]; then
    echo "$(cd "$target" && pwd)"
  else
    echo ""
  fi
}

if [ -n "$PROJECT_PATH" ]; then
  HOST_PATH=$(resolve_path "$PROJECT_PATH")
else
  HOST_PATH=$(pwd)
  echo "ℹ️  No project path specified. Defaulting to current directory: $HOST_PATH"
fi

# --- Branch Safety Check (single-repo, writable runs only) ---
# Prevent an autonomous agent from editing the working tree while checked out on
# a shared/default branch. Only runs when the mount root is itself a git repo
# root and the workspace is writable (coder role); parent-dir/context mounts and
# read-only design/spec runs skip this check.
if [ "$AGENT_TESTING" != "true" ] && [ "$ROLE" != "design" ] && [ "$ROLE" != "spec" ]; then
  if git -C "$HOST_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1 && \
     [ "$(git -C "$HOST_PATH" rev-parse --show-toplevel 2>/dev/null)" = "$HOST_PATH" ]; then
    CURRENT_BRANCH=$(git -C "$HOST_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null)
    case "$CURRENT_BRANCH" in
      main|master|develop|development|trunk|release)
        echo "🛑 Refusing to launch: workspace is on default/shared branch '$CURRENT_BRANCH'."
        echo "💡 Switch to a working branch first, e.g.:"
        echo "   git -C \"$HOST_PATH\" switch -c my-work-branch"
        exit 1
        ;;
    esac
    echo "🌿 Branch check OK: workspace on '$CURRENT_BRANCH'."
  else
    echo "ℹ️  Workspace is not a single git repo root — skipping branch safety check."
  fi
fi

# --- Authentication Mode Check ---
IS_ENV_AUTH=false
ENV_ARGS=()
for var in "${ENV_VARS[@]}"; do
  if [ -n "${!var}" ]; then
    IS_ENV_AUTH=true
    ENV_ARGS+=("-e" "$var=${!var}")
    echo "🔑 Mode: API Key Authentication ($var detected)"
    break
  fi
done

if [ "$IS_ENV_AUTH" = false ]; then
  echo "👤 Mode: OAuth / Local Credentials Authentication (no API key detected in host environment)"
  echo "ℹ️  Authentication tokens will be securely saved in persistent Docker volumes."
fi

# --- Check for prompt.txt or prompt.md if no command line prompt was provided ---
if [ "$HAS_PROMPT" = false ]; then
  if [ -f "$HOST_PATH/prompt.txt" ]; then
    RAW_PROMPT=$(cat "$HOST_PATH/prompt.txt")
    HAS_PROMPT=true
    echo "📄 Found prompt.txt in project directory: $HOST_PATH/prompt.txt"
  elif [ -f "$HOST_PATH/prompt.md" ]; then
    RAW_PROMPT=$(cat "$HOST_PATH/prompt.md")
    HAS_PROMPT=true
    echo "📄 Found prompt.md in project directory: $HOST_PATH/prompt.md"
  elif [ -f "$(pwd)/prompt.txt" ]; then
    RAW_PROMPT=$(cat "$(pwd)/prompt.txt")
    HAS_PROMPT=true
    echo "📄 Found prompt.txt in current working directory: $(pwd)/prompt.txt"
  elif [ -f "$(pwd)/prompt.md" ]; then
    RAW_PROMPT=$(cat "$(pwd)/prompt.md")
    HAS_PROMPT=true
    echo "📄 Found prompt.md in current working directory: $(pwd)/prompt.md"
  fi
fi


# --- Resolve Guidelines and Roles ---
FINAL_PROMPT="$RAW_PROMPT"
WORKSPACE_MOUNT_FLAG="rw"

if [ "$HAS_PROMPT" = true ]; then
  # 1. Load global guidelines if they exist
  GUIDELINES=""
  if [ -f "$SCRIPT_DIR/guidelines.txt" ]; then
    GUIDELINES=$(cat "$SCRIPT_DIR/guidelines.txt")
  fi

  # 2. Handle roles and append role-specific instructions
  ROLE_INSTRUCTIONS=""
  if [ "$ROLE" = "design" ] || [ "$ROLE" = "spec" ]; then
    WORKSPACE_MOUNT_FLAG="ro"
    ROLE_INSTRUCTIONS="### Specification Writing Mode
You are running in DESIGN & SPECIFICATION mode. The workspace is mounted as READ-ONLY. You cannot edit files or compile code. Your task is to analyze the codebase and write specifications, prompt designs, or plan drafts. Deliver all your findings as markdown outputs in the chat."
    echo "🛡️  Role: Design & Specification (Workspace mounted as READ-ONLY)"
  else
    echo "🛠️  Role: Coder (Workspace mounted as Read-Write)"
  fi

  # Combine guidelines
  COMBINED_GUIDELINES=""
  if [ -n "$GUIDELINES" ]; then
    COMBINED_GUIDELINES="$GUIDELINES"
  fi
  if [ -n "$ROLE_INSTRUCTIONS" ]; then
    if [ -n "$COMBINED_GUIDELINES" ]; then
      COMBINED_GUIDELINES="$COMBINED_GUIDELINES"$'\n\n'"$ROLE_INSTRUCTIONS"
    else
      COMBINED_GUIDELINES="$ROLE_INSTRUCTIONS"
    fi
  fi

  if [ -n "$COMBINED_GUIDELINES" ]; then
    FINAL_PROMPT="$RAW_PROMPT"$'\n\n'"---"$'\n\n'"### Global Guidelines & Execution Rules"$'\n\n'"$COMBINED_GUIDELINES"
    echo "📜 Appended safety guidelines and role rules."
  fi
fi

# --- Container Run Arguments & Mount Flags ---
CONTAINER_RUN_ARGS=()
if [ "$CONTAINER_ENGINE" = "podman" ]; then
  CONTAINER_RUN_ARGS+=("--userns=keep-id")
  if [[ "$WORKSPACE_MOUNT_FLAG" != *",z"* ]]; then
    WORKSPACE_MOUNT_FLAG="${WORKSPACE_MOUNT_FLAG},z"
  fi
fi

RUN_CMD=("$CONTAINER_ENGINE" run)
if [ "$AGENT_TESTING" = "true" ] && [ "$IS_ENV_AUTH" = false ]; then
  RUN_CMD=("false")
fi

if [ "$HAS_PROMPT" = true ]; then
  echo "📝 Prompt:"
  echo "$RAW_PROMPT"
  echo ""

  # Set terminal title if the first line is <= 50 characters
  FIRST_LINE=$(echo "$RAW_PROMPT" | head -n 1)
  if [ -n "$FIRST_LINE" ] && [ ${#FIRST_LINE} -le 50 ]; then
    echo -ne "\033]0;${FIRST_LINE}\007"
  fi
fi

# --- File Ownership Check ---
if command -v id >/dev/null 2>&1; then
  CURRENT_UID=$(id -u)
  NON_OWNED_FILES=$(find "$HOST_PATH" -maxdepth 3 ! -user "$CURRENT_UID" -print -quit 2>/dev/null)
  if [ -n "$NON_OWNED_FILES" ]; then
    echo "⚠️  Warning: Found files/directories in your workspace not owned by your user (UID $CURRENT_UID):"
    find "$HOST_PATH" -maxdepth 3 ! -user "$CURRENT_UID" 2>/dev/null | head -n 5
    echo "💡 This can cause Podman/Docker to fail with permission or 'lsetxattr: operation not permitted' errors."
    echo "👉 You may want to run: sudo chown -R \$(id -u):\$(id -g) \"$HOST_PATH\""
    echo ""
  fi
fi

# Check if Container Image exists locally, build if missing
IMAGE_FULL_NAME="$IMAGE_NAME:$TAG"
if [ -z "$($CONTAINER_ENGINE images -q "$IMAGE_FULL_NAME" 2>/dev/null)" ]; then
  echo "⚠️  Container image '$IMAGE_FULL_NAME' not found locally."
  DOCKERFILE_PATH="$ENGINE_DIR"
  if [ -d "$DOCKERFILE_PATH" ]; then
    echo "🔨 Building Container image '$IMAGE_FULL_NAME' from $DOCKERFILE_PATH..."
    $CONTAINER_ENGINE build -t "$IMAGE_FULL_NAME" "$DOCKERFILE_PATH"
    if [ $? -ne 0 ]; then
      echo "❌ Failed to build Container image '$IMAGE_FULL_NAME'."
      exit 1
    fi
    echo "✅ Container image '$IMAGE_FULL_NAME' built successfully!"
  else
    echo "❌ Error: Dockerfile directory not found at $DOCKERFILE_PATH. Cannot build image."
    exit 1
  fi
fi

echo "🚀 Starting Coder Container [Engine: $ENGINE]..."
echo "📂 Mounting Host Path: $HOST_PATH -> /workspace ($WORKSPACE_MOUNT_FLAG)"
if [ "$HAS_PROMPT" = true ] && [ "$TUI" != true ]; then
  echo "📺 Real-time terminal output active."
else
  echo "📺 Real-time terminal output active. Type 'exit' to quit."
fi
echo "--------------------------------------------------------"

# --- Assemble CLI Arguments from the Engine Driver's Per-Mode Contract ---
# The driver declares one array per invocation mode; the runner picks the mode
# and knows nothing about any vendor's flag grammar.
STREAMING=false
MODE_ARGS=()
EXEC_LABEL=""
if [ "$HAS_PROMPT" = true ]; then
  if [ "$TUI" = true ]; then
    MODE_ARGS=("${ARGS_TUI[@]}")
    EXEC_LABEL="$CLI_COMMAND [prompt + guidelines]"
  elif [ -n "$STREAM_FORMATTER" ]; then
    MODE_ARGS=("${ARGS_STREAM[@]}")
    STREAMING=true
    EXEC_LABEL="$CLI_COMMAND -p [prompt + guidelines] (streaming real-time output)"
  else
    MODE_ARGS=("${ARGS_HEADLESS[@]}")
    EXEC_LABEL="$CLI_COMMAND -p [prompt + guidelines]"
  fi
else
  MODE_ARGS=("${ARGS_INTERACTIVE[@]}")
fi

# Substitute the driver's {{PROMPT}} token (a standalone argument, never a substring)
CMD_ARGS=()
for arg in "${ARGS_COMMON[@]}" "${MODE_ARGS[@]}"; do
  if [ "$arg" = "{{PROMPT}}" ]; then
    CMD_ARGS+=("$FINAL_PROMPT")
  else
    CMD_ARGS+=("$arg")
  fi
done

# Honour -v only when the driver names a verbose flag the mode has not already declared
if [ "$VERBOSE" = true ] && [ -n "$VERBOSE_FLAG" ]; then
  case " ${CMD_ARGS[*]} " in
    *" $VERBOSE_FLAG "*) ;;
    *)
      CMD_ARGS+=("$VERBOSE_FLAG")
      EXEC_LABEL="$EXEC_LABEL (with $VERBOSE_FLAG)"
      ;;
  esac
fi

# --- Container stdin / TTY Flags ---
# Docker refuses to attach stdin to a TTY-enabled container unless stdin really
# is a terminal, so -t is only requested when stdin and stdout both are. The
# streamed path pipes stdout into the formatter and takes stdin from /dev/null,
# so it never asks for a TTY.
STDIN_ARGS=("-i")
if [ "$STREAMING" != true ] && [ -t 0 ] && [ -t 1 ]; then
  STDIN_ARGS+=("-t")
fi

DOCKER_ARGS=(
  "${STDIN_ARGS[@]}" --rm
  "${CONTAINER_RUN_ARGS[@]}"
  -v "$HOST_PATH:/workspace:$WORKSPACE_MOUNT_FLAG"
  "${ENV_ARGS[@]}"
  "${VOLUMES[@]}"
  "$IMAGE_NAME:$TAG"
  "$CLI_COMMAND" "${CMD_ARGS[@]}"
)

if [ "$HAS_PROMPT" = true ]; then
  echo "🤖 Executing: $EXEC_LABEL"
else
  echo "🤖 Launching interactive CLI TUI..."
fi

if [ "$STREAMING" = true ]; then
  set -o pipefail
  STDBUF_PREFIX=""
  if command -v stdbuf >/dev/null 2>&1; then
    STDBUF_PREFIX="stdbuf -oL"
  fi
  $STDBUF_PREFIX "${RUN_CMD[@]}" "${DOCKER_ARGS[@]}" < /dev/null | python3 -u "$ENGINE_DIR/$STREAM_FORMATTER"
else
  "${RUN_CMD[@]}" "${DOCKER_ARGS[@]}"
fi

EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "--------------------------------------------------------"
  echo "❌ Container exited with error code $EXIT_CODE."
  if [ -n "$LOG_PATH" ] && [ ${#VOLUMES[@]} -gt 1 ]; then
    VOLUME_MAPPING="${VOLUMES[1]}"
    VOLUME_NAME="${VOLUME_MAPPING%%:*}"
    echo "🔍 Extracting latest logs from container volume '$VOLUME_NAME'..."
    "$CONTAINER_ENGINE" run --rm -v "${VOLUME_NAME}:/volume" alpine sh -c 'latest_log=$(ls -t /volume/'"$LOG_PATH"' 2>/dev/null | head -n 1); if [ -f $latest_log ]; then echo === Latest Logs: $latest_log ===; tail -n 100 $latest_log; fi'
  fi
  if [ "$IS_ENV_AUTH" = false ]; then
    echo "💡 Troubleshooting: $TROUBLESHOOTING_TIP"
  fi
  exit $EXIT_CODE
fi
