from __future__ import annotations

import argparse
import json
import socket
import socketserver
import sys
import threading
from pathlib import Path
from typing import Any

from . import __version__
from .app import HarEntry, parse_har

PROTOCOL_VERSION = "2025-03-26"
SERVER_NAME = "harsharkngx"
MAX_BODY_PREVIEW_CHARS = 20_000
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765


class HarMcpServer:
    def __init__(self, initial_path: Path | None = None) -> None:
        self.current_path: Path | None = None
        self.entries: list[HarEntry] = []
        if initial_path is not None:
            self.load_har(initial_path)

    def run(self) -> None:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                message = json.loads(line)
                response = self._handle_message(message)
            except Exception as exc:
                response = self._error(None, -32700, f"{type(exc).__name__}: {exc}")

            if response is not None:
                self._write(response)

    def load_har(self, path: Path) -> dict[str, Any]:
        resolved = path.expanduser().resolve()
        payload = json.loads(resolved.read_text(encoding="utf-8"))
        entries = parse_har(payload)
        self.set_loaded_har(resolved, entries)
        return self._loaded_result()

    def set_loaded_har(self, path: Path, entries: list[HarEntry]) -> None:
        self.current_path = path
        self.entries = entries

    def clear_loaded_har(self) -> None:
        self.current_path = None
        self.entries = []

    def _loaded_result(self) -> dict[str, Any]:
        return {
            "path": str(self.current_path) if self.current_path else None,
            "entry_count": len(self.entries),
            "hosts": sorted({entry.host for entry in self.entries if entry.host}),
        }

    def _handle_message(self, message: dict[str, Any]) -> dict[str, Any] | None:
        message_id = message.get("id")
        method = message.get("method")
        params = message.get("params") or {}

        if message_id is None:
            return None

        try:
            if method == "initialize":
                return self._result(message_id, self._initialize_result())
            if method == "ping":
                return self._result(message_id, {})
            if method == "tools/list":
                return self._result(message_id, {"tools": self._tools()})
            if method == "tools/call":
                return self._result(message_id, self._call_tool(params))
            if method == "resources/list":
                return self._result(message_id, {"resources": self._resources()})
            if method == "resources/read":
                return self._result(message_id, self._read_resource(params))
            return self._error(message_id, -32601, f"Unknown method: {method}")
        except FileNotFoundError as exc:
            return self._failure(message_id, method, f"File not found: {exc.filename}")
        except json.JSONDecodeError as exc:
            return self._failure(message_id, method, f"Invalid JSON: {exc}")
        except Exception as exc:
            return self._failure(message_id, method, f"{type(exc).__name__}: {exc}")

    def _initialize_result(self) -> dict[str, Any]:
        return {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {
                "tools": {"listChanged": False},
                "resources": {"subscribe": False, "listChanged": False},
            },
            "serverInfo": {
                "name": SERVER_NAME,
                "version": __version__,
            },
        }

    def _tools(self) -> list[dict[str, Any]]:
        return [
            {
                "name": "load_har",
                "description": "Load a local HAR or HAR-shaped JSON file for inspection.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "path": {
                            "type": "string",
                            "description": "Absolute or user-relative path to a .har or .json file.",
                        },
                    },
                    "required": ["path"],
                },
            },
            {
                "name": "summarize_har",
                "description": "Summarize the currently loaded HAR file.",
                "inputSchema": {"type": "object", "properties": {}},
            },
            {
                "name": "list_entries",
                "description": "List request entries from the currently loaded HAR file.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "offset": {"type": "integer", "minimum": 0, "default": 0},
                        "limit": {"type": "integer", "minimum": 1, "maximum": 200, "default": 50},
                        "query": {
                            "type": "string",
                            "description": "Optional case-insensitive search across entry fields.",
                        },
                    },
                },
            },
            {
                "name": "get_entry",
                "description": "Fetch full details for a single HAR entry by zero-based index.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "index": {"type": "integer", "minimum": 0},
                        "include_raw": {
                            "type": "boolean",
                            "default": False,
                            "description": "Include the raw HAR entry JSON.",
                        },
                    },
                    "required": ["index"],
                },
            },
            {
                "name": "search_entries",
                "description": "Search entries and return concise matches.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "query": {"type": "string"},
                        "limit": {"type": "integer", "minimum": 1, "maximum": 200, "default": 50},
                    },
                    "required": ["query"],
                },
            },
        ]

    def _call_tool(self, params: dict[str, Any]) -> dict[str, Any]:
        name = params.get("name")
        arguments = params.get("arguments") or {}

        if name == "load_har":
            result = self.load_har(Path(str(arguments["path"])))
        elif name == "summarize_har":
            result = self._summary()
        elif name == "list_entries":
            result = self._list_entries(arguments)
        elif name == "get_entry":
            result = self._get_entry(arguments)
        elif name == "search_entries":
            result = self._search_entries(arguments)
        else:
            raise ValueError(f"Unknown tool: {name}")

        return self._tool_result(result)

    def _resources(self) -> list[dict[str, Any]]:
        return [
            {
                "uri": "harsharkngx://summary",
                "name": "Loaded HAR summary",
                "description": "Summary metadata for the currently loaded HAR file.",
                "mimeType": "application/json",
            },
            {
                "uri": "harsharkngx://entries",
                "name": "Loaded HAR entries",
                "description": "Concise request list for the currently loaded HAR file.",
                "mimeType": "application/json",
            },
        ]

    def _read_resource(self, params: dict[str, Any]) -> dict[str, Any]:
        uri = params.get("uri")
        if uri == "harsharkngx://summary":
            payload = self._summary()
        elif uri == "harsharkngx://entries":
            payload = self._list_entries({"limit": 200})
        else:
            raise ValueError(f"Unknown resource: {uri}")

        return {
            "contents": [
                {
                    "uri": str(uri),
                    "mimeType": "application/json",
                    "text": json.dumps(payload, indent=2, ensure_ascii=False),
                }
            ]
        }

    def _summary(self) -> dict[str, Any]:
        self._require_loaded()
        status_counts: dict[str, int] = {}
        method_counts: dict[str, int] = {}
        host_counts: dict[str, int] = {}
        slowest = sorted(self.entries, key=lambda entry: entry.total_time_value, reverse=True)[:10]

        for entry in self.entries:
            status_counts[entry.status or "unknown"] = status_counts.get(entry.status or "unknown", 0) + 1
            method_counts[entry.method or "unknown"] = method_counts.get(entry.method or "unknown", 0) + 1
            host_counts[entry.host or "unknown"] = host_counts.get(entry.host or "unknown", 0) + 1

        return {
            "path": str(self.current_path) if self.current_path else None,
            "entry_count": len(self.entries),
            "status_counts": dict(sorted(status_counts.items())),
            "method_counts": dict(sorted(method_counts.items())),
            "top_hosts": sorted(host_counts.items(), key=lambda item: item[1], reverse=True)[:20],
            "slowest_entries": [self._entry_summary(entry, index) for index, entry in self._indexed_entries(slowest)],
        }

    def _list_entries(self, arguments: dict[str, Any]) -> dict[str, Any]:
        self._require_loaded()
        offset = max(0, int(arguments.get("offset", 0)))
        limit = min(200, max(1, int(arguments.get("limit", 50))))
        query = str(arguments.get("query", "")).strip().casefold()
        indexed_entries = list(enumerate(self.entries))
        if query:
            indexed_entries = [
                (index, entry) for index, entry in indexed_entries if query in entry.haystack().casefold()
            ]
        page = indexed_entries[offset : offset + limit]
        return {
            "path": str(self.current_path) if self.current_path else None,
            "total_matches": len(indexed_entries),
            "offset": offset,
            "limit": limit,
            "entries": [self._entry_summary(entry, index) for index, entry in page],
        }

    def _get_entry(self, arguments: dict[str, Any]) -> dict[str, Any]:
        self._require_loaded()
        index = int(arguments["index"])
        if index < 0 or index >= len(self.entries):
            raise IndexError(f"Entry index out of range: {index}")
        entry = self.entries[index]
        payload = {
            **self._entry_summary(entry, index),
            "request": {
                "headers": entry.request_headers,
                "parameters": entry.request_query,
                "cookies": entry.request_cookies,
                "body": self._preview(entry.request_body),
                "saml": self._preview(entry.request_saml),
            },
            "response": {
                "headers": entry.response_headers,
                "parameters": entry.response_params,
                "cookies": entry.response_cookies,
                "body": self._preview(entry.response_body),
            },
        }
        if bool(arguments.get("include_raw", False)):
            payload["raw"] = entry.raw
        return payload

    def _search_entries(self, arguments: dict[str, Any]) -> dict[str, Any]:
        query = str(arguments["query"])
        return self._list_entries({"query": query, "limit": arguments.get("limit", 50)})

    def _entry_summary(self, entry: HarEntry, index: int) -> dict[str, Any]:
        return {
            "index": index,
            "started": entry.started,
            "method": entry.method,
            "status": entry.status,
            "protocol": entry.protocol,
            "host": entry.host,
            "path": entry.path,
            "full_url": entry.full_url,
            "mime_type": entry.mime_type,
            "time_ms": entry.total_time_value,
        }

    def _indexed_entries(self, entries: list[HarEntry]) -> list[tuple[int, HarEntry]]:
        by_id = {id(entry): index for index, entry in enumerate(self.entries)}
        return [(by_id[id(entry)], entry) for entry in entries]

    def _preview(self, value: str) -> dict[str, Any]:
        truncated = len(value) > MAX_BODY_PREVIEW_CHARS
        return {
            "text": value[:MAX_BODY_PREVIEW_CHARS],
            "truncated": truncated,
            "chars": len(value),
        }

    def _require_loaded(self) -> None:
        if self.current_path is None:
            raise ValueError("No HAR file is loaded. Call load_har first or pass a path when starting the server.")

    def _tool_result(self, payload: dict[str, Any]) -> dict[str, Any]:
        return {
            "content": [
                {
                    "type": "text",
                    "text": json.dumps(payload, indent=2, ensure_ascii=False),
                }
            ]
        }

    def _tool_error(self, message_id: Any, message: str) -> dict[str, Any]:
        return self._result(
            message_id,
            {
                "isError": True,
                "content": [{"type": "text", "text": message}],
            },
        )

    def _failure(self, message_id: Any, method: Any, message: str) -> dict[str, Any]:
        if method == "tools/call":
            return self._tool_error(message_id, message)
        return self._error(message_id, -32000, message)

    def _result(self, message_id: Any, result: dict[str, Any]) -> dict[str, Any]:
        return {"jsonrpc": "2.0", "id": message_id, "result": result}

    def _error(self, message_id: Any, code: int, message: str) -> dict[str, Any]:
        return {"jsonrpc": "2.0", "id": message_id, "error": {"code": code, "message": message}}

    def _write(self, message: dict[str, Any]) -> None:
        sys.stdout.write(json.dumps(message, ensure_ascii=False) + "\n")
        sys.stdout.flush()


