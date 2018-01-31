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
HASH_SEP=${LINE_SEP//-/#}
VERBOSE_MODE=${VERBOSE_MODE:-N}

function _log() {
	# $1: marker
	# $2..: text
	local IFS=$' ' mark=$1 color=$2
	shift 2
	printf '%s%-6s%s: %s\n' "$color" "$mark" "$COLOR_RESET" "$*" >&2
}
function log_debug() {
	[ "$VERBOSE_MODE" == Y ] || return 0
	_log DEBUG "${COLOR_DIM}" "$@"
}
function log_info() {
	_log INFO "${COLOR_GREEN}" "$@"
}
function log_warn() {
	_log WARN "${COLOR_YELLOW}" "$@"
}
function log_error() {
	_log ERROR "${COLOR_RED}" "$@"
}
function log_cmd() {
	_log CMD "${COLOR_BLUE}" "$@"
	"$@"
}
function log_cmd_debug() {
	if [ "$VERBOSE_MODE" == Y ]
	then
		log_cmd "$@"
	else
		"$@"
	fi
}
function log_status() {
	local msg=''
	while [ $# -gt 0 ]
	do
		case "$1" in
		--)
			shift
			break;;
		*)
			msg="${msg:+$msg }$1"
			shift;;
		esac
	done
	printf "${COLOR_BLUE}RUN   ${COLOR_RESET}: ${msg:-$1}... " >&2
	if "$@"
	then
		echo "[${COLOR_GREEN}done${COLOR_RESET}]" >&2
	else
		echo "[${COLOR_RED}fail${COLOR_RESET}]" >&2
	fi
}
function log_var() {
	# $1: variable name
	# $2: value (optional, default: variable is read)
	_log VAR "${COLOR_CYAN}" "$(printf "%-20s: %s" "$1" "${2:-${!1}}")"
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
	echo "${COLOR_BOLD}******  ${COLOR_UNDERLINE}$*${COLOR_RESET}" >&2
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
function is_integer() {
	[[ "$1" =~ ^[0-9]+$ ]]
}
function is_number() {
	[[ "$1" =~ ^-?[0-9]+(\.[0-9]*)?$ ]]
}
function has_env() {
	env | grep "^$1=" &>/dev/null
}

function arg_index() {
	# $1: argument
	# $2..: list to check against
	# prints the index to stdout
	local opt="$1" index=0
	shift
	while [ $# -gt 0 ]
	do
		[[ "$opt" == "$1" ]] && echo $index && return 0 || true
		(( index++ ))
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
		_log FATAL "${COLOR_BOLD}${COLOR_RED}" "$msg"
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

if ! [[ ${BATCH_MODE:+x} == x ]]
then
	[[ -t 0 || -p /dev/stdin ]] && BATCH_MODE=N || BATCH_MODE=Y
fi

function prompt() {
	# $1: variable_name
	# $2: text_prompt (optional)
	# $3: default_value (optional)
	# $4..: "-n" for non-empty (optional)
	# Rest are arguments passed to `read` (-s for silent)
	local _name=$1 _text='' _def='' _req=0
	shift
	if [ $# -gt 0 ] && [ "${1:0:1}" != '-' ]
	then
		_text=$1
		shift
	fi
	if [ $# -gt 0 ] && [ "${1:0:1}" != '-' ]
	then
		_def=$1
		shift
	fi
	if [ $# -gt 0 ] && [ "$1" == '-n' ]
	then
		_req=1
		shift
	fi
	[ -n "$_name" ] || die "prompt(): No variable name set"
	if [ "$BATCH_MODE" != N ]
	then
		[ -n "$_def" ] || die "Default value not set for $_name"
		log_debug "Use default value:"
		log_var "$_name" "$_def"
		eval "$_name=\$_def"
		return
	fi
	# Read from input
	[ -n "$_text" ] || _text="Enter $_name"
	[ -z "$_def" ] || _text+=" ${COLOR_DIM}[$_def]${COLOR_RESET}"
	while true
	do
		! has_var TEE_LOG || sleep 0.1
		if read "$@" -r -p "${_text}: " "$_name"
		then
			! (has_var TEE_LOG || arg_index -s "$@" >/dev/null) \
				|| echo >&2
		else
			case $? in
			1|142) # EOF | timeout
				;;
			*)
				die "Failed to read input! ($?)";;
			esac
		fi
		[ -n "${!_name}" ] || eval "$_name=\$_def"
		[ "$_req" -gt 0 ] && [ -z "${!_name}" ] || break
	done
}

function confirm() {
	# $1: text_prompt (optional)
	# $2: default_value (optional, Y/N)
	# Rest passed to `prompt`
	local confirmation='' _text='' _def=''
	if [ $# -gt 0 ] && [ "${1:0:1}" != '-' ]
	then
		_text=$1
		shift
	else
		_text='Confirm'
	fi
	_text==' (y/n)'
	case "${1:-}" in
	y|Y|n|N)
		_def="${1^^}"
		shift;;
	esac
	while true
	do
		prompt confirmation "$_text" "$_def" "$@"
		is_true confirmation && confirmation=0 || confirmation=$?
		case "$confirmation" in
		0) return 0;;
		1) return 1;;
		esac
	done
}

function prompt_choice() {
	# $1: variable_name
	# $2: prompt_text (optional)
	# $3: default_value (optional)
	# --: menu choices (format 'value|text')
	local _name=$1 _text='' _def=''
	shift
	[ "$1" == '--' ] || { _text=$1 && shift; }
	[ "$1" == '--' ] || { _def=$1 && shift; }
	[ "$1" == '--' ] && shift
	[ -n "$_name" ] || die "prompt(): No variable name set"
	[ -n "$_text" ] || _text="Select $_name"
	if [ "$BATCH_MODE" != N ]
	then
		prompt "$_name" "$_text" "$_def"
		return
	fi
	local _mvalue=() _mtext=() _item _i
	for _item
	do
		_mvalue+=("${_item%%|*}")
		_mtext+=("$(echo "${_item#*|}" | xargs)")
	done
	# Select
	[ -z "$_def" ] || _def=$(( $(arg_index "$_def" "${_mvalue[@]}") + 1 ))
	! has_var TEE_LOG || sleep 0.1
	echo "$_text" >&2
	_i=0
	for _item in "${_mtext[@]}"
	do
		(( _i+=1 ))
		printf " %2d) %s\n" "$_i" "$_item"
	done
	while true
	do
		prompt _item 'Choice' "$_def"
		if is_integer "$_item" && (( 0 < _item && _item <= ${#_mvalue[@]} ))
		then
			_item=${_mvalue[$_item-1]}
			break
		else
			log_warn 'Invalid choice'
		fi
	done
	eval "$_name=\$_item"
}

function menu_loop() {
	# $1: prompt_text (optional)
	# -- menu entries (format: 'function|text')
	local _text=Menu _item IFS=' '
	[ "$1" == '--' ] || { _text=$1 && shift; }
	[ "$1" == '--' ] && shift
	if [ "$BATCH_MODE" != N ]
	then
		log_info "${_text}"
		for _item
		do
			_item="${_item%%|*}"
			log_cmd $_item
		done
		return
	fi
	# Menu
	local REPLY
	while true
	do
		prompt_choice REPLY "${COLOR_BOLD}$_text${COLOR_RESET}" -- "$@" || break
		log_cmd_debug $REPLY
	done
}

function wait_user_input() {
	confirm "Proceed..." Y
}

# ---------------------------------------------------------
# Various

declare -A ARG_PARSER_CMD ARG_PARSER_SHORT ARG_PARSER_USAGE
declare -a ARG_PARSER_REST
#TODO -a in arg_parser_opt adds to existing array
#TODO define variable only if not yet defined
#TODO test code? [ -f $var ] when parsing?
#TODO quit on first named argument
#TODO require at least one arg
#TODO handle arg_parser_rest a b -- cs
function arg_parse_opt() {
	# $1: long option name
	# $2: description
	# $3..:
	#   -s char: short option character
	#   -v variable: variable to set
	#   -V: variable to set, same as name
	#   -r: read next arg
	#   -a num: read argument array (max num)
	#   ...: command to run
	local _name=$1 _desc=$2 _short _var _cmd
	shift 2
	[ -z "$_desc" ] || ARG_PARSER_USAGE[$_name]=$_desc
	while [ $# -gt 0 ]
	do
		case "$1" in
		-s)
			ARG_PARSER_SHORT[${2:0:1}]=$_name
			shift 2;;
		-v|-V)
			if [ "$1" == '-v' ]
			then
				_var=$2
				shift 2
			else
				_var=$_name
				shift
			fi
			_cmd="$_var=Y"
			eval "$_var=";;
		-r)
			_cmd="{ $_var=\$1; shift; }"
			shift;;
		-a)
			_cmd="{ local _max=$2; while [ \$# -gt 0] && [ \$_max -gt 0 ]; do "\
				"$_var+=(\$1); shift; (( _max-- )); done; }"
			shift 2;;
		-*)
			die "arg_parse_opt() unknown option [$1]";;
		*)
			_cmd=$1
			shift;;
		esac
	done
	[ -n "$_cmd" ] || die "No command for $_name"
	ARG_PARSER_CMD[$_name]=$_cmd
}
function arg_parse_reset() {
	ARG_PARSER_CMD=()
	ARG_PARSER_SHORT=()
	ARG_PARSER_USAGE=()
	ARG_PARSER_REST=()
	[ "${1:-}" == 'default' ] || return 0
	arg_parse_opt help 'Show help' -s h -s '?' '{ usage; exit; }'
	arg_parse_opt batch-mode '' 'BATCH_MODE=Y'
	arg_parse_opt verbose 'Show debug messages' 'VERBOSE_MODE=Y'
	arg_parse_opt no-color '' color_disable
	arg_parse_opt trace '' 'set -x'
	arg_parse_opt quiet '' '{ exec 2>/dev/null; VERBOSE_MODE=N; }'
}
arg_parse_reset default
function arg_parse_rest() {
	ARG_PARSER_REST=("$@")
	local var
	for var
	do
		[ "${var:0:1}" != '-' ] || continue
		eval "$var=()"
	done
	return 0
}

function arg_parse() {
	local _rest=() _arg _cmd
	# Parse arguments (long and short)
	while [ $# -gt 0 ]
	do
		_arg=$1 _cmd=''
		shift
		if [ "$_arg" == '--' ]
		then
			# End options
			break
		elif [ "${_arg:0:2}" == '--' ]
		then
			# Long option
			_cmd=${ARG_PARSER_CMD[${_arg:2}]:-}
		elif [ "${_arg:0:1}" == '-' ] && [ ${#_arg} -gt 1 ]
		then
			# Short option
			_arg=${_arg:1:1}
			_arg=${ARG_PARSER_SHORT[{$_arg}]:-$_arg}
			_cmd=${ARG_PARSER_CMD[${_arg}]:-}
			_arg="-$_arg" # for error messages
		else
			# Add to rest
			_rest+=("$_arg")
			continue
		fi
		[ -n "$_cmd" ] || die_usage "Unknown option [$_arg]"
		eval "$_cmd" || die "Failed to parse option [$_arg]" "$@"
	done
	# Set the rest
	[ "${_rest:+x}" == x ] \
		&& set -- "${_rest[@]}" -- "$@" \
		|| set -- -- "$@"
	# Check no arguments
	if [ "${ARG_PARSER_REST:+x}" != x ]
	then
		# No rest
		[ $# -gt 1 ] || return 0
		die_usage "$SCRIPT_NAME doesn't accept positional arguments (got $(( $# - 1 )))"
	fi
	# Parse the rest of arguments
	local _sep=$(arg_index '--' "$@") \
		_idx=$(arg_index '--' "${ARG_PARSER_REST[@]}" || true)
	case "$_idx" in
	""|1)
		eval "${ARG_PARSER_REST[0]}=(\"\${@:1:$_sep}\")"
		shift $_sep;;
	0)
		[ "$_sep" -eq 0 ] || die "Unexpected argument [$1]";;
	*) die "Unsupported position of '--' in arg_parse_rest";;
	esac
	# Check unparsed arguments
	shift # --
	if [ -n "$_idx" ]
	then
		eval "${ARG_PARSER_REST[$_idx+1]}=(\"\$@\")"
	elif [ $# -gt 0 ]
	then
		die_usage "Unexpected unparsed argument [$1]"
	fi
}

function usage_parse_args() {
	# options:
	#   -U: print default usage line
	#   -u opts: print usage line
	#   -t text: print text
	#   -: print from stdin
	local IFS=' ' arg usage=0
	while [ $# -gt 0 ]
	do
		case "$1" in
		-U)
			printf "Usage: $SCRIPT_NAME [ options ]"
			[ -n "${ARG_PARSER_REST:-}" ] \
				&& echo '' "${ARG_PARSER_REST[*]}" \
				|| echo
			(( usage+=1 ))
			shift;;
		-u)
			[ "$usage" -gt 0 ] \
				&& echo -n "      " \
				|| echo -n "Usage:"
			echo " $SCRIPT_NAME" "$2"
			shift 2;;
		-t)
			echo "$2"
			shift 2;;
		-)
			cat -
			echo
			shift;;
		*)
			die "usage_parse_args(): unknown option [$1]";;
		esac
	done
	# Parse argument list
	for arg in "${!ARG_PARSER_USAGE[@]}"
	do
		local args="--$arg" a
		for a in "${!ARG_PARSER_SHORT[@]}"
		do
			[ "${ARG_PARSER_SHORT[$a]}" != "$arg" ] || \
				args+="|-$a"
		done
		printf "  %-18s %s\n" "$args" "${ARG_PARSER_USAGE[$arg]}"
	done | sort
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

[ "$(basename "$BASH")" == bash ] || die "You're not using bash"
is_executable realpath || die "realpath is missing"

readonly CURRENT_USER=$USER
readonly CURRENT_DIR=$PWD
readonly HOSTNAME=${HOSTNAME:-$(hostname)}
IFS=$'\n\t'
OSTYPE=${OSTYPE:-$(uname)}
readonly SCRIPT_DIR="$(realpath "$(dirname "$0")")"
readonly SCRIPT_NAME="$(basename "$0")"
readonly TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
TMP_DIR=${TMP_DIR:-/tmp}

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
		local line
		while read line
		do
			[[ "${line:0:1}" == '#' ]] || break
			[[ "${line:1:1}" != '!' ]] || continue
			echo "${line:2}"
		done < "$SCRIPT_DIR/$SCRIPT_NAME" \
			| usage_parse_args -U - >&2
	}
fi

is_true TRACE && set -x || true
strict
