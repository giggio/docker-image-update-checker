#!/usr/bin/env bash

getLayers() {
    set -euo pipefail

    local REGISTRY=$1
    local REPO=$2
    local DIGEST_LIST=$3
    if [ -z "${4+x}" ]; then
        local OS=''
    else
        local OS=$4
    fi
    if [ -z "${5+x}" ]; then
        local ARCH=''
    else
        local ARCH=$5
    fi

    local AUTH
    AUTH=`getToken "$REGISTRY" "$REPO"`
    if [ "$AUTH" != "" ]; then
        AUTH="Authorization: Bearer $AUTH"
    fi
    if [ "$VERBOSE" == "true" ]; then
        echo "curl -s -H \"$AUTH\" -H \"Accept: application/vnd.docker.distribution.manifest.list.v2+json;q=0.9, application/vnd.oci.image.index.v1+json;q=0.8, application/vnd.docker.distribution.manifest.v2+json;q=0.7\" \"https://$REGISTRY/v2/$REPO/manifests/$DIGEST_LIST\"" > "`tty`"
    fi
    # if we request a manifest list from docker hub for an image that is not multi-arch, it will return
    # a v1 manifest by default; comparison of a v1 manifest of an image to a v2 manifest of a base image indicates
    # updating is needed even if it should not, so it is better to request a manifest.list if possible and a 
    # manifest.v2 otherwise. Maybe we should catch comparing v1 to v2 layers alltogether?
    MANIFESTS=`curl -s -H "$AUTH" -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json;q=0.9, application/vnd.oci.image.index.v1+json;q=0.8, application/vnd.docker.distribution.manifest.v2+json;q=0.7" "https://$REGISTRY/v2/$REPO/manifests/$DIGEST_LIST"`
    if jq -Mcre '.. | .errors? | select(type == "array" and length != 0)' <<< "$MANIFESTS" > /dev/null; then
        >&2 echo "Error getting manifest for repo $REGISTRY/$REPO:$DIGEST_LIST."
        exit 64
    fi
    VERSION=`jq -r .schemaVersion <<< "$MANIFESTS"`
    MEDIATYPE=`jq -r .mediaType <<< "$MANIFESTS"`
    if [ "$VERBOSE" == "true" ]; then
        echo "Fetched MANIFESTS content:" > "`tty`"
        echo "$MANIFESTS" > "`tty`"
    fi
    if [ "$VERSION" == '1' ] ; then
        if [ "$VERBOSE" == "true" ]; then
            echo "Using schema version 1" > "`tty`"
        fi
        jq -r '.fsLayers[] | .blobSum' <<< "$MANIFESTS" | tac
    elif [[ "$VERSION" == '2'  && ("$MEDIATYPE" == 'application/vnd.docker.distribution.manifest.list.v2+json' || "$MEDIATYPE" == 'application/vnd.oci.image.index.v1+json') ]]; then
        if [ "$VERBOSE" == "true" ]; then
            echo "Using schema version 2" > "`tty`"
        fi
        if [ "$OS" == "" ]; then
            if [ "`uname`" == 'Linux' ]; then
                OS='linux'
            else
                OS='windows'
            fi
        fi
        if [ "$ARCH" == "" ]; then
            case `uname -m` in
                # todo: handle other cases: ppc64le, s390x, riscv64 etc.
                # todo: is next line correct?
                i386)   ARCH="386" ;;
                # todo: is next line correct?
                i686)   ARCH="386" ;;
                x86_64) ARCH="amd64" ;;
                arm)    dpkg --print-architecture | grep -q arm64 && ARCH=arm64 || ARCH=arm ;;
                *)
                    >&2 echo "Unknown architecture: `uname -m`"
                    exit 1 ;;
            esac
        fi
        export OS=$OS
        export ARCH=$ARCH
        DIGEST=`jq -r '[ .manifests[] | select( .platform.architecture == env.ARCH and .platform.os == env.OS ) ][0].digest' <<< "$MANIFESTS"`
        if [ "$DIGEST" == "null" ]; then
            >&2 echo "No manifest found for $OS/$ARCH"
            exit 1
        fi
        if [ "$VERBOSE" == "true" ]; then
            echo "curl -s -H \"$AUTH\" -H \"Accept: application/vnd.docker.distribution.manifest.v2+json;q=0.9, application/vnd.oci.image.manifest.v1+json;q=0.8\" \"https://$REGISTRY/v2/$REPO/manifests/$DIGEST\"" > "`tty`"
        fi
        MANIFEST=`curl -s -H "$AUTH" -H "Accept: application/vnd.docker.distribution.manifest.v2+json;q=0.9, application/vnd.oci.image.manifest.v1+json;q=0.8" "https://$REGISTRY/v2/$REPO/manifests/$DIGEST"`
        jq -r '.layers[].digest' <<<"$MANIFEST"
    elif [[ "$VERSION" == '2' && ("$MEDIATYPE" == 'application/vnd.docker.distribution.manifest.v2+json' || "$MEDIATYPE" == 'application/vnd.oci.image.manifest.v1+json') ]]; then
        # ghcr gives us a manifest even though we requested a manifest list
        # if we don't use the multiarch functionality, this is fine.
        if [ "$OS" == "" ] && [ "$ARCH" == "" ]; then
            jq -r '.layers[].digest' <<<"$MANIFESTS"
        else
            # such as ghcr.io
            >&2 echo "Registry of $REGISTRY/$REPO:$DIGEST_LIST does not support manifest lists, which are required for multiarch functionality."
            exit 1
        fi
    else
        >&2 echo "Unknown schema version $VERSION with media type $MEDIATYPE"
        exit 1
    fi
}

getToken() {
    set -euo pipefail

    local REGISTRY=$1
    local REPO=$2

    if [ "$REGISTRY" == "index.docker.io" ]; then
        if [ "$VERBOSE" == "true" ]; then
            echo "curl -s \"https://auth.docker.io/token?service=registry.docker.io&scope=repository:$REPO:pull\"" > "`tty`"
        fi
        curl -s "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$REPO:pull" | jq -r '.token'
    elif [ "$REGISTRY" == "ghcr.io" ]; then
        echo "$GITHUB_TOKEN" | base64
    else
        echo ""
    fi
}

set -euo pipefail

if [ -z "${ARCH+x}" ]; then
    ARCH=''
fi
if [ -z "${OS+x}" ]; then
    OS=''
fi
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
IFS=: read BASE BASE_TAG <<< "${FULL_BASE#*/}"
IFS=: read IMAGE IMAGE_TAG <<< "${FULL_IMAGE#*/}"

if [ "$VERBOSE" == "true" ]; then
    echo Base image: "$FULL_BASE"
fi
set +e
if ! LAYERS_BASE=`getLayers "$BASE_REPO" "$BASE" "${BASE_TAG:-latest}" "$OS" "$ARCH"`; then
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
    echo Image: "$FULL_IMAGE"
fi
set +e
LAYERS_IMAGE=`getLayers "$IMAGE_REPO" "$IMAGE" "${IMAGE_TAG:-latest}" "$OS" "$ARCH"`
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

