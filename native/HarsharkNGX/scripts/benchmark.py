"""Generate synthetic captures outside the repo and measure a fresh process per workload."""
import json
from pathlib import Path
import platform
import subprocess
import sys
import tempfile

binary = Path(sys.argv[1]).resolve()
results = []
with tempfile.TemporaryDirectory(prefix="harshark-benchmark-") as directory:
    for name, count, body_size in [("small", 1000, 1024), ("medium", 10000, 4096),
                                    ("many_entries", 50000, 1024), ("large_preview", 1, 4 * 1048576), ("large_body", 1, 33 * 1048576)]:
        path = Path(directory) / (name + ".har")
        with path.open("w") as output:
            output.write('{"log":{"entries":[')
            for index in range(count):
                if index:
                    output.write(",")
                json.dump({"startedDateTime": "2026-10-26T12:00:00.123Z", "time": index % 1000,
                           "request": {"method": "GET", "url": f"https://example.test/path/{index}"},
                           "response": {"status": 200, "content": {"mimeType": "text/plain", "text": "a" * body_size}}}, output)
            output.write("]}}")
        runs = []
        for _ in range(3):
            run = subprocess.run([str(binary), str(path)], capture_output=True, text=True, check=True, timeout=120)
            runs.append(json.loads(run.stdout))
        results.append({"workload": name, "file_bytes": path.stat().st_size, "runs": runs})
print(json.dumps({"platform": platform.platform(), "results": results}, indent=2))
