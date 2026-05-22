#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

sudo puppet apply \
  --modulepath=../modules:./modules \
  manifests/site.pp
