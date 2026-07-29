#!/usr/bin/env bash

SRC=""
SHOW_HELP=false
DEBUG=true
CLEAN=true

for arg in "$@"; do
	case $arg in
	--help) SHOW_HELP=true ;;
	--no-debug) DEBUG=false ;;
	--no-clean) CLEAN=false ;;
	-*)
		echo "Unknown option: $arg"
		exit 1
		;;
	*) SRC="$arg" ;;
	esac
done

# If help was requested, show the various options we support
if [[ "$SHOW_HELP" == true ]]; then
	echo "Usage: x.sh [options] <input file>"
	echo "Options:"
	echo "  --help       Show this help menu"
	echo "  --no-debug   Disable debug mode and optimisations"
	echo "  --no-clean   Prevent deletion of the generated binary"
	exit 0
fi

# Ensure we have a source file
if [[ -z "$SRC" ]]; then
	echo "Error: No source file provided."
	echo "Usage: x.sh [options] <input file>"
	exit 1
fi

OUT="${SRC%.*}"
EXT="${SRC##*.}"
INPUT="${SRC%.*}.in"

has_valgrind() {
	command -v valgrind &>/dev/null
}

run_binary() {
	local cmd=()

	if [[ "$DEBUG" == true ]] && has_valgrind; then
		cmd+=(valgrind --leak-check=full --show-leak-kinds=all --track-origins=yes)
	fi

	cmd+=(./"${OUT}")

	if [[ -f "${INPUT}" ]]; then
		"${cmd[@]}" <"${INPUT}"
	else
		"${cmd[@]}"
	fi

	if [[ "$CLEAN" == true ]]; then
		rm -f "${OUT}"
	fi
}

case ${EXT} in
s)
	if [[ "$DEBUG" == true ]]; then
		as -g -o "${OUT}.o" "${SRC}"
		ld -o "${OUT}" "${OUT}.o"
	else
		as -o "${OUT}.o" "${SRC}"
		ld -s -o "${OUT}" "${OUT}.o"
	fi

	if [[ "$CLEAN" == true ]]; then
		rm -f "${OUT}.o"
	fi

	run_binary
	;;
f90)
	if [[ "$DEBUG" == true ]]; then
		gfortran "${SRC}" -g -O0 -fcoarray=single -fbounds-check -std=f2023 -Wall -Wextra -pedantic -march=native -o "${OUT}"
	else
		gfortran "${SRC}" -fcoarray=single -fbounds-check -std=f2023 -Wall -Wextra -pedantic -O2 -march=native -o "${OUT}"
	fi

	run_binary
	;;
nim)
	nim c --verbosity:0 --hints:off -d:release "${SRC}"
	run_binary
	;;

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
		./"${OUT}" <"${INPUT}"
	else
		./"${OUT}"
	fi

	if [[ "$CLEAN" == true ]]; then
		rm -f "${OUT}" "${OUT}".hi "${OUT}".o
	fi
	;;

c)
	if [[ "$DEBUG" == true ]]; then
		gcc -g -Wall -Werror -pedantic -std=c11 -o "${OUT}" "${SRC}"
	else
		gcc -Wall -Werror -std=c11 -O2 -o "${OUT}" "${SRC}"
	fi
	run_binary
	;;

cpp | c++ | cxx)
	if [[ "$DEBUG" == true ]]; then
		g++ -g -Wall -Werror -pedantic -std=c++2a -o "${OUT}" "${SRC}"
	else
		g++ -Wall -Werror -std=c++2a -O2 -o "${OUT}" "${SRC}"
	fi
	run_binary
	;;

java)
	javac "${SRC}"

	if [[ -f "${INPUT}" ]]; then
		java -cp . "${OUT}" <"${INPUT}"
	else
		java -cp . "${OUT}"
	fi

	if [[ "$CLEAN" == true ]]; then
		rm -f "${OUT}.class"
	fi

	;;

rs)
	if [[ "$DEBUG" == true ]]; then
		rustc -g "${SRC}"
	else
		rustc -O "${SRC}"
	fi

	run_binary
	;;

py)
	if [[ -f "${INPUT}" ]]; then
		python3 "${SRC}" <"${INPUT}"
	else
		python3 "${SRC}"
	fi
	;;

*)
	echo "Unsupported file type: ${EXT}"
	;;
esac
