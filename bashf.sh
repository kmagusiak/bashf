#!/bin/bash
#
# Use this in your script:
#   source ./bashf.sh || exit 1
#
# When executed, shows the function list and help for them.
# Features: logging, prompting, checking values, utils (argument parsing)
#
# Variables read:
# - BATCH_MODE (bool) - sets non-interactive mode
# - COLOR_MODE (bool) - see color_enable() / color_disable()
# - VERBOSE_MODE (int) - sets verbosity
# - OUTPUT_REDIRECT (optional) - set by log_redirect_to
# Variables set:
# - SCRIPT_* - information about current script
# - LINE_SEP - separator
# - HOSTNAME, OSTYPE, TMPDIR - defined if not already known
#
# You can either define usage() for your script or one will get defined by
# reading the header of your script.
#
# Strict mode is enabled by default.
# In this mode, script stops on error, undefined variable or pipeline fails.
#
# Additional fd's are open.
# 3 for logging messages, by default redirected on 1 (stdout).
# 5 for debug tracing, by default redirected to 2 (stderr).

[ -z "${BASHF:-}" ] || return 0 # already sourced
readonly BASHF="$(dirname "${BASH_SOURCE[0]}")"

# ---------------------------------------------------------
# Logging and output

_log() {
	# usage: marker color text...
	local IFS=$' ' mark=$1 color=$2
	shift 2
	printf '%s%-6s%s: %s\n' "$color" "$mark" "$COLOR_RESET" "$*" >&3
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
	# Log command and run it
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
	echo "${COLOR_BOLD}******  ${COLOR_UNDERLINE}$*${COLOR_RESET}" >&3
	printf '        %(%F %T)T\n' >&3
}

log_script_info() {
	# Log information about the running scripts.
	# $@: arguments for main
	is_main || return 0
	(
		local IFS=$' '
		log_section "$SCRIPT_NAME"
		log_var "Directory" "$(pwd)"
		log_var "User" "$SCRIPT_USER"
		log_var "Host" "$HOSTNAME [$OSTYPE]"
		[ -z "$*" ] || log_var "Arguments" "$(quote "$@") "
	) 3>&1 | indent_block >&3
}

