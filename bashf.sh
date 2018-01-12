#!/bin/bash
#
# Script to be sourced in your bash scripts.
# Features: logging, prompting, checking values
#
# Variables:
# - TRACE (bool) - when sourced, enables -x option
# - COLOR_MODE (bool) - enables/disables color
# - VERBOSE_MODE (bool) - sets verbository
# - BATCH_MODE (bool) - sets non-interactive mode
#
# TODO's
# - parse_args()
# - default usage()?
# - main()

[ -z "$BASHF" ] || return 0 # already sourced
BASHF="$(dirname "$BASH_SOURCE")"

# ---------------------------------------------------------
# Logging and output

LINE_SEP="$(seq -s '-' 78 | tr -d '[:digit:]')"
HASH_SEP="$(tr '-' '#' <<< "$LINE_SEP")"
COLOR_MODE="${COLOR_MODE:-Y}"
COLOR_RESET="$(tput sgr0)"
VERBOSE_MODE="${VERBOSE_MODE:-N}"

function is_verbose() {
	[ "$VERBOSE_MODE" == Y ]
}
function _log() {
	# $1: marker
	# $2..: text
	local IFS=$' ' mark="$1"
	shift
	printf '%-6s: %s\n' "$mark" "$*" >&2
}
function log_debug() {
	is_verbose || return 0
	_log DEBUG "$@"
}
function log_info() {
	_log INFO "$@"
}
function log_warn() {
	_log WARN "$@"
}
function log_error() {
	_log ERROR "$@"
}
function log_cmd() {
	local IFS=$' '
	_log CMD "$@"
	"$@"
}
function log_var() {
	# $1: variable name
	# $2: value (optional, default: variable is read)
	_log VAR "$(printf "%-20s: %s" "$1" "${2:-${!1}}")"
}
function log_start() {
	# $@: pass arguments
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
	local IFS=$' '
	echo "******  $*" >&2
	echo "        $(date '+%F %T')" >&2
}

function log_redirect_to() {
	# $1: file to log to
	# call this function only once
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
	trap_add "sleep 0.2; rm -f \"$fifo\""
}

function indent() {
	# $1: prefix
	sed -u "s:^:${1:-\t}:"
}
function indent_block() {
	echo "$HASH_SEP"
	indent '# ' | trim
	echo "$HASH_SEP"
}
function indent_date() {
	# $1: date format (optional)
	local format="${1:-%T}" line=
	while read -r line
	do
		echo "$(date "+$format"): $line"
	done
	return 0
}
function trim() {
	sed -u 's/\s+$//'
}

