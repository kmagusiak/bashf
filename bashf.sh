#!/bin/bash
#
# Script to be sourced in your bash scripts.
# Features: logging, prompting, checking values, utils (argument parsing)
#
# Variables:
# - BATCH_MODE (bool) - sets non-interactive mode
# - COLOR_MODE (bool) - see color_enable() / color_disable()
# - TRACE (bool) - when sourced, enables -x option
# - VERBOSE_MODE (bool) - sets verbosity
#
# You can either define usage() for your script or one will get defined by
# reading the header of your script.
#
# Strict mode is enabled by default.
# In this mode, script stops on error, undefined variable or pipeline fails.
#

[ -z "$BASHF" ] || return 0 # already sourced
readonly BASHF="$(dirname "$BASH_SOURCE")"

# ---------------------------------------------------------
# Logging and output

LINE_SEP="$(seq -s '-' 78 | tr -d '[:digit:]')"
HASH_SEP="$(tr '-' '#' <<< "$LINE_SEP")"
VERBOSE_MODE="${VERBOSE_MODE:-N}"

function _log() {
	# $1: marker
	# $2..: text
	local IFS=$' ' mark="$1"
	shift
	printf '%-6s: %s\n' "$mark" "$*" >&2
}
function log_debug() {
	[ "$VERBOSE_MODE" == Y ] || return 0
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
	_log CMD "$@"
	"$@"
}
function log_status() {
	local msg=$1
	shift
	while [ $# -gt 0 ]
	do
		case "$1" in
		--)
			shift
			break;;
		*)
			msg="$msg $1"
			shift;;
		esac
	done
	log_debug "Running $1"
	if "$@"
	then
		log_info "$msg" '[done]'
	else
		log_error "$msg" '[fail]'
	fi
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

function color_enable() {
	COLOR_MODE=Y
	COLOR_RESET=$'\e[0m'
	COLOR_BLACK=$'\e[30m'
	COLOR_RED=$'\e[31m'
	COLOR_GREEN=$'\e[32m'
	COLOR_YELLOW=$'\e[33m'
	COLOR_BLUE=$'\e[34m'
	COLOR_MAGENTA=$'\e[35m'
	COLOR_CYAN=$'\e[36m'
	COLOR_GRAY=$'\e[37m'
	COLOR_DEFAULT=$'\e[39m'
	COLOR_BOLD=$'\e[1m'
	COLOR_DIM=$'\e[2m'
	COLOR_UNDERLINE=$'\e[4m'
	COLOR_REVERSE=$'\e[7m'
}
function color_disable() {
	COLOR_MODE=N
	COLOR_RESET=''
	COLOR_BLACK=''
	COLOR_RED=''
	COLOR_GREEN=''
	COLOR_YELLOW=''
	COLOR_BLUE=''
	COLOR_MAGENTA=''
	COLOR_CYAN=''
	COLOR_GRAY=''
	COLOR_DEFAULT=''
	COLOR_BOLD=''
	COLOR_DIM=''
	COLOR_UNDERLINE=''
	COLOR_REVERSE=''
}
color_enable

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

function prompt() {
	# -v variable_name
	# -p text_prompt (optional)
	# -d default_value (optional)
	# -s: silent mode - don't output what's typed
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
	if [ "$BATCH_MODE" != N ]
	then
		[ -n "$def" ] || die "Default value not set for $name"
		log_debug "Use default value:"
		log_var "$name" "$def"
		eval "$name=\$def"
		return
	fi
	# Read from input
	[ -n "$text" ] || text="Enter $name"
	[ -z "$def" ] || text="$text [$def]"
	! has_var TEE_LOG || sleep 0.1
	read -r $args -p "${text}: " "$name"
	! has_var TEE_LOG || echo
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
	if [ "$BATCH_MODE" != N ]
	then
		[ -n "$def" ] || die "Default value not set for $name"
		log_debug "Use default value:"
		log_var "$name" "$def"
		eval "$name=\$def"
		return
	fi
	# Select
	[ -n "$text" ] || text="Select $name:"
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
		echo "#  Invalid choice" >&2
	done
}

