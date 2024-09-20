#!/usr/bin/env bash

die()
{
  local _return="${2:-1}"
  echo "$1" >&2
  exit "${_return}"
}

set -euo pipefail

SCRIPTDIR="$(dirname "$(realpath "${BASH_SOURCE[0]:-"$0"}")")"
ROOTDIR="$SCRIPTDIR/../.."
CHART_FILE=${CHART_FILE:-"$ROOTDIR/chart/Chart.yaml"}
INDEX_REMOTE="${INDEX_REMOTE:-origin}"
INDEX_FILE=$(mktemp)
DEBUG=${DEBUG:-}
DATE_TIME_FMT="%Y-%m-%d-%H-%M-%S"

trap "rm '$INDEX_FILE'" HUP QUIT EXIT TERM INT

# Branch to check
CHECK_BRANCH=
# The $date-$time for the main branch
DATE_TIME=
# Upgrade from develop to release/x.y*
DEVELOP_TO_REL=
# Update the release version after release
RELEASED=
# Upgrade from develop to helm-testing
HELM_TESTING=
# Tag that has been pushed
APP_TAG=
# Version from the Chart.yaml
CHART_VERSION=
# AppVersion from the Chart.yaml
CHART_APP_VERSION=
# Updated Version from the Chart.yaml
NEW_CHART_VERSION=
# Updated AppVersion from the Chart.yaml
NEW_CHART_APP_VERSION=
INDEX_CHART_VERSIONS=
LATEST_RELEASE_BRANCH=
BUMP_MAJOR_FOR_MAIN=
EXPECT_FAIL=
FAILED=

build_output()
{
  if [ -n "$CHECK_BRANCH" ]; then
    if [ -n "$HELM_TESTING" ]; then
      cat <<EOF
APP_TAG: $APP_TAG
CHART_VERSION: $CHART_VERSION
CHART_APP_VERSION: $CHART_APP_VERSION
NEW_CHART_VERSION: $NEW_CHART_VERSION
NEW_CHART_APP_VERSION: $NEW_CHART_APP_VERSION
EOF
    elif [ -n "$DEVELOP_TO_REL" ]; then
      if [ -n "$NEW_CHART_VERSION" ]; then
        cat <<EOF
APP_TAG: $APP_TAG
CHART_VERSION: $CHART_VERSION
CHART_APP_VERSION: $CHART_APP_VERSION
NEW_CHART_VERSION: $NEW_CHART_VERSION
NEW_CHART_APP_VERSION: $NEW_CHART_APP_VERSION
EOF
      else
        cat <<EOF
APP_TAG: $APP_TAG
CHART_VERSION: $CHART_VERSION
CHART_APP_VERSION: $CHART_APP_VERSION
EOF
      fi
    else
      cat <<EOF
APP_TAG: $APP_TAG
CHART_VERSION: $CHART_VERSION
CHART_APP_VERSION: $CHART_APP_VERSION
EOF
    fi
  else
    if [ -n "$RELEASED" ]; then
      APP_TAG=$NEW_CHART_VERSION
    fi
    cat <<EOF
APP_TAG: $APP_TAG
CHART_VERSION: $CHART_VERSION
CHART_APP_VERSION: $CHART_APP_VERSION
NEW_CHART_VERSION: $NEW_CHART_VERSION
NEW_CHART_APP_VERSION: $NEW_CHART_APP_VERSION
EOF
  fi
}

build_index_file()
{
  cat <<EOF >$INDEX_FILE
apiVersion: v1
entries:
  mayastor:
EOF

  for v in "${INDEX_CHART_VERSIONS[@]}"
  do
    echo "  - version: $v" >> $INDEX_FILE
  done
}

