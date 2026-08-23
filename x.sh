#!/usr/bin/env bash

SRC=""
SHOW_HELP=false
DEBUG=true
CLEAN=true
RUN_VALGRIND=false
RUN_THREAD_SAN=false
IS_MACOS=false
PARALLEL=false
IMAGE_COUNT=""
OPENMP=false
OPENMP_THREAD_COUNT=""
MPI=false
MPI_RANK_COUNT=""
PROGRAM_ARGS=()

if [[ $(uname -s) == "Darwin" ]]; then
	IS_MACOS=true
fi

# Parse options and separate the source file from program runtime arguments
while [[ $# -gt 0 ]]; do
	case "$1" in
	--help)
		SHOW_HELP=true
		shift
		;;
	--no-debug)
		DEBUG=false
		shift
		;;
	--no-clean)
		CLEAN=false
		shift
		;;
	--valgrind)
		RUN_VALGRIND=true
		shift
		;;
	--thread)
		RUN_THREAD_SAN=true
		shift
		;;
	--images=*)
		PARALLEL=true
		IMAGE_COUNT="${1#*=}"
		shift
		;;
	--images)
		PARALLEL=true
		if [[ $# -gt 1 ]] && [[ "$2" =~ ^([1-9][0-9]*|auto)$ ]]; then
			IMAGE_COUNT="$2"
			shift 2
		else
			IMAGE_COUNT="auto"
			shift
		fi
		;;
	--openmp=*)
		OPENMP=true
		OPENMP_THREAD_COUNT="${1#*=}"
		shift
		;;
	--openmp)
		OPENMP=true
		if [[ $# -gt 1 ]] && [[ "$2" =~ ^([1-9][0-9]*|auto)$ ]]; then
			OPENMP_THREAD_COUNT="$2"
			shift 2
		else
			OPENMP_THREAD_COUNT="auto"
			shift
		fi
		;;
	--mpi=*)
		MPI=true
		MPI_RANK_COUNT="${1#*=}"
		shift
		;;
	--mpi)
		MPI=true
		if [[ $# -gt 1 ]] && [[ "$2" =~ ^([1-9][0-9]*|auto)$ ]]; then
			MPI_RANK_COUNT="$2"
			shift 2
		else
			MPI_RANK_COUNT="auto"
			shift
		fi
		;;
	-*)
		echo "Unknown option: $1"
		exit 1
		;;
	*)
		if [[ -z "$SRC" ]]; then
			SRC="$1"
		else
			PROGRAM_ARGS+=("$1")
		fi
		shift
		;;
	esac
done

# If help was requested, show the various options we support
if [[ "$SHOW_HELP" == true ]]; then
	echo "Usage: x.sh [options] <input file> [program arguments...]"
	echo "Options:"
	echo "  --help       Show this help menu"
	echo "  --no-debug   Build with optimisations and without debug checks"
	echo "  --no-clean   Prevent deletion of the generated binary"
	echo "  --valgrind   Override defaults and use valgrind for runtime testing (not on macOS)"
	echo "  --thread     Switch memory sanitisation to ThreadSanitizer (catches data races) (not on macOS)"
	echo "  --images [N|auto]  Enable parallel Coarray Fortran; bare --images uses all logical CPUs"
	echo "  --openmp [N|auto]  Enable OpenMP Fortran; bare --openmp uses all logical CPUs"
	echo "  --mpi [N|auto]     Enable MPI Fortran; bare --mpi uses all logical CPUs"
	exit 0
fi

# Ensure we have a source file
if [[ -z "$SRC" ]]; then
	echo "Error: No source file provided."
	echo "Usage: x.sh [options] <input file> [program arguments...]"
	exit 1
fi

OUT="${SRC%.*}"
EXT="${SRC##*.}"
INPUT="${SRC%.*}.in"

if [[ "$PARALLEL" == true ]] && [[ "$EXT" != "f90" ]]; then
	echo "Error: --images is only supported for Coarray Fortran (.f90) programs."
	exit 1
