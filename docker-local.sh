#!/usr/bin/env bash

getLayers() {
    set -euo pipefail

    local FULL_IMAGE_NAME=$1
    docker inspect $FULL_IMAGE_NAME --format='{{json .RootFS.Layers}}' | jq -r '.[]'
}

set -euo pipefail

if [ -z "${VERBOSE+x}" ]; then
    VERBOSE=''
fi

case `awk -F/ '{print NF-1}' <<< "$FULL_BASE"` in
    0) FULL_BASE="index.docker.io/library/$FULL_BASE" ;;
    1)
        if ! LC_ALL=en_US.utf8 grep -P '(?=^.{4,253}$)(^(?:[a-zA-Z0-9](?:(?:[a-zA-Z0-9\-]){0,61}[a-zA-Z0-9])?\.)+([a-zA-Z]{2,}|xn--[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])$)' <<< "${FULL_BASE%%/*}" > /dev/null; then
            FULL_BASE="index.docker.io/$FULL_BASE"
        fi ;;
esac
case `awk -F/ '{print NF-1}' <<< "$FULL_IMAGE"` in
    0) FULL_IMAGE="index.docker.io/library/$FULL_IMAGE" ;;
    1)
        if ! LC_ALL=en_US.utf8 grep -P '(?=^.{4,253}$)(^(?:[a-zA-Z0-9](?:(?:[a-zA-Z0-9\-]){0,61}[a-zA-Z0-9])?\.)+([a-zA-Z]{2,}|xn--[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])$)' <<< "${FULL_IMAGE%%/*}" > /dev/null; then
            FULL_IMAGE="index.docker.io/$FULL_IMAGE"
        fi ;;
esac

BASE_REPO="${FULL_BASE%%/*}"
IMAGE_REPO="${FULL_IMAGE%%/*}"
IFS=: read BASE BASE_TAG <<< ${FULL_BASE#*/}
IFS=: read IMAGE IMAGE_TAG <<< ${FULL_IMAGE#*/}

if [ "$VERBOSE" == "true" ]; then
    echo Base image: $FULL_BASE
fi
set +e
LAYERS_BASE=`getLayers $BASE_REPO/$BASE:${BASE_TAG:-latest}`
if [ "$?" != "0" ]; then
    >&2 echo "Error getting layers for $FULL_BASE."
    exit 1
fi
set -e
if [ "$LAYERS_BASE" == "" ]; then
    >&2 echo "No layers found for $FULL_BASE."
    exit 1
fi
if [ "$VERBOSE" == "true" ]; then
    echo Layers:
    echo "$LAYERS_BASE"
    echo Image: $FULL_IMAGE
fi
set +e
LAYERS_IMAGE=`getLayers $IMAGE_REPO/$IMAGE:${IMAGE_TAG:-latest}`
exitCode=$?
if [ "$exitCode" != "0" ]; then
    >&2 echo "Error getting layers for $FULL_IMAGE."
    if [ "$exitCode" == "64" ]; then
        # special treatment for when the image does not yet exist (first build)
        # we can't be sure that that is the case as docker hub does not offer a
        # way to check if an image exists
        exit $exitCode
    else
        exit 1
    fi
fi
set -e
if [ "$LAYERS_IMAGE" == "" ]; then
    echo "No layers found for $FULL_IMAGE."
    exit 1
fi
if [ "$VERBOSE" == "true" ]; then
    echo Layers:
    echo "$LAYERS_IMAGE"
fi

if [[ "$LAYERS_IMAGE" == "$LAYERS_BASE"* ]]; then
  echo false
else
  echo true
fi

