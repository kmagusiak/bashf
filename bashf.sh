#!/bin/bash
#
# Script to be sourced in your bash scripts.
# When executed, shows the function list.
# Features: logging, prompting, checking values, utils (argument parsing)
#
# Variables:
# - BATCH_MODE (bool) - sets non-interactive mode
# - COLOR_MODE (bool) - see color_enable() / color_disable()
# - VERBOSE_MODE (int) - sets verbosity
# - OUTPUT_REDIRECT (optional) - set by log_redirect_to
#
# You can either define usage() for your script or one will get defined by
# reading the header of your script.
#
# Strict mode is enabled by default.
# In this mode, script stops on error, undefined variable or pipeline fails.
#

[ -z "${BASHF:-}" ] || return 0 # already sourced
readonly BASHF="$(dirname "$BASH_SOURCE")"

# ---------------------------------------------------------
# Logging and output

_log() {
	# usage: marker color text...
	local IFS=$' ' mark=$1 color=$2
	shift 2
	printf '%s%-6s%s: %s\n' "$color" "$mark" "$COLOR_RESET" "$*"
	# TODO option to redirect logging to err
}
log_debug() {
	# Show only when verbose.
	(( VERBOSE_MODE )) || return 0
	_log DEBUG "${COLOR_DIM}" "$@"
}
log_info() {
	_log INFO "${COLOR_GREEN}" "$@"
}
log_warn() {
	_log WARN "${COLOR_YELLOW}" "$@"
}
log_error() {
	_log ERROR "${COLOR_RED}" "$@"
}
log_cmd() {
	_log CMD "${COLOR_BLUE}" "$(quote "$@")"
	"$@"
}
log_cmd_debug() {
	# log_cmd only in verbose mode
	if (( VERBOSE_MODE ))
	then
		log_cmd "$@"
	else
		"$@"
	fi
}
log_status() {
	# $1: message (optional)
	# --: command to execute
	# TODO progress-bar
	local msg="" ret=0
	[ "$1" == '--' ] || { msg=$1 && shift; }
	[ "$1" == '--' ] && shift
	printf '%s%-6s%s: %s... ' "${COLOR_BLUE}" RUN "${COLOR_RESET}" "${msg:-$1}"
	"$@" &>/dev/null || ret=$?
	if (( ret == 0 ))
	then
		printf '[%sok%s]\n' "${COLOR_GREEN}" "${COLOR_RESET}"
	else
		printf '[%sfail:%d%s]\n' "${COLOR_RED}" "$ret" "${COLOR_RESET}"
	fi
}
log_var() {
	# $1: variable name
	# $2: value (optional, default: variable is read)
	local _val _t=''
	if [ $# -eq 1 ]
	then
		local _decl="$(quiet_err declare -p "$1" || true)"
		[[ -z "$_decl" || "$_decl" == *=* ]] || _decl=uninitialized
		case "$_decl" in
		'')
			_val="${COLOR_DIM}undefined${COLOR_RESET}";;
		'uninitialized')
			_val="${COLOR_DIM}uninitialized${COLOR_RESET}";;
		'declare -a'*)
			_t=a
			_val="(array)";;
		'declare -A'*)
			_t=A
			_val="(map)";;
		*)
			_val=${!1};;
		esac
	else
		_val=$2
	fi
	_log VAR "${COLOR_CYAN}" "$(printf "%-20s: %s" "$1" "$_val")"
	# print array contents
	if [ -n "$_t" ]
	then
		eval "declare -$_t _arr=${_decl#*=}"
		for i in "${!_arr[@]}"
		do
			log_var "  [$i]" "${_arr[$i]}"
		done
	fi
}
log_section() {
	# Show section separator with text.
	local IFS=$' '
	echo "${COLOR_BOLD}******  ${COLOR_UNDERLINE}$*${COLOR_RESET}"
	printf '        %(%F %T)T\n'
}

log_redirect_to() {
	# Call this function only once to redirect all input to a file.
	# Sets OUTPUT_REDIRECT.
	# $1: file to log to
	if has_var OUTPUT_REDIRECT
	then
		log_warn "Already logging (pid: $OUTPUT_REDIRECT)"
		return 1
	fi
	local fifo="$(mktemp -u --tmpdir ".$$pipe-XXX")"
	mkfifo "$fifo" || die "Failed to open fifo for logging"
	tee -ia "$1" < "$fifo" &
	OUTPUT_REDIRECT=$!
	exec &> "$fifo"
	log_info "Logging to file [$1] started..."
	rm -f "$fifo"
}