call_script()
{
  ARGS="--override-chart "$CHART_VERSION" "$CHART_APP_VERSION" --index-file "$INDEX_FILE" --dry-run"
  if [ -n "$CHECK_BRANCH" ]; then
    ARGS="--check-chart $CHECK_BRANCH $ARGS"
    if [ -n "$DEVELOP_TO_REL" ]; then
      ARGS="--develop-to-release $ARGS"
    fi
    if [ -n "$HELM_TESTING" ]; then
      ARGS="--helm-testing $HELM_TESTING $ARGS"
    fi
    if [ -n "$LATEST_RELEASE_BRANCH" ]; then
      ARGS="--latest-release-branch $LATEST_RELEASE_BRANCH $ARGS"
      if [ "$BUMP_MAJOR_FOR_MAIN" = "true" ]; then
        ARGS="--bump-major-for-main $ARGS"
      fi
    fi
  else
    if [ -n "$RELEASED" ]; then
      ARGS="--released $RELEASED $ARGS"
    fi
    if [ -n "$APP_TAG" ]; then
      ARGS="--app-tag $APP_TAG $ARGS"
    fi
  fi

  if [ -n "$DATE_TIME" ]; then
      ARGS="--date-time $DATE_TIME $ARGS"
  fi
  $SCRIPTDIR/publish-chart-yaml.sh $ARGS
}

test_one()
{
  RED='\033[0;31m'
  ORANGE='\033[0;33m'
  GREEN='\033[0;32m'
  YEL='\033[1;33m'
  PRP='\033[0;35m'
  NC='\033[0m' # No Color

  build_index_file
  set +e
  if [ -n "$DEBUG" ]; then
    actual=$(call_script)
  else
    actual=$(call_script 2>/dev/null)
  fi
  _err=$?
  set -e

  if [ $_err != 0 ]; then
    if [ -z "$EXPECT_FAIL" ]; then
      echo -e "${PRP}L${NC}$BASH_LINENO${ORANGE} =>${NC} ${RED}FAIL${NC} \$?=$_err"
      FAILED=1
    else
      echo -e "${PRP}L${NC}$BASH_LINENO${ORANGE} =>${NC} ${GREEN}OK${NC} \$?=$_err"
    fi
  else
    output=$(build_output)
    if [ "$output" != "$actual" ]; then
      echo -e "${PRP}L${NC}$BASH_LINENO${ORANGE} =>${NC} ${RED}FAIL${NC}"
      echo -e "${ORANGE}Expected:${NC}\n$output"
      echo -e "${ORANGE}Actual:${NC}\n$actual"
      FAILED=1
    else
      echo -e "${PRP}L${NC}$BASH_LINENO${ORANGE} =>${NC} ${GREEN}OK${NC}"
    fi
  fi

  CHECK_BRANCH=
  DATE_TIME=
  DEVELOP_TO_REL=
  RELEASED=
  HELM_TESTING=
  APP_TAG=
  CHART_VERSION=
  CHART_APP_VERSION=
  INDEX_CHART_VERSIONS=
  NEW_CHART_VERSION=
  NEW_CHART_APP_VERSION=
  LATEST_RELEASE_BRANCH=
  BUMP_MAJOR_FOR_MAIN=
  EXPECT_FAIL=
}

CHECK_BRANCH=develop
APP_TAG=0.0.0
CHART_VERSION=0.0.0
CHART_APP_VERSION=0.0.0
test_one "Develop is special"

CHECK_BRANCH=helm-testing/develop
DATE_TIME=$(date +"$DATE_TIME_FMT")
LATEST_RELEASE_BRANCH="release/123.456"
BUMP_MAJOR_FOR_MAIN="false"
APP_TAG=123.457.0-0-main-unstable-$DATE_TIME-0
CHART_VERSION=0.0.0
CHART_APP_VERSION=0.0.0
test_one "helm-testing/develop is special"

CHECK_BRANCH=helm-testing/develop
DATE_TIME=$(date +"$DATE_TIME_FMT")
LATEST_RELEASE_BRANCH="release/123.456"
BUMP_MAJOR_FOR_MAIN="true"
APP_TAG=124.0.0-0-main-unstable-$DATE_TIME-0
CHART_VERSION=0.0.0
CHART_APP_VERSION=0.0.0
test_one "helm-testing/develop is special"

CHECK_BRANCH=helm-testing/develop
HELM_TESTING=helm-testing/develop
DATE_TIME=$(date +"$DATE_TIME_FMT")
LATEST_RELEASE_BRANCH="release/123.456"
BUMP_MAJOR_FOR_MAIN="false"
APP_TAG=123.457.0-0-main-unstable-$DATE_TIME-0
CHART_VERSION=0.0.0
CHART_APP_VERSION=0.0.0
NEW_CHART_VERSION=123.457.0-0-main-unstable-$DATE_TIME-0
NEW_CHART_APP_VERSION=123.457.0-0-main-unstable-$DATE_TIME-0
test_one "helm-testing/develop is special"

