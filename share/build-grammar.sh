#!/usr/bin/env bash
set -euo pipefail

# Build tree-sitter-perl grammar for use with Text::TreeSitter
#
# Prerequisites:
#   - C compiler (cc)
#   - libtree-sitter installed (brew install tree-sitter)
#   - git

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GRAMMAR_DIR="$SCRIPT_DIR/tree-sitter-perl"
OUTPUT="$SCRIPT_DIR/perl.dylib"

# Adjust extension for Linux
if [[ "$(uname)" == "Linux" ]]; then
    OUTPUT="$SCRIPT_DIR/perl.so"
fi

if [[ ! -d "$GRAMMAR_DIR" ]]; then
    echo "Cloning tree-sitter-perl..."
    git clone --depth 1 https://github.com/tree-sitter-perl/tree-sitter-perl.git "$GRAMMAR_DIR"
fi

# Generate parser.c if it doesn't exist (requires tree-sitter CLI + Node.js)
if [[ ! -f "$GRAMMAR_DIR/src/parser.c" ]]; then
    echo "Generating parser..."
    (cd "$GRAMMAR_DIR" && tree-sitter generate)
fi

echo "Building grammar..."
cc -shared -fPIC -o "$OUTPUT" \
    -I"$GRAMMAR_DIR/src" \
    $(pkg-config --cflags tree-sitter) \
    "$GRAMMAR_DIR/src/parser.c" \
    "$GRAMMAR_DIR/src/scanner.c"

echo "Built: $OUTPUT"
