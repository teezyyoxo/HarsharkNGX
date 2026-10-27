#!/bin/zsh
set -euo pipefail
project_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$project_root"
swift build -c release --product harsharkngx-mcp
build_path="$(swift build -c release --show-bin-path)"
install_directory="$HOME/Library/Application Support/HarsharkNGX/bin"
mkdir -p "$install_directory"
install -m 755 "$build_path/harsharkngx-mcp" "$install_directory/harsharkngx-mcp.new"
mv -f "$install_directory/harsharkngx-mcp.new" "$install_directory/harsharkngx-mcp"
printf 'Installed MCP executable: %s\n' "$install_directory/harsharkngx-mcp"
printf 'Use this absolute path as the command in Claude Desktop; no arguments or GUI are required.\n'