fi

if [[ "$OPENMP" == true ]] && [[ "$EXT" != "f90" ]]; then
	echo "Error: --openmp is only supported for Fortran (.f90) programs."
	exit 1
fi

if [[ "$MPI" == true ]] && [[ "$EXT" != "f90" ]]; then
	echo "Error: --mpi is only supported for Fortran (.f90) programs."
	exit 1
fi

MODE_COUNT=0
[[ "$PARALLEL" == true ]] && ((MODE_COUNT += 1))
[[ "$OPENMP" == true ]] && ((MODE_COUNT += 1))
[[ "$MPI" == true ]] && ((MODE_COUNT += 1))
if ((MODE_COUNT > 1)); then
	echo "Error: --images, --openmp, and --mpi are mutually exclusive."
	exit 1
fi

if [[ "$MPI" == true ]] && { [[ "$RUN_VALGRIND" == true ]] || [[ "$RUN_THREAD_SAN" == true ]]; }; then
	echo "Error: --valgrind and --thread are not supported with MPI."
	exit 1
fi

logical_cpu_count() {
	if [[ "$IS_MACOS" == true ]]; then
		sysctl -n hw.logicalcpu
	else
		getconf _NPROCESSORS_ONLN
	fi
}

configure_coarray_images() {
	if [[ -z "$IMAGE_COUNT" ]] || [[ "$IMAGE_COUNT" == "auto" ]]; then
		IMAGE_COUNT=$(logical_cpu_count)
	fi

	if ! [[ "$IMAGE_COUNT" =~ ^[1-9][0-9]*$ ]]; then
		echo "Error: --images expects a positive integer or 'auto'."
		exit 1
	fi
}

configure_openmp_threads() {
	if [[ -z "$OPENMP_THREAD_COUNT" ]] || [[ "$OPENMP_THREAD_COUNT" == "auto" ]]; then
		OPENMP_THREAD_COUNT=$(logical_cpu_count)
	fi

	if ! [[ "$OPENMP_THREAD_COUNT" =~ ^[1-9][0-9]*$ ]]; then
		echo "Error: --openmp expects a positive integer or 'auto'."
		exit 1
	fi
}

configure_mpi_ranks() {
	if [[ -z "$MPI_RANK_COUNT" ]] || [[ "$MPI_RANK_COUNT" == "auto" ]]; then
		MPI_RANK_COUNT=$(logical_cpu_count)
	fi

	if ! [[ "$MPI_RANK_COUNT" =~ ^[1-9][0-9]*$ ]]; then
		echo "Error: --mpi expects a positive integer or 'auto'."
		exit 1
	fi
}

has_valgrind() {
	command -v valgrind &>/dev/null
}