CHECK_BRANCH=helm-testing/develop
HELM_TESTING=helm-testing/develop
DATE_TIME=$(date +"$DATE_TIME_FMT")
LATEST_RELEASE_BRANCH="release/123.456"
BUMP_MAJOR_FOR_MAIN="true"
APP_TAG=124.0.0-0-main-unstable-$DATE_TIME-0
CHART_VERSION=0.0.0
CHART_APP_VERSION=0.0.0
NEW_CHART_VERSION=124.0.0-0-main-unstable-$DATE_TIME-0
NEW_CHART_APP_VERSION=124.0.0-0-main-unstable-$DATE_TIME-0
test_one "helm-testing/develop is special"

CHECK_BRANCH=helm-testing/develop
HELM_TESTING=helm-testing/develop
LATEST_RELEASE_BRANCH="release/123.456"
BUMP_MAJOR_FOR_MAIN="true"
APP_TAG=124.0.0-0-main-unstable-main-0
CHART_VERSION=13.14.15
CHART_APP_VERSION=13.14.15
NEW_CHART_VERSION=124.0.0-0-main-unstable-main-0
NEW_CHART_APP_VERSION=124.0.0-0-main-unstable-main-0
EXPECT_FAIL=1
test_one "helm-testing/develop is special"

CHECK_BRANCH=release/2.0
APP_TAG=2.0.0
CHART_VERSION=2.0.0
CHART_APP_VERSION=2.0.0
test_one "Release branch without patch version"

CHECK_BRANCH=release/2.0.1
APP_TAG=2.0.1
CHART_VERSION=2.0.1
CHART_APP_VERSION=2.0.1
test_one "Release branch with patch version"

CHECK_BRANCH=release/2
APP_TAG=2.0.0
CHART_VERSION=2.0.0
CHART_APP_VERSION=2.0.0
EXPECT_FAIL=1
test_one "Release branch with no minor is not expected"

CHECK_BRANCH=release/2.0.1
APP_TAG=2.0.1
CHART_VERSION=2.0.1
CHART_APP_VERSION=2.0.1
test_one "Release branch with patch version"

CHECK_BRANCH=release/2.0.1
DEVELOP_TO_REL=1
APP_TAG=2.0.1
CHART_VERSION=0.0.0
CHART_APP_VERSION=0.0.0
NEW_CHART_VERSION=2.0.1
NEW_CHART_APP_VERSION=2.0.1
test_one "Upgrade from develop to release"

CHECK_BRANCH=release/2.0.1
DEVELOP_TO_REL=1
APP_TAG=2.0.1
CHART_VERSION=2.0.1
CHART_APP_VERSION=2.0.1
test_one "Already on release, no new version"

APP_TAG=2.0.0-a.0
CHART_VERSION=2.0.0
CHART_APP_VERSION=2.0.0
INDEX_CHART_VERSIONS=()
NEW_CHART_VERSION=2.0.0-a.0
NEW_CHART_APP_VERSION=2.0.0-a.0
test_one "Add the first alpha version"

APP_TAG=2.0.0-a.0
CHART_VERSION=2.0.0
CHART_APP_VERSION=2.0.0
INDEX_CHART_VERSIONS=(2.0.0-a.0)
NEW_CHART_VERSION=2.0.0-a.1
NEW_CHART_APP_VERSION=2.0.0-a.0
test_one "Adding the first alpha tag, but it already exists in the index, so it gets bumped"

APP_TAG=2.0.0-b.0
CHART_VERSION=2.0.0
CHART_APP_VERSION=2.0.0
INDEX_CHART_VERSIONS=(2.0.0-a.0)
NEW_CHART_VERSION=2.0.0-b.0
NEW_CHART_APP_VERSION=2.0.0-b.0
test_one "Updating to the first beta tag"

APP_TAG=2.0.0-a.1
CHART_VERSION=2.0.0
CHART_APP_VERSION=2.0.0
INDEX_CHART_VERSIONS=(2.0.0-a.0)
NEW_CHART_VERSION=2.0.0-a.1
NEW_CHART_APP_VERSION=2.0.0-a.1
test_one "Updating to a newer prerelease tag within the same prefix"

