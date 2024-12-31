#!/usr/bin/env bash

function usage() {
  echo "Usage: wr <source-file>"
  exit 1
}

if [[ "$#" != 1 ]]; then
  usage
fi

FILE="$1"

watch -n 1 "x.sh ${FILE}"