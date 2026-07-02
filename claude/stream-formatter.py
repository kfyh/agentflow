#!/usr/bin/env python3
import sys
import json

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
                    if ctype == "text":
                        text = content.get("text", "")
                        if text and not streamed_text:
                            print(text, flush=True)
                    elif ctype == "tool_use":
                        name = content.get("name")
                        inp = content.get("input", {})
                        print(f"\n\n🛠️  [Tool Use: {name}] Input: {json.dumps(inp)}", flush=True)
                        streamed_text = ""
            
            elif t == "user":
                msg = data.get("message", {})
                content_list = msg.get("content", [])
                for content in content_list:
                    ctype = content.get("type")
                    if ctype == "tool_result":
                        res = content.get("content", "")
                        if isinstance(res, str):
                            res_lines = res.splitlines()
                            summary = "\n".join(res_lines[:5])
                            if len(res_lines) > 5:
                                summary += f"\n... ({len(res_lines) - 5} more lines)"
                            print(f"📦 [Tool Result] Output:\n{summary}\n", flush=True)
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