APP_TAG=2.0.0-b.0
CHART_VERSION=2.0.0
CHART_APP_VERSION=2.0.0
INDEX_CHART_VERSIONS=(2.0.0-a.0 2.0.0-b.3)
NEW_CHART_VERSION=2.0.0-b.4
NEW_CHART_APP_VERSION=2.0.0-b.0
test_one "Updating to the first beta tag, but a newer version already exists in the index, so it gets bumped"

APP_TAG=2.0.0-a.0
CHART_VERSION=2.0.0-a.0
CHART_APP_VERSION=2.0.0
INDEX_CHART_VERSIONS=()
EXPECT_FAIL=1
test_one "Chart Version and appVersion must match"

APP_TAG=2.0.0-a.0
CHART_VERSION=2.0.0
CHART_APP_VERSION=2.0.0-a.0
EXPECT_FAIL=1
test_one "Chart Version and appVersion must match"

APP_TAG=2.1.0
CHART_VERSION=2.0.0
CHART_APP_VERSION=2.0.0
EXPECT_FAIL=1
test_one "Chart Versions and app tag must not differ more than patch"

APP_TAG=2.0.0-b.1
CHART_VERSION=2.0.0
CHART_APP_VERSION=2.0.0
INDEX_CHART_VERSIONS=(2.0.0-c.0)
NEW_CHART_VERSION=2.0.0-b.1
NEW_CHART_APP_VERSION=2.0.0-b.1
test_one "A newer prerelease already exists, update chart on the app tag prerelease prefix"

APP_TAG=2.0.0
CHART_VERSION=2.0.0
CHART_APP_VERSION=2.0.0
INDEX_CHART_VERSIONS=(2.0.0)
EXPECT_FAIL=1
test_one "The stable version is already published"

APP_TAG=2.0.0
CHART_VERSION=2.0.0
CHART_APP_VERSION=2.0.0
INDEX_CHART_VERSIONS=(2.0.0-c.0 2.0.0-b.3 2.0.0)
EXPECT_FAIL=1
test_one "The stable version is already published"

APP_TAG=2.0.0
CHART_VERSION=2.0.0
CHART_APP_VERSION=2.0.0
INDEX_CHART_VERSIONS=(2.0.1 2.0.0-a.0)
NEW_CHART_VERSION=2.0.0
NEW_CHART_APP_VERSION=2.0.0
test_one "A more stable version is already published, but the app tag stable is new"

RELEASED=2.0.0
CHART_VERSION=2.0.0
CHART_APP_VERSION=2.0.0
NEW_CHART_VERSION=2.0.1
NEW_CHART_APP_VERSION=2.0.1
test_one "After release 2.0.0, the next one is 2.0.1"

RELEASED=2.0.0
CHART_VERSION=2.0.0
CHART_APP_VERSION=2.0.0
INDEX_CHART_VERSIONS=(2.0.1 2.0.0-a.0)
EXPECT_FAIL=1
test_one "We've actually already release 2.0.1, so the next one is 2.0.2"

RELEASED=2.0.1
CHART_VERSION=2.0.0
CHART_APP_VERSION=2.0.0
INDEX_CHART_VERSIONS=(2.0.1 2.0.0-a.0)
NEW_CHART_VERSION=2.0.2
NEW_CHART_APP_VERSION=2.0.2
test_one "We've actually already release 2.0.1, so the next one is 2.0.2"

RELEASED=2.2.0
CHART_VERSION=2.0.0
CHART_APP_VERSION=2.0.0
EXPECT_FAIL=1
test_one "Can't bump beyond patch!"

RELEASED=1.2.0
CHART_VERSION=2.0.0
CHART_APP_VERSION=2.0.0
EXPECT_FAIL=1
test_one "Can't bump to an older version!"

RELEASED=1.2.0
APP_TAG=1.2.0
CHART_VERSION=2.0.0
CHART_APP_VERSION=2.0.0
EXPECT_FAIL=1
test_one "Can't specify both!"

echo "Done"

if [ -n "$FAILED" ]; then
  echo "Test failed"
  exit 1
fi
