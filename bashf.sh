#!/bin/bash
#
# Script to be sourced in your bash scripts.
# Features: logging, prompting, checking values
#
# Variables:
# - BASHF (bool) - set when sourced
# - TRACE (bool) - when sourced, enables -x option
# - COLOR_MODE (bool) - enables/disables color
# - VERBOSE_MODE (bool) - sets verbository
# - BATCH_MODE (bool) - sets non-interactive mode
# - EXIT_HANDLES (array) - commands executed on exit
# - TEE_LOG (pid) - logging process ID (if any)
#
# TODO's
# - select multiple options
# - menus
# - parse_args()

[ "$BASHF" != "Y" ] || return 0 # already sourced
BASHF=Y

# ---------------------------------------------------------
# Logging and output

LINE_SEP="$(seq -s '-' 78 | tr -d '[:digit:]')"
HASH_SEP="$(tr '-' '#' <<< "$LINE_SEP")"
COLOR_MODE=Y
COLOR_RESET="$(tput sgr0)"
VERBOSE_MODE=N

function is_verbose() {
	[ "$VERBOSE_MODE" == "Y" ]
}
function _log() {
	printf '%-6s: %s\n' "$@" >&2
}
function log_debug() {
	is_verbose || return 0
	_log DEBUG "$*"
}
function log_info() {
	_log INFO "$*"
}
function log_warn() {
	_log WARN "$*"
}
function log_error() {
	_log ERROR "$*"
}
function log_cmd() {
	local IFS=$' '
	_log CMD "$*"
	"$@"
}
function log_var() {
	_log VAR "$(printf "%-20s: %s" "$1" "${2:-${!1}}")"
}
function log_start() {
	local IFS=$' '
	(
		log_section "$SCRIPT_NAME"
		log_var "Directory" "$(pwd)"
		log_var "User" "$CURRENT_USER"
		log_var "Host" "$HOSTNAME [$OSTYPE]"
		[ -z "$*" ] || log_var "Arguments" "$* "
	) 2>&1 | indent_block >&2
}
function log_section() {
	echo "******  $*" >&2
	echo "        $(date)" >&2
}

function log_redirect_to() {
	if has_var TEE_LOG
	then
		log_warn "Already logging (pid: $TEE_LOG)"
		return 1
	fi
	local fifo="$TMP_DIR/.$$_fifolog"
	mkfifo "$fifo" || die "Failed to open fifo for logging"
	tee -ia "$1" < "$fifo" &
	TEE_LOG=$!
	exec &> "$fifo"
	log_info "Logging to file [$1] started..."
	EXIT_HANDLES+=("sleep 0.2" "rm -f $fifo")
}

function indent() {
	sed "s:^:${1:-\t}:"
}
function indent_block() {
	echo "$HASH_SEP"
	indent '# '
	echo "$HASH_SEP"
}

function color() {
	# $1: color
	# $(2..): text (optional)
	# echoes the text with escapes for the color
	# if no text is given, uses stdin
	local IFS=$' '
	local color="${1,,}" cc=
	shift
	if [ "$COLOR_MODE" == "N" ]
	then
		[ $# -gt 0 ] && echo "$*" || cat
		return
	fi
	[ "${color:0:5}" == "bold-" ] && \
		cc="$(tput bold)" && color="${color:5}"
	case "${color:-reset}" in
	bold)
		cc="$(tput bold)";;
	black)
		cc="$cc$(tput setaf 0)";;
	red|error)
		cc="$cc$(tput setaf 1)";;
	green|info)
		cc="$cc$(tput setaf 2)";;
	yellow|warn)
		cc="$cc$(tput setaf 3)";;
	blue)
		cc="$cc$(tput setaf 4)";;
	magenta)
		cc="$cc$(tput setaf 5)";;
	cyan)
		cc="$cc$(tput setaf 6)";;
	white)
		cc="$cc$(tput setaf 7)";;
	*)
		;;
	esac
	if [ $# -gt 0 ]
	then
		echo "$cc$*$COLOR_RESET"
	else
		echo -n "$cc"
		cat
		echo -n "$COLOR_RESET"
	fi
}

# ---------------------------------------------------------
# Checks

EXIT_HANDLES=()

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
}
function non_strict() {
	set +eEuo pipefail
}
function stacktrace() {
	local skip="${1:-1}"
	local f=
	for f in $(seq "$skip" "${#FUNCNAME[@]}")
	do
		echo -n " > ${FUNCNAME[$f-1]}"
	done
}
function _on_exit_callback() {
	local ret=$? cmd="$BASH_COMMAND"
	[[ "$cmd" == exit* ]] && cmd="" || true
	if [[ $- == *e* ]] && [ $ret -ne 0 ] && [ -n "$cmd" ]
	then
		_log FATAL "${cmd:-Command} failed ($ret)$(stacktrace 3)"
	fi
	local IFS=$' ' h=
	set +e
	for h in "${EXIT_HANDLES[@]:-}"
	do
		$h
	done
}
trap '_on_exit_callback' EXIT

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

BATCH_MODE="${BATCH_MODE:-N}"

function is_batch() {
	[ "$BATCH_MODE" == "Y" ]
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
	if is_batch
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

readonly CURRENT_USER="$(id -un)"
readonly CURRENT_DIR="$(pwd)"
EDITOR="${EDITOR:-vi}"
readonly HOSTNAME="${HOSTNAME:-$(hostname)}"
IFS=$'\n\t'
OSTYPE="${OSTYPE:-$(uname)}"
PAGER="${PAGER:-cat}"
readonly SCRIPT_DIR="$(realpath "$(dirname "$0")")"
readonly SCRIPT_NAME="$(basename "$0")"
readonly TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
TMP_DIR="${TMP_DIR:-/tmp}"

[ "$SCRIPT_NAME" == "bashf.sh" ] && die "You're running bashf.sh, source it instead."
is_executable usage || die "usage() is not defined"
is_true TRACE && set -x || true
strict