log_redirect_output_to() {
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
	# Enable COLOR_* variables
	COLOR_MODE=1
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
	# Clear COLOR_* variables
	COLOR_MODE=0
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
	# Check argument is executable.
	quiet type "$@"
}
has_var() {
	# Check whether the variable is defined and initialized.
	local _v
	_v="$(quiet_err declare -p "$1")" && [[ "${_v}" == *=* ]]
}
has_val() {
	# Check whether the variable is not empty.
	has_var "$1" && [ -n "${!1:-}" ]
}
has_flag() {
	# Check whether the variable is true.
	has_var "$1" && is_true "${!1:-}"
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

index_of() {
	# Print the index to stdout.
	# $1: argument
	# $2..: list to check against
	local opt=$1 index=0 i
	shift
	for i in "$@"
	do
		[[ "$opt" == "$i" ]] && echo $index && return 0 || true
		(( ++index ))
	done
	return 1
}

first_match() {
	# Print first argument that succeeds a test.
	# $1: test operation (or argument to test command)
	# $2..: list of arguments to test
	local check=("$1") val=
	[[ $check != -* ]] || check=(test "$check")
	shift
	for val in "$@"
	do
		"${check[@]}" "$val" && printf '%s\n' "$val" && return 0 || true
	done
	return 1
}

strict() {
	# Strict mode.
	# errexit, errtrace (-eE)
	# nounset (-u)
	# pipefail, functrace
	set -eEu -o pipefail -o functrace
}
non_strict() {
	# Disable strict.
	set +eEu +o pipefail +o functrace
}

debug_trace() {
	# Enable tracing on fd 5 (redirected to 2)
	log_debug "Enable tracing."
	PS4='+|${FUNCNAME[0]:0:15}|${LINENO}| '
	(printf '' >&5) &>/dev/null || exec 5>&2
	BASH_XTRACEFD=5
	set -x
}
debug_repl() {
	# Simple loop with eval, use as breakpoint in scripts.
	local REPLY
	while true
	do
		read -e -p "debug-${PS3:-> }" || break
		eval $REPLY || log_warn "repl: error ($?)"
	done
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
			msg+=" (pipe: ${pipestatus[*]})"
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
		log_debug "Use default value: $_name=$_def"
		eval "$_name=\$_def"
		return
	fi
	# Read from input
	[ -n "$_text" ] || _text="Enter $_name"
	[ -z "$_def" ] || _text+=" ${COLOR_DIM}[$_def]${COLOR_RESET}"
	[ $# -eq 0 ] || log_debug "read arguments: $*"
	! is_true "$_silent" || set -- -s "$@"
	while true
	do
		local _end=N
		! has_var OUTPUT_REDIRECT || sleep 0.1
		if read "$@" -r -p "${_text}: " "${_name?}"
		then
			! (has_var OUTPUT_REDIRECT || quiet index_of -s "$@" ) \
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
	[ -z "$_def" ] || _def=$(( $(index_of "$_def" "${_mvalue[@]}") + 1 ))
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
		elif quiet index_of "$_item" "${_mvalue[@]}"
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
	if is_true "$BATCH_MODE"
	then
		log_info "${_text}"
		for _item
		do
			_item="${_item%%|*}"
			# evaluate item (not quoted)
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
		# evaluate item (not quoted)
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
# - execution (mask output, cd, is_main, retry)
# - http
# - pager
# - job control
# - file locking

arg_eval() {
	# Generate parser for arguments (starting with a -).
	# Must be used inside a function.
	# usage:
	#     eval $(arg_eval var=:val text t --desc='Set text to 1' =1)
	#     eval $(arg_eval help h --desc='Help' '{ help }')
	# --partial: can leave unparsed arguments
	# --opt-var=name: adds standalone options to an array variable
	# --opt-break: break on first option (imply partial)
	# --invalid-break: break on first invalid argument (imply partial)
	# --var=name: local temp variable (default: $_arg)
	# --desc=text: description for next command
	# name: alias for next command (single letter is short option)
	# x=v or { code }: command to execute
	#     if x is empty, last alias is used as variable name
	#     if v contains :val, the next argument is used as the value
	local _alias='' _name='' _i _arg_partial=F _arg_opts='' _arg_invalid_break=F _var=_arg
	for _i in "$@"
	do
		case "$_i" in
			--partial) _arg_partial=T;;
			--opt-break) _arg_opts='break'; _arg_partial=T;;
			--opt-var=*) _arg_opts=${_i#*=};;
			--invalid-break) _arg_invalid_break=T; _arg_partial=T;;
			--var=*) _var=${_i#*=};;
			--desc=*) ;;
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
	echo "  $_var=\$1;"
	echo ' fi;'
	# multi short options
	echo " if [[ \"\$$_var\" =~ ^-[a-zA-Z]{2,} ]]; then"
	echo "  shift;"
	echo "  set -- \"\${$_var:0:2}\" \"-\${$_var:2}\" \"\$@\";"
	echo "  $_var=\$1;"
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
				die "arg_eval: missing option name for [$_i]"
			# check if '=...'
			[[ "$_i" != '='* ]] || \
				_i="${_name}${_i}"
			# with and without value
			if [[ "$_i" == *:val* ]]
			then
				_i=${_i/:val/\$2}
				_i='[ $# -gt 1 ] || die "Missing argument for ['"$_alias"']"; '"$_i"
				_i+='; shift 2'
			else
				_i+='; shift'
			fi
			echo " $_alias) $_i;;"
			_alias=''
			_name=''
			;;
		*)
			[ -z "$_alias" ] || _alias+='|'
			[ "${#_i}" -eq 1 ] && _alias+='-' || _alias+='--'
			_alias+=$_i
			_name=$_i
			;;
		esac
	done
	[ -z "$_alias" ] || die "arg_eval: invalid spec, assign a value"
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
		echo '[ $# -eq 0 ] || die "Too many arguments, next [$1]";'
}