function color() {
	# $1: color
	# $2: if set, read from stdin (default Y)
	# outputs the terminal code for the solor
	local color="${1,,}" cc=
	if [ "$COLOR_MODE" == N ]
	then
		[ $# -gt 1 ] && cat || true
		return
	fi
	[ "${color:0:5}" == "bold-" ] && \
		cc="$(tput bold)" && color="${color:5}"
	case "${color:-reset}" in
	bold)
		cc="$(tput bold)";;
	black)
		cc="$cc$(tput setaf 0)";;
	red)
		cc="$cc$(tput setaf 1)";;
	green)
		cc="$cc$(tput setaf 2)";;
	yellow)
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
		cc="$COLOR_RESET";;
	esac
	echo -n "$cc"
	if [ $# -gt 1 ]
	then
		cat
		echo -n "$COLOR_RESET"
	fi
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

function arg_index() {
	# $1: argument
	# $2..: list to check against
	# prints the index to stdout
	local opt="$1" local index=0
	shift
	while [ $# -gt 0 ]
	do
		[[ "$opt" == "$1" ]] && echo $index && return 0 || true
		index=$(( index + 1 ))
		shift
	done
	return 1
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
	set -euo pipefail
}
function non_strict() {
	set +euo pipefail
}
function stacktrace() {
	# $1: mode (full or short) (default: full)
	# $2: number of frames to skip (default: 1)
	# prints stacktrace to stdout
	local mode="${1:-full}" skip="${2:-1}"
	local i=
	for (( i=skip; i<${#FUNCNAME[@]}; i++))
	do
		local name="${FUNCNAME[$i]:-??}" line="${BASH_LINENO[$i-1]}"
		case "$mode" in
		short)
			echo -n " > $name:$line"
			;;
		*)
			echo "  at: $name (${BASH_SOURCE[$i]:-(unknown)}:$line)"
			;;
		esac
	done
}
function _on_exit_callback() {
	# $@: $PIPESTATUS
	# called by default in bashf on exit
	# log FATAL error if command failed in strict mode
	local ret=$? cmd="$BASH_COMMAND" pipestatus=("$@")
	[[ "$cmd" == exit* ]] && cmd="" || true
	if [[ $- == *e* ]] && [ $ret -ne 0 ] && [ -n "$cmd" ]
	then
		[[ "$cmd" == return* ]] && cmd="" || true
		local msg="${cmd:-Command} failed"
		if [ ${#pipestatus[@]} -gt 1 ]
		then
			msg+=" (pipe: ${pipestatus[@]})"
		else
			msg+=" ($ret)"
		fi
		msg+="$(stacktrace short 2)"
		_log FATAL "$msg"
	fi
}
function trap_add() {
	# $*: command to run on exit
	local handle="$(trap -p EXIT \
		| sed "s:^trap -- '::" \
		| sed "s:' EXIT\$::")"
	local IFS=$' '
	trap "$*; $handle" EXIT
}
trap_add '_on_exit_callback "${PIPESTATUS[@]}"'

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
	# $1: exit code
	# $2..: message
	local e="$1"
	shift
	log_error "$@"
	exit "$e"
}

# ---------------------------------------------------------
# Input

BATCH_MODE="${BATCH_MODE:-N}"
# TODO wait mode (like batch, but show value and sleep)

function is_batch() {
	[ "$BATCH_MODE" != N ]
}

function prompt() {
	# -v variable_name
	# -p text_prompt (optional)
	# -d default_value (optional)
	# -s: silent mode
	local name='' def='' text='' args=''
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
		read -r $args -p "${text}: " "$name"
		! has_var TEE_LOG || echo
	fi
	[ -n "${!name}" ] || eval "$name=\$def"
}

function confirm() {
	# uses prompt to confirm
	local confirmation=''
	local args=(-v confirmation)
	if arg_index -p "$@" >/dev/null
	then
		args+=(-p "(y/n)")
	else
		args+=(-p "Confirm (y/n)")
	fi
	while true
	do
		prompt "$@" "${args[@]}"
		is_true confirmation && confirmation=0 || confirmation=$?
		case "$confirmation" in
		0) return 0;;
		1) return 1;;
		esac
	done
}

function prompt_choice() {
	# -v variable_name
	# -p prompt_text (optional)
	# -d default_value (optional)
	# -- menu choices
	local name='' def='' text=''
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
		--)
			shift
			break;;
		*)
			die "prompt(): Invalid parameter [$1]";;
		esac
	done
	[ -n "$name" ] || die "prompt(): No variable name set"
	[ -n "$text" ] || text="Select $name:"
	if is_batch
	then
		[ -n "$def" ] || die "Default value not set for $name"
		log_info "Using default value for $name"
		eval "$name=\$def"
	else
		[ -z "$def" ] || text="$text [$def]"
		! has_var TEE_LOG || sleep 0.1
		local choice=
		echo "$text"
		select choice in "$@"
		do
			if arg_index "$choice" "$@" >/dev/null
			then
				eval "$name=\$choice"
				return
			elif [ -n "$def" ]
			then
				eval "$name=\$def"
				return
			fi
			echo "#  Invalid choice"
			echo "$text"
		done
	fi
}

function wait_user_input() {
	# confirm proceed (default: Y)
	confirm -p "Proceed..." -d Y
}
function wait_countdown() {
	# $1: number of seconds (default: 5)
	local waiting="${1:-5}"
	shift
	echo -n "$@"
	for (( ; waiting>0; waiting--))
	do
		echo -n " $waiting"
		sleep 1
	done
	echo
}
function wait_until() {
	# $1: number of seconds
	# $2..: command
	# wait for N seconds or until the command is true
	local timeout=$(( $1 * 2 ))
	shift
	while ! "$@"
	do
		[ "$timeout" -gt 0 ] || return 1
		timeout=$(( timeout - 1 ))
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