class McpTcpService:
    def __init__(
        self,
        server: HarMcpServer,
        host: str = DEFAULT_HOST,
        port: int = DEFAULT_PORT,
    ) -> None:
        self.server = server
        self.host = host
        self.port = port
        self._tcp_server: socketserver.ThreadingTCPServer | None = None
        self._thread: threading.Thread | None = None

    def start(self) -> int:
        owner = self

        class Handler(socketserver.StreamRequestHandler):
            def handle(self) -> None:
                for raw_line in self.rfile:
                    line = raw_line.decode("utf-8").strip()
                    if not line:
                        continue
                    try:
                        message = json.loads(line)
                        response = owner.server._handle_message(message)
                    except Exception as exc:
                        response = owner.server._error(None, -32700, f"{type(exc).__name__}: {exc}")
                    if response is not None:
                        self.wfile.write((json.dumps(response, ensure_ascii=False) + "\n").encode("utf-8"))
                        self.wfile.flush()

        class ThreadingServer(socketserver.ThreadingTCPServer):
            allow_reuse_address = True
            daemon_threads = True

        self._tcp_server = ThreadingServer((self.host, self.port), Handler)
        self.port = int(self._tcp_server.server_address[1])
        self._thread = threading.Thread(target=self._tcp_server.serve_forever, name="HarsharkNGX MCP", daemon=True)
        self._thread.start()
        return self.port

    def stop(self) -> None:
        if self._tcp_server is not None:
            self._tcp_server.shutdown()
            self._tcp_server.server_close()
            self._tcp_server = None
        if self._thread is not None:
            self._thread.join(timeout=1)
            self._thread = None


