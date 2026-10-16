#!/bin/sh
set -eu
case "${1-}" in
  install) shift; set -- install --deployment "$@" ;;
esac
printf '%s\n' '--- pod invocation ---' "$@" >> "<evidence-root>/logs/pod-invocations.args"
exec "<evidence-root>/tools/gem-bin/pod" "$@"