run_binary() {
	local cmd=()
	local -a program_command=(./"${OUT}" "${PROGRAM_ARGS[@]}")

	# Use valgrind only if explicitly requested
	if [[ "$IS_MACOS" == false ]] && [[ "$DEBUG" == true ]] && [[ "$RUN_VALGRIND" == true ]] && has_valgrind; then
		local suppress=""

		if [[ -f "$HOME/.config/valgrind/rust.supp" ]]; then
			echo "Suppressions file found"
			suppress="--suppressions=$HOME/.config/valgrind/rust.supp"
		fi
		cmd+=(valgrind "$suppress" --leak-check=full --show-leak-kinds=all --track-origins=yes)
	fi

	if [[ "$MPI" == true ]]; then
		program_command=(mpiexec -n "$MPI_RANK_COUNT" ./"${OUT}" "${PROGRAM_ARGS[@]}")
	elif [[ "$OPENMP" == true ]]; then
		program_command=(env "GFORTRAN_NUM_IMAGES=1" "OMP_NUM_THREADS=$OPENMP_THREAD_COUNT" ./"${OUT}" "${PROGRAM_ARGS[@]}")
	# Coarray Fortran needs an explicit single-image default when --images is omitted.
	# Keep the variable scoped to Fortran binaries so other programs are unaffected.
	elif [[ "$EXT" == "f90" ]]; then
		program_command=(env "GFORTRAN_NUM_IMAGES=${IMAGE_COUNT:-1}" ./"${OUT}" "${PROGRAM_ARGS[@]}")
	fi
	cmd+=("${program_command[@]}")

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
		rm -f -- "${OUT}" ./*.smod ./*.mod
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
	if [[ "$IS_MACOS" == true ]] && [[ -z "${MACOSX_DEPLOYMENT_TARGET:-}" ]]; then
		IFS=. read -r MACOS_MAJOR MACOS_MINOR _ <<<"$(sw_vers -productVersion)"
		export MACOSX_DEPLOYMENT_TARGET="${MACOS_MAJOR}.${MACOS_MINOR:-0}"
	fi

	FORTRAN_FLAGS=(-std=f2023 -Wall -Wextra -Wtrampolines -pedantic -march=native)
	FORTRAN_SAN_FLAGS=()
	if [[ "$DEBUG" == true ]]; then
		FORTRAN_FLAGS+=(-g -O0 -fcheck=all -fbacktrace)
	else
		FORTRAN_FLAGS+=(-O2)
	fi

	if [[ "$PARALLEL" == true ]]; then
		if [[ "$RUN_VALGRIND" == true ]] || [[ "$RUN_THREAD_SAN" == true ]]; then
			echo "Error: --valgrind and --thread are not supported with multi-image Coarray Fortran."
			exit 1
		fi
		configure_coarray_images
		if [[ "$DEBUG" == true ]] && [[ "$IS_MACOS" == false ]]; then
			FORTRAN_FLAGS+=(-fsanitize=undefined)
		fi
	elif [[ "$MPI" == true ]]; then
		configure_mpi_ranks
		if ! command -v mpifort &>/dev/null || ! command -v mpiexec &>/dev/null; then
			echo "Error: MPI requires both mpifort and mpiexec."
			exit 1
		fi
		FORTRAN_FLAGS+=(-fcoarray=single)
		if [[ "$DEBUG" == true ]] && [[ "$IS_MACOS" == false ]]; then
			FORTRAN_FLAGS+=(-fsanitize=undefined)
		fi
		if ! env "OMPI_FC=$(command -v gfortran)" mpifort "${SRC}" "${FORTRAN_FLAGS[@]}" -o "${OUT}"; then
			exit 1
		fi
	else
		if [[ "$OPENMP" == true ]]; then
			configure_openmp_threads
			FORTRAN_FLAGS+=(-fopenmp)
		fi
		if [[ "$DEBUG" == true ]] && [[ "$IS_MACOS" == false ]] && [[ "$RUN_VALGRIND" == false ]]; then
			read -r -a FORTRAN_SAN_FLAGS <<<"$SAN_FLAGS"
			FORTRAN_FLAGS+=("${FORTRAN_SAN_FLAGS[@]}")
		fi
	fi

	if [[ "$MPI" == false ]]; then
		# Always use the library-based ABI so coarray programs compile even when
		# they default to one image. Ordinary Fortran programs can use it as well.
		if ! gfortran "${SRC}" "${FORTRAN_FLAGS[@]}" -fcoarray=lib -o "${OUT}" -lcaf_shmem; then
			exit 1
		fi
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

	if [[ -f "${INPUT}" ]]; then
		./"${OUT}" "${PROGRAM_ARGS[@]}" <"${INPUT}"
	else
		./"${OUT}" "${PROGRAM_ARGS[@]}"
	fi

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
		java -cp . "${OUT}" "${PROGRAM_ARGS[@]}" <"${INPUT}"
	else
		java -cp . "${OUT}" "${PROGRAM_ARGS[@]}"
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
		python3 "${SRC}" "${PROGRAM_ARGS[@]}" <"${INPUT}"
	else
		python3 "${SRC}" "${PROGRAM_ARGS[@]}"
	fi
	;;

*)
	echo "Unsupported file type: ${EXT}"
	;;
esac
