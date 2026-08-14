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
        # Engines are discovered from the vendor folders holding an agent.conf
        for engine in ["claude", "gemini", "mistral"]:
            self.assertIn(engine, result.stdout.split("Available engines:")[1])

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

    def test_gemini_verbose_flag_parsing(self):
        """Verifies that the verbose flag and streaming format are correctly loaded for gemini engine."""
        result = subprocess.run(
            ["./run-agent.sh", "-c", "gemini", "-p", "test prompt", "--verbose"],
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

    def _run(self, *args):
        """Runs the bash runner with testing env and returns stdout."""
        return subprocess.run(
            ["./run-agent.sh", *args],
            capture_output=True,
            text=True,
            env=self.test_env
        ).stdout

    def _container_flags(self, stdout):
        """Extracts the stdin/TTY flags the runner assembled for the container."""
        for line in stdout.splitlines():
            if "Container flags:" in line:
                return line.split("Container flags:")[1].strip()
        self.fail(f"Runner did not report container flags:\n{stdout}")

    def test_interactive_mode_requests_a_tty(self):
        """No prompt means the bare interactive TUI, which cannot run without a PTY.

        The CLIs switch themselves to non-interactive print mode when stdin is
        not a terminal, so a missing -t here breaks the sandbox-then-work-by-hand
        flow rather than merely degrading it.
        """
        output = self._run("-c", "claude", ".")
        self.assertIn("Launching interactive CLI TUI", output)
        self.assertEqual("-i -t", self._container_flags(output))

    def test_tui_prompt_mode_requests_a_tty(self):
        """A prompt delivered to the TUI still lands in an interactive session."""
        output = self._run("-c", "claude", "-p", "test prompt", "--tui")
        self.assertEqual("-i -t", self._container_flags(output))

    def test_streamed_mode_does_not_request_a_tty(self):
        """The streamed path pipes stdout and reads stdin from /dev/null.

        Docker refuses to allocate a TTY for a container whose stdin is not a
        terminal, so requesting one here would fail the run outright.
        """
        output = self._run("-c", "claude", "-p", "test prompt")
        self.assertIn("streaming real-time output", output)
        self.assertEqual("-i", self._container_flags(output))

    def test_headless_mode_does_not_request_a_tty(self):
        """Mistral declares no stream formatter, so a prompt uses headless mode."""
        output = self._run("-c", "mistral", "-p", "test prompt")
        self.assertEqual("-i", self._container_flags(output))

    def test_tui_flag_without_a_prompt_stays_interactive(self):
        """-t selects how a prompt is delivered; alone it is a no-op.

        Documents the behaviour rather than endorsing it: without a prompt there
        is nothing to route, so the run is identical to omitting the flag.
        """
        with_flag = self._run("-c", "claude", ".", "-t")
        without_flag = self._run("-c", "claude", ".")
        self.assertIn("Launching interactive CLI TUI", with_flag)
        self.assertEqual(
            self._container_flags(without_flag), self._container_flags(with_flag)
        )

    def test_no_volume_shadows_the_cli_install_path(self):
        """Deleting an image must be a complete reset of container code.

        The vendor CLIs install under ~/.local/bin, so a volume mounted at
        /home/node itself would shadow the binary and pin it in state that
        survives `docker rmi` — a rebuilt image would silently keep running the
        old CLI. Volumes carry credentials and config; the image carries code.
        Mount subdirectories of the home directory, never the home directory.
        """
        import glob
        for driver in sorted(glob.glob("*/agent.conf") + glob.glob("*/agent.psd1")):
            engine = os.path.basename(os.path.dirname(driver))
            with open(driver) as f:
                body = f.read()
            with self.subTest(driver=f"{engine}/{os.path.basename(driver)}"):
                # A subdirectory mount reads ":/home/node/<something>"; only an
                # exact home-directory mount ends the quoted target there.
                msg = (
                    f"{driver} mounts a volume at /home/node itself, which "
                    f"shadows the CLI installed under ~/.local/bin. Mount a "
                    f"subdirectory such as /home/node/.{engine} instead."
                )
                self.assertNotIn(':/home/node"', body, msg)
                self.assertNotIn(":/home/node'", body, msg)

    def test_claude_persists_its_credentials_directory(self):
        """Credentials live in ~/.claude/.credentials.json and must outlive --rm.

        Without this the OAuth flow would have to be repeated on every prompted
        run, not just interactive ones.
        """
        output = self._run("-c", "claude", ".")
        self.assertIn("agentic-coder-claude:/home/node/.claude", output)

    def test_every_engine_declares_stdin_flags_for_each_mode(self):
        """A driver that omits its stdin contract silently loses the TTY.

        The runner falls back to -i alone, which is correct for headless work and
        wrong for anything interactive, so the omission surfaces as a broken TUI
        rather than a config error.
        """
        import glob
        for conf in sorted(glob.glob("*/agent.conf")):
            engine = os.path.basename(os.path.dirname(conf))
            with open(conf) as f:
                body = f.read()
            with self.subTest(engine=engine):
                for mode in ["STDIN_INTERACTIVE", "STDIN_TUI", "STDIN_HEADLESS"]:
                    self.assertIn(f"{mode}=", body)
                # Only a driver with a stream formatter ever uses STDIN_STREAM.
                if "STREAM_FORMATTER=" in body:
                    self.assertIn("STDIN_STREAM=", body)

    def test_mistral_env_file_loading(self):
        """Verifies that ~/.vibe/.env is loaded and exports MISTRAL_API_KEY."""
        import tempfile

        # Create a temp directory to simulate $HOME
        temp_home = tempfile.mkdtemp()
        try:
            vibe_dir = os.path.join(temp_home, ".vibe")
            os.makedirs(vibe_dir)
            env_file = os.path.join(vibe_dir, ".env")
            
            with open(env_file, "w") as f:
                f.write("# This is a comment\n")
                f.write("MISTRAL_API_KEY=mocked_key_from_env_file\n")
                
            # Symlink host's .docker and .colima directories so docker command can resolve sockets/contexts
            original_home = os.environ.get("HOME")
            if original_home:
                for folder in [".docker", ".colima"]:
                    src = os.path.join(original_home, folder)
                    if os.path.exists(src):
                        try:
                            os.symlink(src, os.path.join(temp_home, folder))
                        except Exception:
                            pass

            env = self.test_env.copy()
            env["HOME"] = temp_home
            env["USERPROFILE"] = temp_home

            result = subprocess.run(
                ["./run-agent.sh", "-c", "mistral", ".", "test"],
                capture_output=True,
                text=True,
                env=env
            )
            
            self.assertIn("Mode: API Key Authentication (MISTRAL_API_KEY detected)", result.stdout)
        finally:
            import shutil
            shutil.rmtree(temp_home, ignore_errors=True)

if __name__ == '__main__':
    unittest.main()

