#!/bin/bash
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PARENT_DIR=$(dirname "$SCRIPT_DIR")
DIR_NAME=$(basename "$SCRIPT_DIR")
echo $DIR_NAME
echo $SCRIPT_DIR
echo $PARENT_DIR
