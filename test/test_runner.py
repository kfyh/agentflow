import subprocess
import unittest
import os

class TestRunner(unittest.TestCase):
    def setUp(self):
        # Create a clean environment copy and clear any vendor API keys
        # to ensure deterministic authentication failure tests.
        self.test_env = os.environ.copy()
        for key in ["GEMINI_API_KEY", "MISTRAL_API_KEY", "ANTHROPIC_API_KEY"]:
            self.test_env.pop(key, None)
        self.test_env["AGENT_TESTING"] = "true"

    def test_bash_syntax(self):
        """Verifies that the central Bash runner has valid syntax."""
        result = subprocess.run(
            ["bash", "-n", "run-agent.sh"],
            capture_output=True,
            text=True
        )
        self.assertEqual(result.returncode, 0, f"Syntax errors found:\n{result.stderr}")

    def test_invalid_engine_handling(self):
        """Verifies that specifying a non-existent engine driver fails gracefully."""
        result = subprocess.run(
            ["./run-agent.sh", "-c", "nonexistent"],
            capture_output=True,
            text=True,
            env=self.test_env
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("is not a valid driver config", result.stdout)
        self.assertIn("Available engines: gemini, mistral, claude", result.stdout)

    def test_run_without_credentials(self):
        """Verifies runner behavior when executing without API credentials.
        Should either fail due to missing Docker daemon, or fail inside Docker run
        and output the appropriate troubleshooting instructions.
        """
        # We pass a directory (.) and a dummy prompt ("test")
        result = subprocess.run(
            ["./run-agent.sh", "-c", "gemini", ".", "test"],
            capture_output=True,
            text=True,
            env=self.test_env
        )
        self.assertNotEqual(result.returncode, 0)
        
        # Determine if it failed because Docker was down or because Docker run failed
        if "Docker daemon is not running" in result.stdout or "Docker daemon is not running" in result.stderr:
            # Docker is down: this is a valid environment failure
            self.assertIn("Docker daemon is not running", result.stdout or result.stderr)
        else:
            # Docker is up: should run the container, fail due to no credentials, and print advice
            self.assertIn("Container exited with error code", result.stdout)
            self.assertIn("Troubleshooting: Since you are using Google One OAuth", result.stdout)

    def test_prompt_file_resolution(self):
        """Verifies that the runner correctly resolves prompt.txt and prompt.md priority."""
        txt_path = "prompt.txt"
        md_path = "prompt.md"

        # Helper to run script and return stdout
        def run_runner():
            return subprocess.run(
                ["./run-agent.sh", "-c", "gemini", "."],
                capture_output=True,
                text=True,
                env=self.test_env
            ).stdout

        # Case 1: Only prompt.txt exists
        try:
            with open(txt_path, "w") as f:
                f.write("test prompt txt")
            output = run_runner()
            self.assertIn("Found prompt.txt in", output)
        finally:
            if os.path.exists(txt_path):
                os.remove(txt_path)

        # Case 2: Only prompt.md exists
        try:
            with open(md_path, "w") as f:
                f.write("test prompt md")
            output = run_runner()
            self.assertIn("Found prompt.md in", output)
        finally:
            if os.path.exists(md_path):
                os.remove(md_path)

        # Case 3: Both exist (prompt.txt should take precedence)
        try:
            with open(txt_path, "w") as f:
                f.write("test prompt txt")
            with open(md_path, "w") as f:
                f.write("test prompt md")
            output = run_runner()
            self.assertIn("Found prompt.txt in", output)
        finally:
            if os.path.exists(txt_path):
                os.remove(txt_path)
            if os.path.exists(md_path):
                os.remove(md_path)

    def test_verbose_flag_parsing(self):
        """Verifies that the verbose flag is correctly identified and passed down for claude engine."""
        result = subprocess.run(
            ["./run-agent.sh", "-c", "claude", "-p", "test prompt", "--verbose"],
            capture_output=True,
            text=True,
            env=self.test_env
        )
        self.assertIn("(streaming real-time output)", result.stdout)

    def test_tui_prompt_mode(self):
        """Verifies that running with --tui and a prompt prints Executing: claude [prompt...] and not Executing: claude -p."""
        result = subprocess.run(
            ["./run-agent.sh", "-c", "claude", "-p", "test prompt", "--tui"],
            capture_output=True,
            text=True,
            env=self.test_env
        )
        self.assertIn("Executing: claude [prompt + guidelines]", result.stdout)
        self.assertNotIn("claude -p", result.stdout)

if __name__ == '__main__':
    unittest.main()

