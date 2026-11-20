#!/bin/sh
set -eu
rsp="${DERIVED_FILE_DIR:?}/deboogey-mac-la.rsp"
mkdir -p "${DERIVED_FILE_DIR}"
: > "${rsp}"
[ "${PLATFORM_NAME:-}" = "macosx" ] || exit 0
case "${SDK_VERSION:-}" in
	27.3*) ;;
	*) exit 0 ;;
esac
if "${SRCROOT:?}/Scripts/mac-la-omit.sh"; then
	exit 0
fi
printf -- '-D\nDEBOOGEY_MAC_LIVE_ACTIVITIES\n' > "${rsp}"