arg_eval_rest() {
	# Generate parser for named non-arguments (rest of parameters)
	# Usage: eval $(arg_eval_rest arg1 ? arg2 [ options ])
	# --partial: can leave unparsed arguments (after '--')
	# --opt-var=name: array to which to append other arguments
	# --opt-min=N: minimum number of arguments in list
	# --partial-var=name: array to which to assign all arguments
	#   after '--', implies --partial
	# --var=name: local temp variable (default: $_arg)
	# name: name of the argument
	# ?: after this point arguments are optional
	local _i _arg_partial=F _arg_optional=F _var=_arg
	local _arg_var_list='' _arg_list_min=0 _arg_var_partial=''
	# output parser
	while [ $# -gt 0 ]
	do
		_i=$1
		shift
		case "$_i" in
			--) break;;
			--partial) _arg_partial=T;;
			--partial-var=*) _arg_var_partial=${_i#*=}; _arg_partial=T;;
			--opt-var=*) _arg_var_list=${_i#*=};;
			--opt-min=*) _arg_list_min=${_i#*=};;
			--var=*) _var=${_i#*=};;
			-*) die "arg_eval_rest: invalid option [$_i]";;
			\?) _arg_optional=T;;
			*)
				# named arguments
				echo 'if [ $# -gt 0 ] && [ "$1" != -- ]; then'
				echo " $_i=\$1; shift;"
				if ! is_true "$_arg_optional"
				then
					echo 'else'
					echo ' die "Expecting '"$_i"' argument";'
				fi
				echo 'fi;'
				;;
		esac
	done
	# list arguments
	if [ -n "$_arg_var_list" ]
	then
		echo "local $_var=\$(index_of '--' \"\$@\" || true);"
		echo "if [ -n \"\$$_var\" ]; then"
		echo " $_arg_var_list=(\"\${@:1:\$$_var}\");"
		echo " shift \${$_var};"
		echo 'else'
		echo " $_arg_var_list=(\"\$@\");"
		echo ' set --;'
		echo 'fi;'
	fi
 	[ "$_arg_list_min" -eq 0 ] || \
 		echo "[ \${#${_arg_var_list}[@]} -ge $_arg_list_min ] || " \
 		"die 'Not enough arguments ($_arg_list_min needed)';"
	# partial arguments
	if is_true "$_arg_partial"
	then
		printf '%s' '[ $# -eq 0 ] || { [ "$1" == "--" ] && shift; }'
		echo ' || die "Unexpected argument [$1]";'
		if [ -n "$_arg_var_partial" ]
		then
			echo "$_arg_var_partial=(\"\$@\");"
			echo 'set --;'
		fi
	else
		echo '[ $# -eq 0 ] || die "Too many arguments, next [$1]";'
	fi
}

