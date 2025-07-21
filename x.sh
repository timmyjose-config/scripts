#!/usr/bin/env bash

SRC="$1"
shift

OUT="${SRC%.*}"
EXT="${SRC##*.}"
INPUT="${SRC%.*}.in"
FLAG="$@"

run_binary() {
    if [[ -f "${INPUT}" ]]; then
      ./"${OUT}" < ${INPUT}
    else
      ./"${OUT}"
    fi

    if [[ "${FLAG}" != *"--no-clean"* ]]; then
      rm -f "${OUT}"
    fi
}

case ${EXT} in
  mm)
    clang++ -Wall -Werror -Wextra -fobjc-arc -framework Foundation "${SRC}" -o "${OUT}"
    run_binary
    ;;

  m)
    clang -Wall -Werror -Wextra -fobjc-arc -framework Foundation "${SRC}" -o "${OUT}"
    run_binary
    ;;

  swift)
    swiftc "${SRC}"
    run_binary
    ;;

  hs)
    ghc -o "${OUT}" "${SRC}"

    if [[ -f "${INPUT}" ]]; then
      ./"${OUT}" < ${INPUT}
    else
      ./"${OUT}"
    fi

    if [[ "${FLAG}" != *"--no-clean"* ]]; then
      rm -f "${OUT}" "${OUT}".hi "${OUT}".o
    fi
    ;;

  c)
    gcc -Wall -Werror -std=c11 -o "${OUT}" "${SRC}"
    run_binary
    ;;

  cpp | c++ | cxx)
    g++ -Wall -Werror -std=c++2a -o "${OUT}" "${SRC}"
    run_binary
    ;;

  java)
    javac "${SRC}"

    if [[ -f "${INPUT}" ]]; then
      java -cp . "${OUT}" < ${INPUT}
    else
      java -cp . "${OUT}"
    fi

    if [[ "${FLAG}" != *"--no-clean"* ]]; then
      rm -f "${OUT}.class"
    fi

    ;;

  rs)
    rustc -O "${SRC}"
    run_binary
    ;;

  py)
    if [[ -f "${INPUT}" ]]; then
      python3 "${SRC}" < ${INPUT}
    else
      python3 "${SRC}"
    fi
    ;;

  *)
    echo "Unsupported file type: ${EXT}"
    ;;
esac
