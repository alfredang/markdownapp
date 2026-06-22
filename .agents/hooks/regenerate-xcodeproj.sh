#!/usr/bin/env bash
# PostToolUse hook: when project.yml is edited, regenerate the Xcode project so the
# workspace never drifts from the XcodeGen spec. No-ops for any other file.
#
# Wire it up in .claude/settings.json:
#   "hooks": { "PostToolUse": [ { "matcher": "Edit|Write|MultiEdit",
#     "hooks": [ { "type": "command",
#       "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/regenerate-xcodeproj.sh" } ] } ] }

input=$(cat)
file=$(printf '%s' "$input" | /usr/bin/python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' 2>/dev/null)

case "$file" in
  */project.yml|project.yml)
    cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
    if command -v xcodegen >/dev/null 2>&1; then
      if xcodegen generate >/dev/null 2>&1; then
        printf '{"systemMessage":"Regenerated MarkdownVault.xcodeproj from project.yml"}\n'
      fi
    fi
    ;;
esac
exit 0