declare -a ARG_PARSE_OPTS=() ARG_PARSE_REST=()
arg_parse_reset() {
	# Reset the parser by defining ARG_PARSE_OPTS and ARG_PARSE_REST.
	# Arguments can be:
	#  color: color and no-color options
	#  help: Show the usage and exit (-h)
	#  quiet: Suppress output
	#  trace: See debug_trace function
	#  verbose: Show verbose message
	#  v: verbose (short option)
	#  default: help verbose color
	ARG_PARSE_OPTS=()
	ARG_PARSE_REST=()
	local i
	if [ "${1:-}" == "default" ]
	then
		shift
		set -- help verbose color "$@"
	fi
	for i in "$@"
	do
		case "$i" in
		help) ARG_PARSE_OPTS+=(help h --desc='Show help' '{ usage; exit; }');;
		v) ARG_PARSE_OPTS+=(v '{ (( ++VERBOSE_MODE )) }');;
		verbose) ARG_PARSE_OPTS+=(verbose
			--desc='Show debug messages' '{ (( ++VERBOSE_MODE )); }'
			);;
		color) ARG_PARSE_OPTS+=(
			color '{ color_enable; }'
			no-color '{ color_disable; }'
			);;
		trace) ARG_PARSE_OPTS+=(trace '{ debug_trace; }');;
		quiet) ARG_PARSE_OPTS+=(quiet
			'{ exec 2>/dev/null 3>/dev/null; VERBOSE_MODE=0; }'
			);;
		*) log_warn "Unknown parser preset [$i]";;
		esac
	done
}
arg_parse() {
	# Run the parser, give "$@" as arguments.
	# Combines `arg_eval` with arguments ARG_PARSE_OPTS
	# and `arg_eval_rest` with arguments ARG_PARSE_REST.
	local _arg_parse_opts=()
	eval $(arg_eval --partial --opt-var=_arg_parse_opts "${ARG_PARSE_OPTS[@]}")
	[ "${#_arg_parse_opts[@]}" -eq 0 ] || set -- "${_arg_parse_opts[@]}" "$@"
	eval $(arg_eval_rest "${ARG_PARSE_REST[@]}")
}

usage_arg_parse() {
	# Print usage message with options list based on ARG_PARSE_* variables.
	# -U: print default usage line
	# -u opts: print usage line
	# -t text: print text
	# -: print from stdin
	local IFS=' ' usage=0
	local i alias desc
	while [ $# -gt 0 ]
	do
		case "$1" in
		-U)
			printf "Usage: ${COLOR_BOLD}%s${COLOR_RESET}" "$SCRIPT_NAME"
			[ "${#ARG_PARSE_OPTS[@]}" -eq 0 ] || printf ' [ options ]'
			local optional=F partial=''
			alias=''
			for i in "${ARG_PARSE_REST[@]}"
			do
				case "$i" in
				--) break;;
				--partial) partial=${partial:-rest};;
				--partial-var=*) partial=${i#*=};;
				--opt-var=*) alias=${i#*=};;
				-*) ;;
				\?) optional=T;;
				*)
					if is_true "$optional"
					then
						printf ' [%s]' "$i"
					else
						printf ' %s' "$i"
					fi
					;;
				esac
			done
			[ -z "$alias" ] || printf ' %s...' "$alias"
			[ -z "$partial" ] || printf ' [ -- %s ]' "$partial"
			echo
			(( usage+=1 ))
			shift;;
		-u)
			[ "$usage" -gt 0 ] \
				&& printf '      ' \
				|| printf 'Usage:'
			printf " ${COLOR_BOLD}%s${COLOR_RESET} %s\n" "$SCRIPT_NAME" "$2"
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
			die "usage_arg_parse(): unknown option [$1]";;
		esac
	done
	# Print option list
	alias=''
	desc=''
	for i in "${ARG_PARSE_OPTS[@]}"
	do
		case "$i" in
			--desc=*) desc=${i##*=};;
			-*) ;;
			*=*|{*})
				[ -z "$desc" ] || \
					printf "  %-18s %s\n" "$alias" "$desc"
				desc=''
				alias=''
				;;
			*)
				[ -z "$alias" ] || alias+='|'
				[ "${#i}" -eq 1 ] && alias+='-' || alias+='--'
				alias+=$i
				;;
		esac
	done
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
		if [[ "$i" =~ ${func}\s?\(\) && "$i" != *'#'* ]]
		then
			trim | sed -n '/^{/n; /^[^#]/q; s/#\s\?//p'
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

is_main() {
	# Check if current file is being called.
	[[ "$0" == "${BASH_SOURCE[-1]:-}" ]]
}

is_tty() {
	# Are we running in a tty?
	[[ -t 1 ]]
}