echo() {
	# Safe echo without flags
	local IFS=$' '
	printf '%s\n' "$*"
}
readline() {
	# Read entire line
	local IFS=$'\n'
	read -r "$@"
}

indent() {
	# $1: prefix (default: tab)
	sed -u "s:^:${1:-\t}:" || true
}
indent_block() {
	echo "$HASH_SEP"
	indent '# ' | rtrim
	echo "$HASH_SEP"
}
indent_date() {
	# Prefix lines with a timestamp.
	# $1: date format (optional)
	local format="${1:-%T}" line now
	while readline line
	do
		printf -v now '%(%s)T'
		printf "%($format)T: %s\n" "$now" "$line"
	done
	return 0
}

quote() {
	# $@: arguments to quote
	local out=''
	while [ $# -gt 0 ]
	do
		[ -z "$out" ] || printf ' '
		if [[ "$1" =~ " " ]]
		then
			out="'${1//\'/\'\\\'\'}'"
			printf "%s" "$out"
		else
			out=1
			printf "%q" "$1"
		fi
		shift
	done
	printf '\n'
}

trim() {
	sed -u 's/^\s\+//; s/\s\+$//' || true
}
rtrim() {
	sed -u 's/\s\+$//' || true
}

color_enable() {
	# Enable COLOR_ variables
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
color_disable() {
	# Clear COLOR_ variables
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

# ---------------------------------------------------------
# Checks

is_executable() {
	# Check argument is executable
	quiet type "$@"
}
has_var() {
	# Check whether the variable is defined and initialized.
	local _v
	_v="$(quiet_err declare -p "$1")" && [[ "${_v}" == *=* ]]
}
has_val() {
	# Check whether the variable is not empty.
	has_var "$1" && [ -n "${!1}" ]
}
has_flag() {
	# Check whether the variable is true.
	has_var "$1" && is_true "${!1}"
}
is_true() {
	# Test argument value for a boolean.
	case "${1,,}" in
	y|yes|t|true|1|on) return 0;;
	n|no|f|false|0|off) return 1;;
	esac
	! is_integer "$1" || return 0
	return 2
}
is_integer() {
	# Test whether argument is a positive integer.
	[[ "$1" =~ ^[0-9]+$ ]]
}
is_number() {
	# Test whether argument is a number.
	[[ "$1" =~ ^-?[0-9]+(\.[0-9]*)?$ ]]
}
has_env() {
	# Check whether the variable is in env
	env | quiet grep "^$1="
}

arg_index() {
	# Print the index to stdout.
	# $1: argument
	# $2..: list to check against
	local opt=$1 index=0
	shift
	while [ $# -gt 0 ]
	do
		[[ "$opt" == "$1" ]] && echo $index && return 0 || true
		(( ++index ))
		shift
	done
	return 1
}

test_first_match() {
	# Print first argument that succeeds in a test.
	# $1: test operation
	# $2..: list of arguments to test
	local arg="$1"
	shift
	local val=
	for val in "$@"
	do
		if test "$arg" "$val"
		then
			printf '%s\n' "$val"
			return
		fi
	done
	return 1
}

strict() {
	# Strict mode:
	# errexit, errtrace (-eE)
	# nounset (-u)
	# pipefail, functrace
	set -eEu -o pipefail -o functrace
}
non_strict() {
	# Disable strict
	set +eEu +o pipefail +o functrace
}
stacktrace() {
	# Print stacktrace to stdout.
	# $1: mode (full or short) (default: full)
	# $2: number of frames to skip (default: 1)
	local mode="${1:-full}" skip="${2:-1}"
	local i=
	for (( i=skip; i<${#FUNCNAME[@]}; i++))
	do
		local name="${FUNCNAME[$i]:-??}" line="${BASH_LINENO[$i-1]}"
		case "$mode" in
		short)
			printf ' > %s:%s' "$name" "$line"
			;;
		*)
			printf '  at: %s (%s:%d)\n' "$name" "${BASH_SOURCE[$i]:-(unknown)}" "$line"
			;;
		esac
	done
}
_on_exit_callback() {
	# $@: $PIPESTATUS
	# called by default in bashf on exit
	# log FATAL error if command failed in strict mode
	local ret=$? cmd="$BASH_COMMAND" pipestatus=("$@")
	[[ "$cmd" != exit* ]] || cmd=""
	if [[ $- == *e* && "$ret" != 0 ]]
	then
		[[ "$cmd" != return* ]] || cmd=""
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
trap_add() {
	# Add command to trap EXIT.
	# $*: command to run
	local handle="$(trap -p EXIT \
		| sed "s:^trap -- '::" \
		| sed "s:' EXIT\$::")"
	local IFS=$' '
	trap "$*; $handle" EXIT
}
trap_default() {
	# Set default trap on ERR in bashf.
	trap '_on_exit_callback "${PIPESTATUS[@]}"' ERR
}

die() {
	# Log error and exit with failure.
	log_error "$@"
	log_debug "$(stacktrace short 2)" >&2
	exit 1
}
die_usage() {
	# Log error, usage and exit with failure.
	log_error "$@"
	usage >&2
	exit 1
}
die_return() {
	# Log error and exit with given code.
	# $1: exit code
	# $2..: message
	local e="$1"
	shift
	log_error "$@"
	log_debug "$(stacktrace short 2)" >&2
	exit "$e"
}

# ---------------------------------------------------------
# Input

prompt() {
	# Prompt user.
	# usage: variable_name [ options ]
	# --text|-t: prompt
	# --def|-d: default value
	# --non-empty|-n: force having a reply
	# --silent|-s: for password prompting
	# anything else is passed to `read`
	local _name=$1 _text='' _def='' _req=0 _silent=0
	shift
	[ -n "$_name" ] || die "prompt(): No variable name set"
	eval $(arg_eval \
		text t _text=:val \
		def d _def=:val \
		non-empty n _req=1 \
		silent s _silent=1 \
		--invalid-break \
	)
	if is_true "$BATCH_MODE"
	then
		[ -n "$_def" ] || die "prompt(): Default value not set for $_name"
		log_debug "Use default value:"
		log_var "$_name" "$_def"
		eval "$_name=\$_def"
		return
	fi
	# Read from input
	[ -n "$_text" ] || _text="Enter $_name"
	[ -z "$_def" ] || _text+=" ${COLOR_DIM}[$_def]${COLOR_RESET}"
	! is_true "$_silent" || set -- -s "$@"
	while true
	do
		local _end=N
		! has_var OUTPUT_REDIRECT || sleep 0.1
		if read "$@" -r -p "${_text}: " "$_name"
		then
			! (has_var OUTPUT_REDIRECT || quiet arg_index -s "$@" ) \
				|| echo
		else
			case $? in
			1|142) # EOF | timeout
				echo;;
			*)
				die "prompt(): Failed to read input! ($?)";;
			esac
			_end=Y
		fi
		[ -n "${!_name}" ] || eval "$_name=\$_def"
		[ "$_req" -gt 0 ] && [ -z "${!_name}" ] || break
		! has_flag _end || die "prompt(): Reached end of input"
	done
}

confirm() {
	# Ask for a boolean reply.
	# usage: [ text_prompt ] [ options ]
	# --def|-d: default value (Y/N)
	# Rest passed to `prompt`.
	local confirmation='' _text='' _def=''
	if [ $# -gt 0 ] && [ "${1:0:1}" != '-' ]
	then
		_text=$1
		shift
	else
		_text='Confirm'
	fi
	_text+=' (y/n)'
	eval $(arg_eval \
		def d _def=:val \
		--invalid-break \
	)
	if [ -n "$_def" ]
	then
		set -- --def "${_def^^}" "$@"
	fi
	while true
	do
		prompt confirmation --text "$_text" "$@"
		is_true "$confirmation" && confirmation=0 || confirmation=$?
		case "$confirmation" in
		0) return 0;;
		1) return 1;;
		esac
	done
}

prompt_choice() {
	# Prompt with multiple choices.
	# usage: variable_name [ options ] -- menu choices
	# --text|-t: prompt
	# --def|-d: default reply
	# menu choices are in format 'value|text'
	local _name=$1 _text='' _def=''
	shift
	[ -n "$_name" ] || die "prompt(): No variable name set"
	eval $(arg_eval --partial \
		text t _text=:val \
		def d _def=:val \
	)
	[ "$1" == '--' ] && shift
	[ -n "$_text" ] || _text="Select $_name"
	if is_true "$BATCH_MODE"
	then
		prompt "$_name" --text "$_text" --def "$_def"
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
	! has_var OUTPUT_REDIRECT || sleep 0.1
	printf '%s\n' "$_text"
	_i=0
	for _item in "${_mtext[@]}"
	do
		(( ++_i ))
		printf " %2d) %s\n" "$_i" "$_item"
	done
	while true
	do
		prompt _item --text 'Choice' --def "$_def"
		if is_integer "$_item" && (( 0 < _item && _item <= ${#_mvalue[@]} ))
		then
			_item=${_mvalue[$_item-1]}
			break
		elif quiet arg_index "$_item" "${_mvalue[@]}"
		then
			break
		else
			log_warn 'Invalid choice'
		fi
	done
	eval "$_name=\$_item"
}

menu_loop() {
	# Prompt in a loop.
	# usage: [ prompt_text ] -- menu entries
	# menu entries are 'function|text'
	local _text=Menu _item IFS=' '
	eval $(arg_eval_rest ? _text --partial)
	[ "$1" == '--' ] && shift
	if is_true "$BATCH_MODE"
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
		prompt_choice REPLY --text "${COLOR_BOLD}$_text${COLOR_RESET}" \
			-- "$@" "break|Exit" || break
		[ "$REPLY" != break ] || break
		log_cmd_debug $REPLY
	done
}

wait_user_input() {
	# Wait for user confirmation.
	confirm "Proceed..." --def Y
}

# ---------------------------------------------------------
# Various
# - argument parsing
# - list functions
# - execution (mask output, cd, run_main)
# - pager
# - job control

arg_eval() {
	# Generate parser for arguments (starting with a -).
	# Must be used inside a function.
	# usage: eval $(arg_eval var=:val text t var2=1)
	# --partial: can leave unparsed arguments
	# --opt-var=name: adds standalone options to an array variable
	# --opt-break: break on first option (imply partial)
	# --invalid-break: break on first invalid argument (imply partial)
	# --var=name: local temp variable (default: $_arg)
	# name: alias for next command (single letter is short option)
	# x=v or { code }: command to execute (if v is :val, the next argument is read)
	local _name='' _i _arg_partial=F _arg_opts='' _arg_invalid_break=F _var=_arg
	for _i in "$@"
	do
		case "$_i" in
			--partial) _arg_partial=T;;
			--opt-break) _arg_opts=break; _arg_partial=T;;
			--opt-var=*) _arg_opts=${_i#*=};;
			--invalid-break) _arg_invalid_break=T; _arg_partial=T;;
			--var=*) _var=${_i#*=};;
			-*) die "arg_eval: invalid option [$_i]";;
		esac
	done
	# start parser
	echo "local $_var;"
	echo 'while [ $# -gt 0 ];'
	echo 'do'
	echo " $_var=\$1;"
	# check for equal sign
	echo " if [[ \"\$$_var\" == -*=* ]]; then"
	echo "  shift;"
	echo "  set -- \"\${$_var%=*}\" \"\${$_var#*=}\" \"\$@\";"
	echo ' fi;'
	# check options
	echo ' case "$1" in'
	echo ' --) break;;'
	for _i in "$@"
	do
		case "$_i" in
		-*) continue;;
		*=*|{*})
			[ -n "$_name" ] || \
				_name="--${_i%=*}"
			# with and without value
			if [[ "$_i" == *:val* ]]
			then
				_i=${_i/:val/\$2}
				_i='[ $# -gt 1 ] || die "Missing argument for ['"$_name"']"; '"$_i"
				_i+='; shift 2'
			else
				_i+='; shift'
			fi
			echo " $_name) $_i;;"
			_name=''
			;;
		*)
			[ -z "$_name" ]  || _name+='|'
			if [ "${#_i}" -gt 1 ]
			then
				_name+='--'
			else
				_name+='-'
			fi
			_name+=$_i
			;;
		esac
	done
	[ -z "$_name" ] || die "arg_eval: invalid spec, assign a value"
	# invalid arguments
	if is_true "$_arg_invalid_break"
	then
		echo ' -?*) break;;'
	else
		echo ' -?*) die "Invalid argument [$1]";;'
	fi
	# other options
	case "$_arg_opts" in
		break) echo ' *) break;;';;
		'') echo ' *) die "Unexpected argument [$1]";;';;
		*) echo ' *) '"$_arg_opts"'+=("$1"); shift;;';;
	esac
	echo ' esac;'
	echo 'done;'
	is_true "$_arg_partial" || \
		echo '[ $# -eq 0 ] || die "Too many arguments";'
}

