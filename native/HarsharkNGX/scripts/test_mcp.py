"""Exercise the standalone server over real stdio, without launching the GUI."""
import json
from pathlib import Path
import subprocess
import select
import sys
import tempfile
import uuid

root = Path(__file__).resolve().parent.parent
binary = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="harshark-mcp-test-") as directory:
    session_id = str(uuid.uuid4()).upper()
    snapshot = Path(directory) / (session_id + ".har")
    snapshot.write_bytes((root / "HarsharkNGX/Sample.har").read_bytes())
    requests = []

    def request(method, params=None):
        identifier = len(requests) + 1
        requests.append({"jsonrpc": "2.0", "id": identifier, "method": method, "params": params or {}})
        return identifier

    def tool(name, arguments=None):
        return request("tools/call", {"name": name, "arguments": arguments or {}})

    initialize = request("initialize", {"protocolVersion": "2025-11-25", "capabilities": {}, "clientInfo": {"name": "regression", "version": "1"}})
    discovery = request("tools/list")
    unloaded = tool("summarize_har")
    sessions = tool("list_sessions")
    opened = tool("open_session", {"id": session_id})
    entry = tool("get_entry", {"index": 0})
    search = tool("search_entries", {"query": "403"})
    page = tool("get_body", {"index": 0, "offset": 0, "limit": 10})
    missing = tool("get_entry", {"index": 999})
    failed_load = tool("load_har", {"path": str(Path(directory) / "absent.har")})
    retained = tool("summarize_har")
    resource = request("resources/read", {"uri": "harsharkngx://entries"})
    process = subprocess.Popen([str(binary), "--session-directory", directory],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    replies = {}
    try:
        for message in requests:
            process.stdin.write((json.dumps(message) + "\n").encode())
            process.stdin.flush()
            assert select.select([process.stdout], [], [], 5)[0], "Server did not respond while stdin remained open"
            reply = json.loads(process.stdout.readline())
            replies[reply["id"]] = reply
        process.stdin.close()
        assert process.wait(timeout=5) == 0
        assert not process.stderr.read(), "Unexpected diagnostic output"
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
    assert len(replies) == len(requests)

    def payload(identifier):
        return json.loads(replies[identifier]["result"]["content"][0]["text"])

    assert replies[initialize]["result"]["serverInfo"]["version"] == "1.0.0"
    assert len(replies[discovery]["result"]["tools"]) == 8
    assert replies[unloaded]["result"]["isError"]
    assert payload(sessions)["sessions"][0]["id"] == session_id
    assert payload(opened)["entry_count"] == 6
    assert "sample-1" in payload(entry)["response"]["body"]["text"]
    assert payload(entry)["request"]["body"]["notice"]
    assert payload(search)["total_matches"] == 1
    assert len(payload(page)["text"]) == 10 and payload(page)["truncated"]
    assert replies[missing]["result"]["isError"]
    assert replies[failed_load]["result"]["isError"]
    assert payload(retained)["entry_count"] == 6
    assert json.loads(replies[resource]["result"]["contents"][0]["text"])["total_matches"] == 6
    print("MCP regression passed: interactive startup, tools, shared sessions, bodies, paging, search, resources, error recovery, EOF shutdown.")