HTTP_TOOL=""
_check_http_tool() {
	[ -z "$HTTP_TOOL" ] || return 0 # already configured
	HTTP_TOOL=$(first_match is_executable curl wget)
	log_debug "HTTP tool is $HTTP_TOOL"
}
http_get() {
	# Download using wget or curl
	# $1: URL
	# $2: output file (default to stdout)
	local url=$1
	local output="${2:-}"
	[ -n "$url" ] || die "No URL provided"
	_check_http_tool
	case "$HTTP_TOOL" in
	curl)
		local opts=(--show-error --fail --location)
		[ -z "$output" ] || opts+=(-o "$output")
		if (( VERBOSE_MODE > 1 ))
		then
			opts+=(--verbose)
		else
			(( VERBOSE_MODE )) || opts+=(--silent)
		fi
		log_cmd_debug curl "${opts[@]}" "$url";;
	wget)
		local opts=(--no-cache)
		[ -z "$output" ] && opts+=(-O -) || opts+=("--output-document=$output")
		if (( VERBOSE_MODE > 1 ))
		then
			opts+=(--verbose)
		else
			(( VERBOSE_MODE )) || opts+=(--quiet)
		fi
		log_cmd_debug wget "${opts[@]}" "$url";;
	*) die "HTTP_TOOL is not set";;
	esac
}

