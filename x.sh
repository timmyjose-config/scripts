#!/usr/bin/env bash

SRC=""
SHOW_HELP=false
DEBUG=true
CLEAN=true
RUN_VALGRIND=false
RUN_THREAD_SAN=false
IS_MACOS=false

if [[ $(uname -s) == "Darwin" ]]; then
	IS_MACOS=true
fi

for arg in "$@"; do
	case $arg in
	--help) SHOW_HELP=true ;;
	--no-debug) DEBUG=false ;;
	--no-clean) CLEAN=false ;;
	--valgrind) RUN_VALGRIND=true ;;
	--thread) RUN_THREAD_SAN=true ;;
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
	echo "  --no-debug   Disable debug mode and optimisations (not on macOS)"
	echo "  --no-clean   Prevent deletion of the generated binary (not on macOS)"
	echo "  --valgrind   Override defaults and use valgrind for runtime testing (not on macOS)"
	echo "  --thread     Switch memory sanitisation to ThreadSanitizer (catches data races) (not on macOS)"
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

	# Use valgrind only if explicitly requested
	if [[ "$IS_MACOS" == false ]] && [[ "$DEBUG" == true ]] && [[ "$RUN_VALGRIND" == true ]] && has_valgrind; then
		local suppress=""

		if [[ -f "$HOME/.config/valgrind/rust.supp" ]]; then
			echo "Suppressions file found"
			suppress="--suppressions=$HOME/.config/valgrind/rust.supp"
		fi
		cmd+=(valgrind "$suppress" --leak-check=full --show-leak-kinds=all --track-origins=yes)
	fi

	cmd+=(./"${OUT}")

	# Force leak detection behaviour on for ASan executions
	if [[ "$IS_MACOS" == false ]] && [[ "$DEBUG" == true ]] && [[ "$RUN_VALGRIND" == false ]] && [[ "$RUN_THREAD_SAN" == false ]]; then
		export ASAN_OPTIONS="detect_leaks=1"
	fi

	if [[ -f "${INPUT}" ]]; then
		"${cmd[@]}" <"${INPUT}"
	else
		"${cmd[@]}"
	fi

	if [[ "$CLEAN" == true ]]; then
		rm -f "${OUT}"
	fi
}

SAN_FLAGS=""
RUST_SAN=""

if [[ "$DEBUG" == true ]] && [[ "$RUN_VALGRIND" == false ]]; then
	if [[ "$RUN_THREAD_SAN" == true ]]; then
		SAN_FLAGS="-fsanitize=thread,undefined"
		# only supported on nightly Rust
		if rustc --version | grep -q "nightly"; then
			RUST_SAN="-Z sanitizer=thread"
		fi
	else
		# Default: Maximum memory protection + leak checking
		SAN_FLAGS="-fsanitize=address,undefined"
		# Only supported on nightly Rust
		if rustc --version | grep -q "nightly"; then
			RUST_SAN="-Z sanitizer=address"
		fi
	fi
fi

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
	if [[ "$IS_MACOS" == false ]] && [[ "$DEBUG" == true ]]; then
		gfortran "${SRC}" -g -O0 -fcoarray=single -fbounds-check -std=f2023 -Wall -Wextra -pedantic -march=native ${SAN_FLAGS} -o "${OUT}"
	else
		gfortran "${SRC}" -fcoarray=single -fbounds-check -std=f2023 -Wall -Wextra -pedantic -O2 -march=native -o "${OUT}"
	fi

	run_binary
	;;

nim)
	# Nim has built in custom trackers, defaults to standard release/debug configurations
	if [[ "$DEBUG" == true ]]; then
		nim c --verbosity:0 --hints:off --debuginfo:on "${SRC}"
	else
		nim c --verbosity:0 --hints:off -d:release "${SRC}"
	fi
	run_binary
	;;

m | mm)
	COMPILER="clang"
	[[ "${EXT}" == "mm" ]] && COMPILER="clang++"
	if [[ "$IS_MACOS" == false ]] && [[ "$DEBUG" == true ]]; then
		$COMPILER -g -Wall -Werror -Wextra -fobjc-arc -framework Foundation ${SAN_FLAGS} "${SRC}" -o "${OUT}"
	else
		$COMPILER -O2 -Wall -Werror -Wextra -fobjc-arc -framework Foundation "${SRC}" -o "${OUT}"
	fi
	run_binary
	;;

swift)
	if [[ "$DEBUG" == true ]]; then
		swiftc -g "${SRC}" -o "${OUT}"
	fi
	run_binary
	;;

hs)
	if [[ "$DEBUG" == true ]]; then
		ghc -g -o "${OUT}" "${SRC}"
	else
		ghc -O2 -o "${OUT}" "${SRC}"
	fi

	if [[ -f "${INPUT}" ]]; then ./"${OUT}" <"${INPUT}"; else ./"${OUT}"; fi
	[[ "$CLEAN" == true ]] && rm -f "${OUT}" "${OUT}".hi "${OUT}".o
	;;

c)
	if [[ "$IS_MACOS" == false ]] && [[ "$DEBUG" == true ]]; then
		gcc -g -Wall -Wextra -pedantic -std=c11 ${SAN_FLAGS} -o "${OUT}" "${SRC}"
	else
		gcc -Wall -Wextra -Werror -std=c11 -O2 -o "${OUT}" "${SRC}"
	fi
	run_binary
	;;

cpp | c++ | cxx)
	if [[ "$IS_MACOS" == false ]] && [[ "$DEBUG" == true ]]; then
		g++ -g -Wall -Wextra -pedantic -std=c++2a ${SAN_FLAGS} -o "${OUT}" "${SRC}"
	else
		g++ -Wall -Wextra -Werror -std=c++2a -O2 -o "${OUT}" "${SRC}"
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
	if [[ "$IS_MACOS" == false ]] && [[ "$DEBUG" == true ]]; then
		rustc -g ${RUST_SAN} "${SRC}" -o "${OUT}"
	else
		rustc -O "${SRC}" -o "${OUT}"
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
