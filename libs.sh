#!/bin/bash
set -e

VERSION="2.9.2"
URL="https://github.com/markneh/react-native-pjsip-builder/releases/download/${VERSION}/$.tar.gz"
LOCK=".libs.lock"
DEST=".libs.tar.gz"
DOWNLOAD=true
TARGET_PLATFORMS=("ios" "android")

if ! type "curl" > /dev/null; then
    echo "Missed curl dependency" >&2;
    exit 1;
fi
if ! type "tar" > /dev/null; then
    echo "Missed tar dependency" >&2;
    exit 1;
fi

if [ -f ${LOCK} ]; then
    CURRENT_VERSION=$(cat ${LOCK})

    if [ "${CURRENT_VERSION}" == "${VERSION}" ];then
        DOWNLOAD=false
    fi
fi

if [ "$DOWNLOAD" = true ]; then
	for platform in "${TARGET_PLATFORMS[@]}"
	do
		URL="https://github.com/markneh/react-native-pjsip-builder/releases/download/${VERSION}/${platform}.tar.gz"
        curl -L --silent "${URL}" -o "${platform}${DEST}"
        tar -xvf "${platform}${DEST}"
        rm -f "${platform}${DEST}"
	done

    echo "${VERSION}" > ${LOCK}
fi