def bridge_stdio(host: str = DEFAULT_HOST, port: int = DEFAULT_PORT) -> None:
    try:
        with socket.create_connection((host, port), timeout=5) as sock:
            reader = sock.makefile("r", encoding="utf-8")
            writer = sock.makefile("w", encoding="utf-8")
            for line in sys.stdin:
                if not line.strip():
                    continue
                message = json.loads(line)
                writer.write(json.dumps(message, ensure_ascii=False) + "\n")
                writer.flush()
                if message.get("id") is None:
                    continue
                response = reader.readline()
                if not response:
                    raise ConnectionError("HarsharkNGX MCP service closed the connection.")
                sys.stdout.write(response)
                sys.stdout.flush()
    except Exception as exc:
        fallback = {
            "jsonrpc": "2.0",
            "id": None,
            "error": {
                "code": -32000,
                "message": f"Unable to connect to HarsharkNGX. Open HarsharkNGX first. {type(exc).__name__}: {exc}",
            },
        }
        sys.stdout.write(json.dumps(fallback, ensure_ascii=False) + "\n")
        sys.stdout.flush()


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the HarsharkNGX MCP server.")
    parser.add_argument(
        "--bridge",
        action="store_true",
        help="Bridge stdio MCP traffic to the MCP service running inside the HarsharkNGX app.",
    )
    parser.add_argument(
        "--tcp",
        action="store_true",
        help="Run a standalone TCP MCP service for development.",
    )
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("path", nargs="?", help="Optional HAR file to load at startup.")
    args = parser.parse_args()

    if args.bridge:
        bridge_stdio(args.host, args.port)
        return

    initial_path = Path(args.path) if args.path else None
    server = HarMcpServer(initial_path)
    if args.tcp:
        service = McpTcpService(server, args.host, args.port)
        port = service.start()
        sys.stderr.write(f"HarsharkNGX MCP TCP service listening on {args.host}:{port}\n")
        sys.stderr.flush()
        try:
            threading.Event().wait()
        except KeyboardInterrupt:
            service.stop()
        return

    server.run()


if __name__ == "__main__":
    main()