function menu_loop() {
	# -p prompt text (optional)
	# -- menu entries (format: 'function: text')
	local prompt=Menu
	while true
	do
		case "$1" in
		-p)
			prompt="$2"
			shift 2;;
		--)
			shift
			break;;
		-*)
			die "menu_loop: Invalid option [$1]";;
		*)
			break;;
		esac
	done
	local mvalue=() mtext=()
	local item
	for item
	do
		mtext+=("${item#*:}")
		item="${item%%:*}"
		mvalue+=("${item// /$'\n'}")
	done
	if [ "$BATCH_MODE" != N ]
	then
		log_info "${prompt:-Menu}"
		for ((item=0 ; item < ${#mvalue[@]}; item++))
		do
			log_info "Execute: ${mtext[$item]}"
			${mvalue[$item]}
		done
		return
	fi
	# Menu
	local reply
	while true
	do
		prompt_choice -v reply -p "$prompt" -- "${mtext[@]}" || break
		item=$(arg_index "$reply" "${mtext[@]}")
		${mvalue[$item]}
	done
}

function wait_user_input() {
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

# ---------------------------------------------------------
# Various

function parse_args() {
	# Usage: parse_args [ opts ] func "$@"
	# opts:
	#   -a  Try parsing arguments after '--' (implies -f)
	#       (default: stop parsing)
	#   -f  Parse options other than '-*'
	#   -n  Requires at least one argument
	#   -v var  Set var to the remaining options
	# func: function to parse an argument
	#       return code is the number of parsed parameters
	local func='' all='' req=0 fvar='' fopt=''
	while [ $# -gt 0 ]
	do
		case "$1" in
		-a)
			all=Y
			fopt=Y
			shift;;
		-f)
			fopt=Y
			shift;;
		-n)
			req=1
			shift;;
		-v)
			fvar="$2"
			shift 2;;
		*)
			func="$1"
			shift
			break;;
		esac
	done
	is_executable "$func" || die "Pass a function for parse_args()"
	while [ $# -gt 0 ]
	do
		case "$1" in
		--batch-mode)
			BATCH_MODE=Y
			shift;;
		--no-color)
			color_disable
			shift;;
		--help|-h|-\?)
			usage
			exit;;
		--trace)
			set -x
			shift;;
		--verbose)
			VERBOSE_MODE=Y
			shift;;
		--)
			# Finish parsing
			shift
			[ -n "$all" ] || break
			while [ $# -gt 0 ]
			do
				if "$func" "$@"
				then
					die_usage "Unhandled arguments after '--' [$1]"
				else
					shift $?
					req=0
				fi
			done;;
		*)
			# Parse using the given function
			if [ "${1:0:1}" != '-' ]
			then
				[ -n "$fopt" ] || break
				req=0
			fi
			if "$func" "$@"
			then
				die_usage "Unknown argument [$1]"
			else
				shift $?
			fi;;
		esac
	done
	# Check required
	[[ "$req" -eq 0 || $# -gt 0 ]] || die_usage "Missing arguments!"
	# Set remaining options
	if [ -n "$fvar" ]
	then
		eval "$fvar=(\"\$@\")"
	elif [ $# -gt 0 ]
	then
		local IFS=$' '
		die "Unparsed arguments: $*"
	fi
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

case "$SCRIPT_NAME" in
bashf.sh)
	die "You're running bashf.sh, source it instead.";;
bash)
	log_warn "Sourcing from console?";;
esac

# Default usage definition
if ! is_executable usage
then
	function usage() {
		echo "Usage: $SCRIPT_NAME [ args ]"
		local line
		while read line
		do
			[[ "${line:0:1}" == '#' ]] || break
			[[ "${line:1:1}" != '!' ]] || continue
			echo "${line:2}"
		done < "$SCRIPT_DIR/$SCRIPT_NAME"
	}
fi

is_true TRACE && set -x || true
strict
