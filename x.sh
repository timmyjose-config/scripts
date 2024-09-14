#!/usr/bin/env bash

SRC="$1"
OUT="${SRC%.*}"
EXT="${SRC##*.}"
INPUT="${SRC%.*}.in"

case ${EXT} in
  cpp | c++ | cxx)
    g++ -Wall -Werror -std=c++2a -o ${OUT} ${SRC}

    if [[ -f "${INPUT}" ]]; then
      ./${OUT} < ${INPUT}
    else
      ./${OUT}
    fi

    rm -f ${OUT}
    ;;

  java)
    javac ${SRC}

    if [[ -f "${INPUT}" ]]; then
      java -cp . ${OUT} < ${INPUT}
    else
      java -cp . ${OUT}
    fi

    rm -f "${OUT}.class"

    ;;

  rs)
    rustc -O ${SRC}

    if [[ -f "${INPUT}" ]]; then
      ./${OUT} < ${INPUT}
    else
      ./${OUT}
    fi

    rm -f ${OUT}
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
