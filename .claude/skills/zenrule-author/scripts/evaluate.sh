#!/usr/bin/env bash
# evaluate.sh — POST a context to the ZenRule agent and print result + trace
#
# Usage:
#   evaluate.sh <rule-name> '<context-json>'
#   evaluate.sh <rule-name> path/to/context.json
#   echo '<context-json>' | evaluate.sh <rule-name> -
#
# <rule-name> is the filename under priv/zenrule/atomic-fi/ — with or
# without the .json extension; the script adds it if missing.
#
# Exit codes:
#   0   agent returned 200, output piped to stdout
#   1   bad arguments
#   2   agent unreachable (curl error)
#   3   agent returned a non-200 (likely "Loader error" — file not in
#       agent's entrypoints; verify the .json exists in priv/zenrule/
#       and you've waited 5s for the poll)

set -euo pipefail

AGENT_URL="${ZENRULE_AGENT_URL:-http://localhost:8090}"
PROJECT="${ZENRULE_PROJECT:-atomic-fi}"

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <rule-name> '<context-json>' | path/to/context.json | -" >&2
  exit 1
fi

rule="$1"
src="$2"

# Normalise rule name → always ends in .json
[[ "$rule" == *.json ]] || rule="${rule}.json"

# Load context from arg, file, or stdin
if [[ "$src" == "-" ]]; then
  context="$(cat)"
elif [[ -f "$src" ]]; then
  context="$(cat "$src")"
else
  context="$src"
fi

# Validate it's parseable JSON before sending
if ! printf '%s' "$context" | jq -e . >/dev/null 2>&1; then
  echo "error: context is not valid JSON" >&2
  exit 1
fi

# Build the request body — always trace:true so the trace panel is populated
body="$(jq -n --argjson ctx "$context" '{context: $ctx, trace: true}')"

# POST
response="$(curl -sS -w '\n%{http_code}' \
  -X POST "${AGENT_URL}/api/projects/${PROJECT}/evaluate/${rule}" \
  -H 'content-type: application/json' \
  -d "$body" 2>&1)" || {
  echo "error: cannot reach ZenRule agent at ${AGENT_URL}" >&2
  echo "$response" >&2
  exit 2
}

http_code="$(printf '%s' "$response" | tail -n1)"
payload="$(printf '%s' "$response" | sed '$d')"

if [[ "$http_code" != "200" ]]; then
  echo "error: agent returned HTTP ${http_code}" >&2
  printf '%s\n' "$payload" >&2
  echo "" >&2
  echo "hint: if you see 'Loader error', the file ${rule} isn't in the agent's entrypoints." >&2
  echo "  curl -s ${AGENT_URL}/api/projects/${PROJECT}/entrypoints | jq" >&2
  echo "  ls priv/zenrule/${PROJECT}/" >&2
  echo "  (the agent re-scans every ~5s; wait if you just saved)" >&2
  exit 3
fi

printf '%s\n' "$payload" | jq .
