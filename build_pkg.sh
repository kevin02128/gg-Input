#!/bin/bash
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$PROJECT_DIR/build_pkg.command" "$@"
