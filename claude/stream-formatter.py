#!/usr/bin/env python3
import sys
import json

# Truncation limits (tune here).
MAX_TOOL_INPUT_STR = 400   # max length of a single string value in fallback JSON
MAX_RESULT_LINES = 30      # tool-result lines shown before head+tail truncation
RESULT_HEAD_LINES = 22     # lines kept from the start when truncating
RESULT_TAIL_LINES = 6      # lines kept from the end when truncating


def _truncate_str(s):
    if isinstance(s, str) and len(s) > MAX_TOOL_INPUT_STR:
        return s[:MAX_TOOL_INPUT_STR] + f"…(+{len(s) - MAX_TOOL_INPUT_STR} chars)"
    return s


def _truncate_values(obj):
    """Recursively truncate long string values so fallback JSON stays readable."""
    if isinstance(obj, dict):
        return {k: _truncate_values(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_truncate_values(v) for v in obj]
    return _truncate_str(obj)


def _content_summary(text):
    lines = text.splitlines()
    return f"({len(lines)} lines, {len(text)} chars)"


def format_tool_use(name, inp):
    """Return a concise, human-first description of a tool call."""
    header = f"🛠️  [Tool Use: {name}]"
    if not isinstance(inp, dict):
        return f"{header} {inp}"

    if name == "Bash":
        line = f"{header} $ {inp.get('command', '')}"
        desc = inp.get("description")
        if desc:
            line += f"\n     ↳ {desc}"
        return line

    if name in ("Read", "Edit", "MultiEdit", "NotebookEdit"):
        return f"{header} {inp.get('file_path', inp.get('notebook_path', ''))}"

    if name == "Write":
        return f"{header} {inp.get('file_path', '')} {_content_summary(inp.get('content', ''))}"

    if name in ("Glob", "Grep"):
        detail = inp.get("pattern", "")
        scope = inp.get("path") or inp.get("glob")
        if scope:
            detail += f"  (in {scope})"
        return f"{header} {detail}"

    if name in ("Task", "Agent"):
        return f"{header} {inp.get('description', '')}"

    if name == "WebFetch":
        return f"{header} {inp.get('url', '')}"

    if name == "WebSearch":
        return f"{header} {inp.get('query', '')}"

    # Fallback: pretty-printed JSON with long string values truncated.
    return f"{header}\n{json.dumps(_truncate_values(inp), indent=2)}"


def result_to_text(res):
    """Normalize tool-result content (string or list of blocks) to text."""
    if isinstance(res, str):
        return res
    if isinstance(res, list):
        parts = []
        for block in res:
            if isinstance(block, dict):
                btype = block.get("type")
                if btype == "text":
                    parts.append(block.get("text", ""))
                elif btype == "image":
                    parts.append("[image]")
                else:
                    parts.append(json.dumps(block))
            else:
                parts.append(str(block))
        return "\n".join(parts)
    return str(res)


def truncate_result(text):
    """Keep head and tail so the end of output (errors, exit status) stays visible."""
    lines = text.splitlines()
    if len(lines) <= MAX_RESULT_LINES:
        return text
    hidden = len(lines) - RESULT_HEAD_LINES - RESULT_TAIL_LINES
    kept = lines[:RESULT_HEAD_LINES] + [f"… ({hidden} lines hidden) …"] + lines[-RESULT_TAIL_LINES:]
    return "\n".join(kept)


def main():
    streamed_text = ""
    for line in sys.stdin:
        line_str = line.strip()
        if not line_str:
            continue
        try:
            data = json.loads(line_str)
            t = data.get("type")

            if t == "system":
                subtype = data.get("subtype")
                if subtype == "init":
                    print(f"🤖 Claude Code Initialized (Session: {data.get('session_id', 'unknown')})", flush=True)
                    print(f"⚙️  Model: {data.get('model', 'unknown')}", flush=True)
                    print(f"🛠️  Tools: {', '.join(data.get('tools', []))}\n", flush=True)
                streamed_text = ""

            elif t == "stream_event":
                event = data.get("event", {})
                delta = event.get("delta", {})
                text = delta.get("text", "")
                if not text and isinstance(event, dict):
                    text = event.get("text", "")
                if text:
                    print(text, end="", flush=True)
                    streamed_text += text

            elif t == "assistant":
                msg = data.get("message", {})
                content_list = msg.get("content", [])
                for content in content_list:
                    ctype = content.get("type")
                    if ctype == "thinking":
                        thinking = content.get("thinking", "")
                        if thinking:
                            print(f"\n💭 [Thinking]\n\033[2m{thinking}\033[0m\n", flush=True)
                    elif ctype == "text":
                        text = content.get("text", "")
                        if text and not streamed_text:
                            print(text, flush=True)
                    elif ctype == "tool_use":
                        name = content.get("name")
                        inp = content.get("input", {})
                        print(f"\n\n{format_tool_use(name, inp)}", flush=True)
                        streamed_text = ""

            elif t == "user":
                msg = data.get("message", {})
                content_list = msg.get("content", [])
                for content in content_list:
                    ctype = content.get("type")
                    if ctype == "tool_result":
                        text = result_to_text(content.get("content", ""))
                        if text:
                            print(f"📦 [Tool Result] Output:\n{truncate_result(text)}\n", flush=True)
                        streamed_text = ""

            elif t == "result":
                is_error = data.get("is_error", False)
                res = data.get("result", "")
                duration = data.get("duration_ms", 0) / 1000.0
                print(f"\n\n🏁 Session Finished in {duration:.2f}s", flush=True)
                if is_error:
                    if not streamed_text:
                        print(f"❌ Error: {res}", flush=True)
                    else:
                        print("\n❌ Session failed.", flush=True)
                else:
                    if not streamed_text:
                        print(f"✅ Success: {res}", flush=True)
                    else:
                        print("\n✅ Session completed.", flush=True)

        except Exception:
            print(line_str, flush=True)

if __name__ == "__main__":
    main()
