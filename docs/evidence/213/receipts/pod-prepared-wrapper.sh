#!/bin/sh
set -eu
baseline213_root="<evidence-root>"
if [ "${1:-}" = install ]; then
  if [ "$PWD" != "$baseline213_root/sources/prepared-localsend/app/ios" ]; then
    echo 'prepared-input lock resolution called outside approved clone' >&2
    exit 97
  fi
  printf '%s\n' "cwd=$PWD" "$@" >> "$baseline213_root/logs/pod-prepared-invocations.args"
fi
exec "$baseline213_root/tools/gem-bin/pod" "$@"
