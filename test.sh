#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
testbin=$(mktemp -d)
trap 'rm -rf "$testbin"' EXIT
swiftc -parse-as-library -D ENGINE_TEST -swift-version 5 Sources/*.swift Tests/EngineTests.swift -o "$testbin/engine-tests"
"$testbin/engine-tests"

node Tests/TuyaTests.cjs

node Tests/HomeKitTests.cjs
