#!/bin/sh
set -eu
file="${SRCROOT:?}/DeboogeyClient/DebugVariables.swift"
if grep -Eq '^[[:space:]]*static var omitMacLiveActivities[[:space:]]*=[[:space:]]*true[[:space:]]*(//.*)?$' "$file"; then
	exit 0
fi
exit 1
