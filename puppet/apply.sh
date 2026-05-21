#!/usr/bin/env bash
set -euo pipefail

sudo puppet apply \
  --modulepath=./modules \
  manifests/site.pp