arg_eval_rest() {
	# Generate parser for non-arguments (rest of parameters)
	# Usage: eval $(arg_eval_rest arg1 ? arg2)
	# --partial: can leave unparsed arguments
	# name: name of the argument
	# ?: after this point arguments are optional
	local _i _arg_partial=F _arg_optional=F
	# output parser
	for _i in "$@"
	do
		case "$_i" in
			--partial) _arg_partial=T;;
			\?) _arg_optional=T;;
			-*) die "arg_eval: invalid option [$_i]";;
			*)
				echo 'if [ $# -gt 0 ] && [ "$1" != -- ]; then'
				echo " $_i=\$1; shift;"
				if ! is_true "$_arg_optional"
				then
					echo 'else'
					echo ' die "Expecting argument for '"$_i"'";'
				fi
				echo 'fi;'
				;;
		esac
	done
	is_true "$_arg_partial" || \
		echo '[ $# -eq 0 ] || die "Too many arguments";'
}

# TODO rewrite using arg_eval
declare -A ARG_PARSER_CMD ARG_PARSER_SHORT ARG_PARSER_USAGE
declare -A ARG_PARSER_OPT
arg_parse_opt() {
	# $1: long option name
	# $2: description
	# $3..:
	#   -s char: short option character
	#   -v variable: variable to set
	#   -V: variable to set, same as name
	#   -f: var set to boolean (Y/N)
	#   -r: var set to next arg
	#   -a: append next arg to var (array)
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
			;;
		-f)
			_cmd="$_var=Y"
			eval "$_var=F"
			shift;;
		-r)
			_cmd="{ $_var=\$1; shift; }"
			eval "$_var=''"
			shift;;
		-a)
			_cmd="{ $_var+=(\"\$1\"); shift; }"
			eval "$_var=()"
			shift;;
		-*)
			die "arg_parse_opt(): unknown option [$1]";;
		*)
			_cmd=$1
			shift;;
		esac
	done
	[ -n "$_cmd" ] || die "No command for $_name"
	ARG_PARSER_CMD[$_name]=$_cmd
}
arg_parse_reset() {
	ARG_PARSER_CMD=()
	ARG_PARSER_SHORT=()
	ARG_PARSER_USAGE=()
	ARG_PARSER_OPT[named]= # how to treat named arguments (no -*)
	ARG_PARSER_OPT[rest]= # how to treat rest of the arguments
	ARG_PARSER_OPT[require]=0 # number of required named arguments
	ARG_PARSER_OPT[break_on_named]=N # whether to stop option parsing on named argument
	[ "${1:-}" == 'default' ] || return 0
	arg_parse_opt help 'Show help' -s h -s '?' '{ usage; exit; }'
	arg_parse_opt batch-mode '' 'BATCH_MODE=Y'
	arg_parse_opt verbose 'Show debug messages' 'VERBOSE_MODE=$((VERBOSE_MODE+1))'
	arg_parse_opt no-color '' color_disable
	arg_parse_opt trace '' 'set -x'
	arg_parse_opt quiet '' '{ exec >/dev/null; VERBOSE_MODE=0; }'
}
arg_parse_require() {
	# $1: number of required arguments
	ARG_PARSER_OPT['require']=$1
}
arg_parse_rest() {
	# $1: one of the following
	#   - name of the rest arguments (default: '')
	#   - number of named arguments ($2.. are the names)
	# -- name for the rest of arguments
	local _i _a="${1:-}"
	ARG_PARSER_OPT['named']=$_a
	[ -n "$_a" ] || return 0
	shift
	if is_integer "$_a"
	then
		for (( _i=0; _i < _a; _i++ ))
		do
			ARG_PARSER_OPT["named$_i"]=$1
			eval "$1=''"
			shift
		done
	elif [ "$_a" != '--' ]
	then
		eval "$_a=()"
	else
		ARG_PARSER_OPT['named']=''
	fi
	_a="${1:-}"
	[ "$_a" != '--' ] || shift && _a="${1:-}"
	ARG_PARSER_OPT['rest']=$_a
	[ -z "$_a" ] || eval "$_a=()"
}

