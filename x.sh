#!/usr/bin/env bash

SRC="$1"
shift

OUT="${SRC%.*}"
EXT="${SRC##*.}"
INPUT="${SRC%.*}.in"
FLAG="$@"

case ${EXT} in
  cpp | c++ | cxx)
    g++ -Wall -Werror -std=c++2a -o ${OUT} ${SRC}

    if [[ -f "${INPUT}" ]]; then
      ./${OUT} < ${INPUT}
    else
      ./${OUT}
    fi

    if [[ "${FLAG}" != *"--no-clean"* ]]; then
      rm -f ${OUT}
    fi
    ;;

  java)
    javac ${SRC}

    if [[ -f "${INPUT}" ]]; then
      java -cp . ${OUT} < ${INPUT}
    else
      java -cp . ${OUT}
    fi

    if [[ "${FLAG}" != *"--no-clean"* ]]; then
      rm -f "${OUT}.class"
    fi

    ;;

  rs)
    rustc -O ${SRC}

    if [[ -f "${INPUT}" ]]; then
      ./${OUT} < ${INPUT}
    else
      ./${OUT}
    fi

    if [[ "${FLAG}" != *"--no-clean"* ]]; then
      rm -f ${OUT}
    fi
    ;;

  py)
    if [[ -f "${INPUT}" ]]; then
      python3 ${SRC} < ${INPUT}
    else
      python3 ${SRC}
    fi
    ;;

  *)
    echo "Unsupported file type: ${EXTENSION}"
    ;;
esac
