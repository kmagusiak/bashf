#!/bin/bash
# TODO's
# - traps
# - verbose flag
# - select multiple options
# - menus
# - parse_args()
# - stack_trace() using $FUNCNAME
# - test script

[ "$BASHF" != "Y" ] || return 0 # already sourced
BASHF=Y
LINE_SEP="-----------------------------------------------------------------------------"
HASH_SEP="$(tr '-' '#')"

# ---------------------------------------------------------
# Logging and output

function log() {
	printf "%6s: %s\n" "$1" "$*" >&2
}
function log_info() {
	log INFO "$@"
}
function log_warn() {
	log WARN "$@"
}
function log_error() {
	log ERROR "$@"
}
function log_cmd() {
	log CMD "$@"
	"$@"
}
function log_var() {
	log VAR "$(printf "%20s: %s" "$1" "${2:-${!1}}")"
}
function log_start() {
	(
		log_section "$SCRIPT_NAME"
		log_var "Directory" "$(pwd)"
		log_var "User" "$CURRENT_USER"
		log_var "Host" "$HOSTNAME $OSTYPE"
		[ $# -eq 0] || log_var "Arguments" "$*"
	) 2>&1 | indentBlock >&2
}
function log_section() {
	echo "****** $*" >&2
	echo "       $(date)" >&2
}

function log_to_file() {
	if has_var TEE_LOG
	then
		log_warn "Already logging (pid: $TEE_LOG)"
		return 1
	fi
	local fifo="$TMP_DIR/.$$_log"
	mkfifo "$fifo" || die "Failed to open fifo for logging"
	tee -ia "$1" < "$fifo" &
	TEE_LOG=$!
	exec &> "$fifo"
	log_info "Logging to file [$1] started..."
}

function indent() {
	sed "s:^:${1-\t}"
}
function indentBlock() {
	echo "$HASH_SEP"
	indent '# '
	echo "$HASH_SEP"
}


color() {
	# $1: color
	# $(2..): text
	# echoes the text with escapes for the color
	local color="${1,,}" cc=
	shift
	[ "${color:0:5}" == "bold-" ] && \
		cc="1;" && color="${color:5}"
	case "$color" in
	bold)
		cc=1;;
	black)
		cc=${cc}30;;
	red)
		cc=${cc}31;;
	green)
		cc=${cc}32;;
	yellow)
		cc=${cc}33;;
	blue)
		cc=${cc}34;;
	magenta)
		cc=${cc}35;;
	cyan)
		cc=${cc}36;;
	white)
		cc=${cc}37;;
	info)
		cc="1;32";;
	warn)
		cc="31";;
	error)
		cc="1;31";;
	*)
		cc=0;;
	esac
	local cs="\033[${cc}m"
	local ce="\033[0m"
	echo "$cs$*$ce"
}

# ---------------------------------------------------------
# Checks

function is_executable() {
	type "$@" &>/dev/null
}
function has_var() {
	declare -p "$1" &>/dev/null
}
function has_val() {
	has_var "$1" && [ -n "${!1}" ]
}
function is_true() {
	case "${!1,,}" in
	y*|t|true|1) return 0;;
	n*|f|false|0) return 1;;
	esac
	return 2
}
function has_env() {
	env | grep "^$1=" &>/dev/null
}

function test_first_match() {
	local arg="$1"
	shift
	local val=
	for val in "$@"
	do
		if test "$arg" "$val"
		then
			echo "$val"
			return
		fi
	done
	return 1
}

function strict() {
	set -eEuo pipefail
	trap "echo \"FATAL: script failed - ${FUNCNAME[*]} ($?)\"" ERR
}
function non_strict() {
	set +eEuo pipefail
	trap "" ERR
}

function die() {
	log_error "$@"
	exit 1
}
function die_usage() {
	log_error "$@"
	usage
	exit 1
}
function die_return() {
	local e="$1"
	shift
	log_error "$@"
	exit "$e"
}

# ---------------------------------------------------------
# Input

SILENT_MODE="${SILENT_MODE:-}"

function is_silent() {
	[ "$SILENT_MODE" == "Y" ]
}

function prompt() {
	local name=""
	local def=""
	local text=""
	local args=""
	while [ $# -gt 0 ]
	do
		case "$1" in
		-d)
			def="$2"
			shift 2;;
		-p)
			text="$text$2"
			shift 2;;
		-v)
			name="$2"
			shift 2;;
		-s)
			args=-s
			shift;;
		*)
			die "prompt(): Invalid parameter [$1]";;
		esac
	done
	[ -n "$name" ] || die "prompt(): No variable name set"
	[ -n "$text" ] || text="Enter $name"
	if is_silent
	then
		[ -n "$def" ] || die "Default value not set for $name"
		log_info "Using default value for $name"
		eval "$name=''"
	else
		[ -z "$def" ] || text="$text [$def]"
		! has_var TEE_LOG || sleep 0.1
		read $args -p "${text}: " "$name"
		! has_var TEE_LOG || echo
	fi
	[ -n "${!name}" ] || eval "$name='$def'"
}

function confirm() {
	local confirmation=""
	while true
	do
		prompt "$@" -v confirmation
		is_true confirmation && confirmation=0 || confirmation=$?
		case "$confirmation" in
		0) return 0;;
		1) return 1;;
		esac
	done
}

function wait_user_input() {
	confirm -p "Proceed..." -d Y
}
function wait_countdown() {
	# $1: number of seconds
	local waiting="${1:-5}"
	shift
	echo -n "$@"
	for waiting in $(seq "$waiting" -1 1)
	do
		echo -n " $waiting"
		sleep 1
	done
	echo
}
function wait_until() {
	# Wait for N seconds or until the command is true
	local timeout=$(( $1 * 2 ))
	shift
	while ! "$@"
	do
		(( $timeout =< 0 )) && return 1
		timeout=$(( $timeout - 1 ))
		sleep 0.5
	done
	return 0
}

# ---------------------------------------------------------
# Global variables and checks

[ "$(basename "$SHELL")" == bash ] || die "You're not using bash \$SHELL"
is_executable realpath || die "realpath is missing"
is_executable usage || die "usage() is not defined"

readonly CURRENT_USER="$(id -un)"
readonly CURRENT_DIR="$(pwd)"
EDITOR="${EDITOR:-vi}"
readonly HOSTNAME="${HOSTNAME:-$(hostname)}"
IFS=$'\n\t'
OSTYPE="${OSTYPE:-$(uname)}"
PAGER="${PAGER:-cat}"
readonly SCRIPT_DIR="$(dirname "$0")"
readonly SCRIPT_NAME="$(basename "$0")"
readonly TIMESTAMP="$(date '%YMD_hms')"
TMP_DIR="${TMP_DIR:-/tmp}"

[ "$SCRIPT_NAME" == "bashf.sh" ] && die "You're running bashf.sh, source it instead."
has_val TRACE || set -x