arg_parse() {
	# $@: arguments to parse
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
			[ ${#_arg} -le 2 ] || set -- "-${_arg:2}" "$@"
			_arg=${_arg:1:1}
			_arg=${ARG_PARSER_SHORT[${_arg}]:-$_arg}
			_cmd=${ARG_PARSER_CMD[${_arg}]:-}
			_arg="-$_arg" # for error messages
		else
			# Add to named arguments
			_rest+=("$_arg")
			if [ "${ARG_PARSER_OPT['break_on_named']:-N}" != N ]
			then
				while [ $# -gt 0 ]
				do
					[ "$1" != '--' ] || break
					_rest+=("$1")
					shift
				done
				break
			fi
			continue
		fi
		[ -n "$_cmd" ] || die_usage "Unknown option [$_arg]"
		eval "$_cmd" || die "Failed to parse option [$_arg]" "$@"
	done
	# Set the rest
	[ "${_rest:+x}" == x ] \
		&& set -- "${_rest[@]}" -- "$@" \
		|| set -- -- "$@"
	local _req=${ARG_PARSER_OPT['require']:-0}
	# Parse the named arguments
	local _i _name=${ARG_PARSER_OPT['named']}
	if is_integer "$_name"
	then
		for (( _i=0; _i < _name; _i++ ))
		do
			[ "$1" != '--' ] || break
			eval "${ARG_PARSER_OPT["named$_i"]}=\$1"
			(( _req--, 1 ))
			shift
		done
	elif [ -n "$_name" ]
	then
		_i=$(arg_index '--' "$@")
		eval "$_name=(\"\${@:1:$_i}\")"
		(( _req -= _i, 1 ))
		shift "$_i"
	fi
	# Check unparsed arguments
	[ "$_req" -le 0 ] || \
		die_usage "$SCRIPT_NAME expects $_req additional arguments"
	[ "$1" == '--' ] || \
		die_usage "$SCRIPT_NAME doesn't accept more positional arguments"
	shift
	_name=${ARG_PARSER_OPT['rest']}
	if [ -n "$_name" ]
	then
		eval "$_name=(\"\$@\")"
	elif [ $# -gt 0 ]
	then
		die_usage "Unexpected unparsed argument [$1]"
	fi
}

usage_parse_args() {
	# $@:
	#   -U: print default usage line
	#   -u opts: print usage line
	#   -t text: print text
	#   -: print from stdin
	local IFS=' ' arg usage=0
	local named=${ARG_PARSER_OPT['named']}
	local req=${ARG_PARSER_OPT['require']}
	while [ $# -gt 0 ]
	do
		case "$1" in
		-U)
			printf 'Usage: %s [ options ]' "$SCRIPT_NAME"
			if is_integer "$named"
			then
				for (( arg=0; arg < named; arg++ ))
				do
					if [ "$req" -gt 0 ]
					then
						printf ' %s' "${ARG_PARSER_OPT["named$arg"]}"
						(( req--, 1 ))
					else
						printf ' [%s]' "${ARG_PARSER_OPT["named$arg"]}"
					fi
				done
			elif [ -n "$named" ]
			then
				if [ "$req" -gt 0 ]
				then
					printf ' %s' "$named"
				else
					printf ' [%s]' "$named"
				fi
			fi
			[ -n "${ARG_PARSER_OPT['rest']}" ] \
				&& echo " [ -- ${ARG_PARSER_OPT['rest']} ]" \
				|| echo
			(( usage+=1 ))
			shift;;
		-u)
			[ "$usage" -gt 0 ] \
				&& printf '      ' \
				|| printf 'Usage:'
			printf ' %s %s\n' "$SCRIPT_NAME" "$2"
			(( usage+=1 ))
			shift 2;;
		-t)
			printf '%s\n' "$2"
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

_read_functions_from_file() {
	# Print "$function_name:$line" for each function in file.
	# $1: file to read
	local file="$1"
	[ -r "$file" ] || die "Cannot read file [$file]"
	(grep -n '^\(function \)\?[a-z]\w*\s\?()' "$file" || true) |
	sed 's/^\([0-9]\+\):\(function\s*\)\?\([a-z]\w*\)\s\?().*$/\3:\1/' |
	sort
}

read_function_help() {
	# Print first comment block in a function.
	# $1: function name
	# stdin: function/file code
	local func=$1
	local i
	while readline i
	do
		if [[ "$i" =~ ${func}\s?() && "$i" != *'#'* ]]
		then
			trim | sed -n '/^[^#]/q; s/#\s\?//p'
			break
		fi
	done
}

quiet() {
	# Suppress output
	"$@" &>/dev/null
}
quiet_err() {
	# Suppress stderr
	"$@" 2>/dev/null
}

pager() {
	# Use a pager for displaying text.
	# If parameters are given, the output is executed, piped and return code
	# is returned.
	local pager=() r
	if has_val PAGER
	then
		pager=("$PAGER")
	elif is_executable less
	then
		pager=(less --RAW-CONTROL-CHARS --no-init --quit-if-one-screen)
	fi
	if [ $# -eq 0 ]
	then
		# run pager
		"${pager[@]}"
	elif [ -n "$pager" ]
	then
		# pipe and return exit code
		"$@" | "${pager[@]}" && r=0 || r=("${PIPESTATUS[@]}")
		return $r
	else
		# no pager, just run
		"$@"
	fi
}

exec_in() {
	# Execute command in directory.
	# $1: directory
	# $2..: command
	local dir=$1
	shift
	(
		cd "$dir" || return
		"$@"
	)
}

is_main() {
	# Check if current file is being called.
	[[ "$0" == "${BASH_SOURCE[-1]:-}" ]]
}
run_main() {
	# Run the `main` function if this is the called file.
	# $@: pass arguments to main
	is_main || return 0
	is_executable main || die "run_main: missing main function"
	(
		local IFS=$' '
		log_section "$SCRIPT_NAME"
		log_var "Directory" "$(pwd)"
		log_var "User@Host" "$SCRIPT_USER@$HOSTNAME [$OSTYPE]"
		[ -z "$*" ] || log_var "Arguments" "$(quote "$@") "
	) | indent_block
	main "$@"
	log_debug "END $SCRIPT_NAME"
}

declare -i JOBS_PARALLELISM
declare -i JOBS_FAIL JOBS_SUCCESS
declare -a JOBS_PIDS
init_jobs() {
	# Initialize parallel job controls.
	# TODO arg_eval
	# $1: max parallelism (default: processor count)
	# sets JOBS_PARALLELISM, JOBS_PIDS, JOBS_FAIL, JOBS_SUCCESS
	JOBS_PIDS=()
	JOBS_FAIL=0
	JOBS_SUCCESS=0
	[ $# -eq 0 ] || JOBS_PARALLELISM=$1
	has_val JOBS_PARALLELISM || JOBS_PARALLELISM=$(grep -c '^processor' /proc/cpuinfo)
	(( JOBS_PARALLELISM > 0 )) || die "init_jobs: parallelism must be positive"
	log_debug "Max jobs: $JOBS_PARALLELISM"
}
check_jobs() {
	# Check for jobs in JOBS_PIDS and remove finished ones.
	local failed=0 success=0 pid
	local running=()
	for pid in "${JOBS_PIDS[@]}"
	do
		if quiet kill -s 0 "$pid"
		then
			running+=("$pid")
		else
			wait "$pid" && (( ++success )) || (( ++failed ))
			log_debug " job $pid finished"
		fi
	done
	(( JOBS_SUCCESS += success )) || true
	(( JOBS_FAIL += failed )) || true
	JOBS_PIDS=(${running[@]})
	return $failed
}
finish_jobs() {
	# Wait for all jobs to finish.
	while [ ${#JOBS_PIDS[@]} -gt 0 ]
	do
		sleep 0.1
		check_jobs || true
	done
	log_debug "  $JOBS_SUCCESS jobs finished"
	[ "$JOBS_FAIL" -eq 0 ] || log_debug "  $JOBS_FAIL jobs failed"
	log_debug "Finishing all jobs"
	wait || (( ++JOBS_FAIL ))
	return $JOBS_FAIL
}
spawn() {
	# Start a job.
	# usage: [options -- ] command [args]
	# -i: don't disable input
	# TODO arg_eval
	local ret=0 _input=N
	while [[ "$1" == -* ]]
	do
		case "$1" in
		--)
			shift
			break;;
		-i)
			_input=Y;;
		*)
			log_error "Invalid option [$1]"
			return 1;;
		esac
		shift
	done
	# throttle
	while [ $(jobs | wc -l) -ge "$JOBS_PARALLELISM" ]
	do
		sleep 0.1
		check_jobs || (( ret += $? ))
	done
	[ ${#JOBS_PIDS[@]} -le "$JOBS_PARALLELISM" ] || \
		check_jobs || (( ret += $? ))
	# start
	if has_flag _input
	then
		"$@" &
	else
		"$@" </dev/null &
	fi
	local pid=$!
	JOBS_PIDS+=($pid)
	log_debug " job $pid started"
	return $ret
}

wait_until() {
	# Wait for N seconds or until the command is true.
	# $1: number of seconds
	# $2..: command
	# TODO arg_eval
	local timeout=$1 now
	printf -v now '%(%s)T'
	(( timeout += now ))
	shift
	while ! "$@"
	do
		printf -v now '%(%s)T'
		[ "$timeout" -gt "$now" ] || return 1
		sleep 0.1
	done
	return 0
}

# ---------------------------------------------------------
# Global variables and initialization

IFS=$'\n\t'
declare -i VERBOSE_MODE=${VERBOSE_MODE:-0}
declare LINE_SEP HASH_SEP
printf -v LINE_SEP "%${COLUMNS:-78}s"
LINE_SEP=${LINE_SEP// /-}
HASH_SEP=${LINE_SEP//-/#}
if has_var COLOR_MODE
then
	is_true "$COLOR_MODE" && color_enable || color_disable
else
	[[ -t 1 ]] && color_enable || color_disable
fi
if ! has_var BATCH_MODE
then
	[[ -t 0 || -p /dev/stdin ]] && BATCH_MODE=N || BATCH_MODE=Y
fi

trap_default
strict

[[ "$BASH" == *bash ]] || die "You're not using bash"
(( "${BASH_VERSINFO[0]}" >= 4 )) || log_warn "Minimum requirement for bashf is bash 4"
is_executable realpath || die "realpath is missing"

# Set variables
SCRIPT_USER="${USER:-${USERNAME:-}}"
has_val SCRIPT_USER || SCRIPT_USER="$(id -un)"
printf -v TIMESTAMP '%(%Y%m%d_%H%M%S)T'
readonly SCRIPT_USER TIMESTAMP
readonly SCRIPT_WORK_DIR=$PWD
SCRIPT_NAME=${0#-*}
readonly SCRIPT_DIR="$(realpath "$(dirname "$SCRIPT_NAME")")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_NAME")"
TMPDIR=${TMPDIR:-/tmp}

has_val HOSTNAME || HOSTNAME="$(hostname)"
has_val OSTYPE || OSTYPE="$(uname)"

# Default usage definition
if ! is_executable usage
then
	function usage() {
		if [[ "$SCRIPT_NAME" == bash ]]
		then
			usage_parse_args -u 'bashf.sh' -t 'Interactive mode'
			return
		fi
		# quit when found a non-comment line
		# and strip comment character
		sed '/^[^#]/Q; /^$/Q; /^#!/d; s/^#\s\?//' "$SCRIPT_DIR/$SCRIPT_NAME" \
			| usage_parse_args -U -
	}
fi

# TODO debug mode
#BASH_XTRACEFD="5"
#PS4='$LINENO: '

# Check environment
case "$SCRIPT_NAME" in
bashf.sh)
	# Executed from console
	# TODO use run_main
	arg_parse_reset default
	arg_parse_opt filter 'Filter functions' \
		-v FILTER -r -s f
	arg_parse "$@"
	FUNCTIONS=($(_read_functions_from_file "$0"))
	for f in "${FUNCTIONS[@]}"
	do
		[ -z "$FILTER" ] || [[ "$f" == *$FILTER* ]] || continue
		func=${f%:*}
		line=${f#*:}
		printf "%s ${COLOR_DIM}(%d)${COLOR_RESET}\n" "$func" "$line"
		[ -z "$FILTER" ] || read_function_help "$func" < "$0" | indent '  '
	done
	;;
bash)
	# Sourced from console
	arg_parse_reset
	PS1="${COLOR_DIM}(bf)${COLOR_RESET}$PS1"
	log_warn "Interactive bashf"
	;;
*)
	# Normal script
	arg_parse_reset default
	;;
esac

# End of bashf.sh
