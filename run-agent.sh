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

# Load Pluggable Engine Driver Config
VERBOSE_FLAG=""
STREAM_FORMATTER=""
CLI_ARGS=()
CONF_FILE="$SCRIPT_DIR/config/$ENGINE.conf"
if [ ! -f "$CONF_FILE" ]; then
  echo "❌ Error: Engine '$ENGINE' is not a valid driver config (file not found: $CONF_FILE)."
  echo "💡 Available engines: gemini, mistral, claude"
  exit 1
fi

source "$CONF_FILE"

# --- Docker Check ---
if ! docker info >/dev/null 2>&1; then
  echo "❌ Error: Docker daemon is not running."
  if command -v colima >/dev/null 2>&1; then
    echo "💡 Colima was detected on your machine. You can start it using:"
    echo "   colima start"
  fi
  exit 1
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

# Check if Docker Image exists locally, build if missing
IMAGE_FULL_NAME="$IMAGE_NAME:$TAG"
if [ -z "$(docker images -q "$IMAGE_FULL_NAME" 2>/dev/null)" ]; then
  echo "⚠️  Docker image '$IMAGE_FULL_NAME' not found locally."
  DOCKERFILE_PATH="$SCRIPT_DIR/$ENGINE"
  if [ -d "$DOCKERFILE_PATH" ]; then
    echo "🔨 Building Docker image '$IMAGE_FULL_NAME' from $DOCKERFILE_PATH..."
    docker build -t "$IMAGE_FULL_NAME" "$DOCKERFILE_PATH"
    if [ $? -ne 0 ]; then
      echo "❌ Failed to build Docker image '$IMAGE_FULL_NAME'."
      exit 1
    fi
    echo "✅ Docker image '$IMAGE_FULL_NAME' built successfully!"
  else
    echo "❌ Error: Dockerfile directory not found at $DOCKERFILE_PATH. Cannot build image."
    exit 1
  fi
fi

echo "🚀 Starting Coder Container [Engine: $ENGINE]..."
echo "📂 Mounting Host Path: $HOST_PATH -> /workspace ($WORKSPACE_MOUNT_FLAG)"
echo "📺 Real-time terminal output active. Type 'exit' to quit."
echo "--------------------------------------------------------"

# Run the docker container
CMD_ARGS=("${CLI_ARGS[@]}")
if [ "$HAS_PROMPT" = true ]; then
  if [ "$TUI" = true ]; then
    CMD_ARGS+=("$FINAL_PROMPT")
  else
    if [ -n "$STREAM_FORMATTER" ]; then
      CMD_ARGS+=("-p" "$FINAL_PROMPT" "--output-format" "stream-json" "--verbose")
    else
      CMD_ARGS+=("-p" "$FINAL_PROMPT")
    fi
  fi
fi
if [ "$VERBOSE" = true ] && [ -n "$VERBOSE_FLAG" ]; then
  CMD_ARGS+=("$VERBOSE_FLAG")
fi

if [ "$HAS_PROMPT" = true ]; then
  if [ "$TUI" = true ]; then
    echo "🤖 Executing: $CLI_COMMAND [prompt + guidelines] ${VERBOSE_FLAG:+(with $VERBOSE_FLAG)}"
    docker run -it --rm \
      -v "$HOST_PATH:/workspace:$WORKSPACE_MOUNT_FLAG" \
      "${ENV_ARGS[@]}" \
      "${VOLUMES[@]}" \
      "$IMAGE_NAME:$TAG" \
      "$CLI_COMMAND" "${CMD_ARGS[@]}"
  else
    if [ -n "$STREAM_FORMATTER" ]; then
      echo "🤖 Executing: $CLI_COMMAND -p [prompt + guidelines] (streaming real-time output)"
      set -o pipefail
      docker run -i --rm \
        -v "$HOST_PATH:/workspace:$WORKSPACE_MOUNT_FLAG" \
        "${ENV_ARGS[@]}" \
        "${VOLUMES[@]}" \
        "$IMAGE_NAME:$TAG" \
        "$CLI_COMMAND" "${CMD_ARGS[@]}" | python3 -u "$SCRIPT_DIR/$STREAM_FORMATTER"
    else
      echo "🤖 Executing: $CLI_COMMAND -p [prompt + guidelines] ${VERBOSE_FLAG:+(with $VERBOSE_FLAG)}"
      docker run -it --rm \
        -v "$HOST_PATH:/workspace:$WORKSPACE_MOUNT_FLAG" \
        "${ENV_ARGS[@]}" \
        "${VOLUMES[@]}" \
        "$IMAGE_NAME:$TAG" \
        "$CLI_COMMAND" "${CMD_ARGS[@]}"
    fi
  fi
else
  echo "🤖 Launching interactive CLI TUI..."
  docker run -it --rm \
    -v "$HOST_PATH:/workspace:$WORKSPACE_MOUNT_FLAG" \
    "${ENV_ARGS[@]}" \
    "${VOLUMES[@]}" \
    "$IMAGE_NAME:$TAG" \
    "$CLI_COMMAND" "${CMD_ARGS[@]}"
fi

EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
  echo "--------------------------------------------------------"
  echo "❌ Container exited with error code $EXIT_CODE."
  if [ "$IS_ENV_AUTH" = false ]; then
    echo "💡 Troubleshooting: $TROUBLESHOOTING_TIP"
  fi
  exit $EXIT_CODE
fi
