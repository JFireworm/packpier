"""Check Swift correctness rules while leaving formatting to the source authors."""
from pathlib import Path
import re
import subprocess

paths = [str(p) for folder in ("Sources", "Loader", "Plugins/WeChatCeladon", "Tests")
         for p in Path(folder).rglob("*.swift") if ".build" not in p.parts]
rules = {"NoAssignmentInExpressions", "NeverUseForceTry", "NoCasesWithOnlyFallthrough", "NoPlaygroundLiterals"}
run = subprocess.run(["xcrun", "swift-format", "lint", "--no-color-diagnostics",
                      "--configuration", '{"rules":{"NeverUseForceTry":true}}', *paths],
                     capture_output=True, text=True, check=True)
for line in run.stderr.splitlines() + run.stdout.splitlines():
    rule = re.search(r"warning: \[([^\]]+)\]", line)
    if "error:" in line or (rule and rule[1] in rules):
        raise SystemExit(line)
print(f"PASS Swift lint ({len(paths)} files)")
