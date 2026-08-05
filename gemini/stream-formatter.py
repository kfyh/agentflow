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
    if not isinstance(text, str):
        text = str(text)
    lines = text.splitlines()
    return f"({len(lines)} lines, {len(text)} chars)"


def format_tool_use(name, inp):
    """Return a concise, human-first description of a tool call."""
    header = f"🛠️  [Tool Use: {name}]"
    if not isinstance(inp, dict):
        return f"{header} {inp}"

    if name == "run_command":
        cmd = inp.get("CommandLine", "")
        cwd = inp.get("Cwd", "")
        line = f"{header} $ {cmd}"
        if cwd:
            line += f" (in {cwd})"
        return line

    if name in ("view_file", "replace_file_content", "multi_replace_file_content", "write_to_file"):
        path = inp.get("AbsolutePath") or inp.get("TargetFile") or ""
        desc = f"{header} {path}"
        if name == "write_to_file":
            content = inp.get("CodeContent", "")
            desc += f" {_content_summary(content)}"
        elif name == "view_file":
            start = inp.get("StartLine")
            end = inp.get("EndLine")
            if start is not None and end is not None:
                desc += f" (lines {start}-{end})"
        return desc

    if name == "grep_search":
        query = inp.get("Query", "")
        path = inp.get("SearchPath", "")
        return f"{header} '{query}' in {path}"

    if name == "list_dir":
        path = inp.get("DirectoryPath", "")
        return f"{header} {path}"

    if name == "search_web":
        query = inp.get("query", "")
        return f"{header} '{query}'"

    if name == "read_url_content":
        url = inp.get("Url", "")
        return f"{header} {url}"

    if name == "send_message":
        recipient = inp.get("Recipient", "")
        return f"{header} to {recipient}"

    if name == "invoke_subagent":
        subagents = inp.get("Subagents", [])
        roles = [s.get("Role", s.get("TypeName", "")) for s in subagents if isinstance(s, dict)]
        return f"{header} with roles: {', '.join(roles)}"

    if name == "define_subagent":
        sub_name = inp.get("name", "")
        return f"{header} name: {sub_name}"

    if name == "ask_question":
        questions = inp.get("questions", [])
        q_texts = [q.get("question", "") for q in questions if isinstance(q, dict)]
        return f"{header} questions: {'; '.join(q_texts)}"

    # Fallback: pretty-printed JSON with long string values truncated.
    return f"{header}\n{json.dumps(_truncate_values(inp), indent=2)}"


def result_to_text(res):
    """Normalize tool-result content to text."""
    if isinstance(res, str):
        return res
    if isinstance(res, (dict, list)):
        try:
            return json.dumps(res, indent=2)
        except Exception:
            return str(res)
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
    printed_tool_calls = set()
    printed_subagents = set()
    in_thinking = False

    while True:
        line = sys.stdin.readline()
        if not line:
            break
        line_str = line.strip()
        if not line_str:
            continue
        try:
            data = json.loads(line_str)
            event = data.get("event")

            if event == "init":
                if in_thinking:
                    print("\033[0m\n", end="", flush=True)
                    in_thinking = False
                init_data = data.get("init", {})
                conv_id = init_data.get("conversation_id", "unknown")
                print(f"🤖 Antigravity CLI Initialized (Session: {conv_id})", flush=True)
                model = init_data.get("model")
                if model:
                    print(f"⚙️  Model: {model}", flush=True)
                tools = init_data.get("tools")
                if tools:
                    print(f"🛠️  Tools: {', '.join(tools)}\n", flush=True)
                streamed_text = ""

            elif event == "step_update":
                u = data.get("step_update", {})
                step_index = u.get("step_index")
                step_type = u.get("step_type")
                state = u.get("state")
                text_delta = u.get("text_delta", "")
                thinking_delta = u.get("thinking_delta", u.get("thinking", u.get("thought", u.get("thought_delta", ""))))

                # Check if this delta is reasoning/thinking
                is_thinking_delta = (step_type in ("thought", "thinking", "reasoning")) or bool(thinking_delta)
                delta_to_print = thinking_delta if thinking_delta else text_delta

                if delta_to_print:
                    if is_thinking_delta:
                        if not in_thinking:
                            print("\n💭 [Thinking]\n\033[2m", end="", flush=True)
                            in_thinking = True
                        print(delta_to_print, end="", flush=True)
                    else:
                        if in_thinking:
                            print("\033[0m\n", end="", flush=True)
                            in_thinking = False
                        print(delta_to_print, end="", flush=True)
                    streamed_text += delta_to_print

                # Handle tool updates
                tool_info = u.get("tool_info", {})
                if tool_info:
                    name = tool_info.get("name")
                    if name:
                        if in_thinking:
                            print("\033[0m\n", end="", flush=True)
                            in_thinking = False
                        if step_index not in printed_tool_calls:
                            inp = tool_info.get("parameters", {})
                            print(f"\n\n{format_tool_use(name, inp)}", flush=True)
                            printed_tool_calls.add(step_index)
                        
                        if state == "DONE":
                            error = tool_info.get("error")
                            output = tool_info.get("output")
                            if error:
                                err_msg = ""
                                if isinstance(error, dict):
                                    err_msg = f"{error.get('type', 'Error')}: {error.get('message', '')}"
                                else:
                                    err_msg = str(error)
                                print(f"❌ [Tool Error]: {err_msg}\n", flush=True)
                            elif output is not None:
                                text = result_to_text(output)
                                if text:
                                    print(f"📦 [Tool Result] Output:\n{truncate_result(text)}\n", flush=True)
                            streamed_text = ""

                # Handle subagent updates
                subagent_info = u.get("subagent_info", {})
                if subagent_info:
                    sub_id = subagent_info.get("conversation_id")
                    if sub_id:
                        if in_thinking:
                            print("\033[0m\n", end="", flush=True)
                            in_thinking = False
                        if step_index not in printed_subagents:
                            role = subagent_info.get("role", "")
                            type_name = subagent_info.get("type_name", "")
                            print(f"\n👥 [Subagent: {role} ({type_name})] - Session: {sub_id}", flush=True)
                            printed_subagents.add(step_index)
                        
                        if state == "DONE":
                            print(f"👥 [Subagent Finished] Session: {sub_id}\n", flush=True)
                            streamed_text = ""

            elif event == "result":
                if in_thinking:
                    print("\033[0m\n", end="", flush=True)
                    in_thinking = False
                res_data = data.get("result", {})
                duration = res_data.get("duration", res_data.get("duration_seconds", 0.0))
                print(f"\n\n🏁 Session Finished in {duration:.2f}s", flush=True)
                
                usage = res_data.get("usage", {})
                if usage:
                    parts = []
                    for k, v in usage.items():
                        parts.append(f"{k.replace('_', ' ').title()}: {v}")
                    if parts:
                        print(f"📊 Usage: {', '.join(parts)}", flush=True)
                
                output = res_data.get("output", res_data.get("result", ""))
                status = res_data.get("status")
                is_error = res_data.get("is_error", False)
                
                if not streamed_text and output:
                    print(output, flush=True)
                
                if is_error or status == "ERROR":
                    print("❌ Session failed.", flush=True)
                else:
                    print("✅ Session completed.", flush=True)

        except Exception as e:
            if in_thinking:
                print("\033[0m\n", end="", flush=True)
                in_thinking = False
            # Fallback to printing the raw line on parsing error to ensure no info is lost
            print(line_str, flush=True)


if __name__ == "__main__":
    main()
