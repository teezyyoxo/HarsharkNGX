#!/bin/zsh
set -euo pipefail
project_root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$project_root"
install_directory="$HOME/Library/Application Support/HarsharkNGX/bin"
mkdir -p "$install_directory"
staging="$(mktemp -d "$install_directory/.mcp-install.XXXXXX")"
trap 'rm -rf -- "$staging"' EXIT
"$project_root/scripts/build-mcp-bundle.sh" "$staging/HarsharkMCP.app"
if [[ -e "$install_directory/HarsharkMCP.previous.app" ]]; then
    rm -rf -- "$install_directory/HarsharkMCP.previous.app"
fi
if [[ -e "$install_directory/HarsharkMCP.app" ]]; then
    mv "$install_directory/HarsharkMCP.app" "$install_directory/HarsharkMCP.previous.app"
fi
mv "$staging/HarsharkMCP.app" "$install_directory/HarsharkMCP.app"
ln -s "HarsharkMCP.app/Contents/MacOS/harsharkngx-mcp" "$staging/harsharkngx-mcp"
mv -f "$staging/harsharkngx-mcp" "$install_directory/harsharkngx-mcp"
printf 'Installed MCP executable: %s\n' "$install_directory/harsharkngx-mcp"
printf 'Use this absolute path as the command in Claude Desktop; no arguments or GUI are required.\n'
printf 'Add %s/HarsharkMCP.app in Full Disk Access, verify in the Setup Assistant, then restart Claude.\n' "$install_directory"
