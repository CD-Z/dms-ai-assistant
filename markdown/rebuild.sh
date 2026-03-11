#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)"
cd "$SCRIPT_DIR"

rm -rf ./build
rm ./*.so
cmake -B build
cmake --build build -j$(nproc)