declare -i JOBS_PARALLELISM
declare -i JOBS_FAIL JOBS_SUCCESS
declare -a JOBS_PIDS
init_jobs() {
	# Initialize parallel job controls.
	# usage: [ options ]
	# --parallelism|-p: set parallelism to N (default: processor count)
	# sets JOBS_PARALLELISM, JOBS_PIDS, JOBS_FAIL, JOBS_SUCCESS
	JOBS_PIDS=()
	JOBS_FAIL=0
	JOBS_SUCCESS=0
	eval $(arg_eval parallelism p JOBS_PARALLELISM=:val)
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
	JOBS_PIDS=("${running[@]}")
	return $failed
}
finish_jobs() {
	# Wait for all jobs to finish.
	while [ ${#JOBS_PIDS[@]} -gt 0 ]
	do
		sleep 0.1
		check_jobs || true
	done
	quiet jobs
	log_debug "  $JOBS_SUCCESS jobs finished"
	[ "$JOBS_FAIL" -eq 0 ] || log_debug "  $JOBS_FAIL jobs failed"
	log_debug "Finishing all jobs"
	wait || (( ++JOBS_FAIL ))
	return $JOBS_FAIL
}
spawn() {
	# Start a job.
	# usage: [ options -- ] command [args]
	# -i: don't disable input
	local ret=0 _input=N
	eval $(arg_eval --opt-break \
		i _input=Y \
	)
	[ "$1" != '--' ] || shift
	# throttle
	while [ ${#JOBS_PIDS[@]} -ge "$JOBS_PARALLELISM" ]
	do
		sleep 0.1
		check_jobs || (( ret += $? ))
	done
	quiet jobs
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
	JOBS_PIDS+=("$pid")
	log_debug " job $pid started"
	return $ret
}

retry() {
	# Retry a command until success or timeout.
	# usage: [ options ] -- command
	# --count: N tries
	# --timeout: N seconds
	# --interval: seconds between tries (default: 1)
	# --backoff: interval multiplier (backoff: 1)
	local -i n=0 max_tries=2147483648
	local -i now timeout=2147483648
	local interval=1 backoff=1
	printf -v now '%(%s)T'
	eval $(arg_eval --partial \
		n count max_tries=:val \
		t timeout '{ (( timeout = :val + now )); }' \
		i interval =:val \
		backoff =:val \
	)
	[ "$1" == '--' ] && shift
	until "$@"
	do
		(( ++n <= max_tries )) || return 1
		printf -v now '%(%s)T'
		(( timeout > now )) || return 2
		log_debug "retry in ${interval}s ($n)"
		sleep "$interval"
		interval=$(bc <<< "$interval * $backoff")
	done
}

lock_file() {
	# Lock a file.
	# Creates a file with PID written inside it.
	local lock=$1
	if check_unlocked "$lock" >/dev/null && (
		set -o noclobber
		echo "$SCRIPT_PID" > "$lock"
	)
	then
		sync
		return 0
	else
		log_debug "Failed to acquire lock on $lock"
		return 1
	fi
}
unlock_file() {
	# Unlock a previously locked file.
	local lock=$1
	local pid="$(cat "$lock" 2>/dev/null || true)"
	[ "$pid" -eq "$SCRIPT_PID" ] || die "Locked owned by $pid"
	rm -f "$lock"
	sync
}
check_unlocked() {
	# Checks whether a file is unlocked.
	# Prints the owner PID to stdout if locked.
	local lock=$1
	local pid="$(cat "$lock" 2>/dev/null || true)"
	if [ -n "$pid" ] && kill -0 "$pid"
	then
		echo "$pid"
		return 1
	fi
	rm -f "$lock"
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
# Color
if has_var COLOR_MODE
then
	is_true "$COLOR_MODE" && color_enable || color_disable
else
	is_tty && color_enable || color_disable
fi
# Batch
if ! has_var BATCH_MODE
then
	[[ -t 0 || -p /dev/stdin ]] && BATCH_MODE=0 || BATCH_MODE=1
fi
# Log redirection
exec 3>&1

trap_default
strict

[[ "$BASH" == *bash ]] || die "You're not using bash"
(( "${BASH_VERSINFO[0]}" >= 4 )) || log_warn "Minimum requirement for bashf is bash 4"
is_executable realpath || die "realpath is missing"

# Set variables
SCRIPT_USER="${USER:-${USERNAME:-}}"
has_val SCRIPT_USER || SCRIPT_USER="$(id -un)"
printf -v SCRIPT_TIMESTAMP '%(%Y%m%d_%H%M%S)T'
readonly SCRIPT_USER SCRIPT_TIMESTAMP
readonly SCRIPT_WORK_DIR=$PWD
SCRIPT_NAME=${0#-*}
readonly SCRIPT_DIR="$(realpath "$(dirname "$SCRIPT_NAME")")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_NAME")"
readonly SCRIPT_PID=$$
TMPDIR=${TMPDIR:-/tmp}

has_val HOSTNAME || HOSTNAME="$(hostname)"
has_val OSTYPE || OSTYPE="$(uname)"

# Default usage definition
if ! is_executable usage
then
	function usage() {
		if [[ "$SCRIPT_NAME" == bash ]]
		then
			usage_arg_parse -u 'bashf.sh' -t 'Interactive mode'
			return
		fi
		# quit when found a non-comment line
		# and strip comment character
		sed '/^[^#]/Q; /^$/Q; /^#!/d; s/^#\s\?//' "$SCRIPT_DIR/$SCRIPT_NAME" \
			| usage_arg_parse -U -
	}
fi

# Check environment
case "$SCRIPT_NAME" in
bashf.sh)
	# Executed from console
	is_main # assert
	arg_parse_reset default
	declare FILTER=''
	ARG_PARSE_OPTS+=(filter f --desc='Filter functions' FILTER=:val)
	arg_parse "$@"
	if [ -z "$FILTER" ]
	then
		log_info "List all functions"
	else
		log_info "Help for ($FILTER)"
	fi
	log_var "Script" "$0"
	_read_functions_from_file "$0" | \
	while readline f
	do
		[ -z "$FILTER" ] || [[ "$f" == $FILTER* ]] || continue
		func=${f%:*}
		line=${f#*:}
		printf "%s ${COLOR_DIM}(%d)${COLOR_RESET}\n" "$func" "$line"
		[ -z "$FILTER" ] || read_function_help "$func" < "$0" | indent '  '
	done | pager
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
