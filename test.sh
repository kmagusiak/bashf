#!/bin/bash
# Test suite for bashf.sh
# arg must be 'run' to execute.

# try sourcing locally first
source ./bashf.sh || source bashf.sh || exit 1

TEST_SUCCESS=0
TEST_TOTAL=0
function run_test() {
	local name="$1"
	log_info "Test: $name"
	local out=
	if ("$@" < /dev/null)
	then
		TEST_SUCCESS=$(($TEST_SUCCESS + 1))
	else
		log_error "Failed [$1]"
	fi
	TEST_TOTAL=$(($TEST_TOTAL + 1))
}
function run_all_tests() {
	log_info "Run all tests..."
	local name=
	for name in $(compgen -A function | grep '^tc_')
	do
		run_test "$name"
	done
}

# ---------------------------------------------------------
# Prefix: tc_

# Output

function tc__is_bashf() {
	has_val BASHF
	[[ $- == *e* ]] # strict mode
	[ "$VERBOSE_MODE" == N ]
	[ "$BATCH_MODE" == N ]
}
function tc_vars() {
	local v=
	for v in CURRENT_USER CURRENT_DIR EDITOR HOSTNAME \
		OSTYPE PAGER SCRIPT_DIR SCRIPT_NAME TIMESTAMP \
		TMP_DIR
	do
		log_var "$v"
	done
}

function tc_log_stderr() {
	local chars=
	# make sure output is on stderr
	local chars=$(log_info 'test' 2>/dev/null | wc -c)
	[ "$chars" == 0 ]
	local chars=$(log_section 'test' 2>/dev/null | wc -c)
	[ "$chars" == 0 ]
}
function tc_log_debug() {
	local chars=
	chars=$(log_debug Nothing 2>&1)
	[ "$chars" == 0 ]
	VERBOSE_MODE=Y
	chars=$(log_debug Something 2>&1)
	[ "$chars" != 0 ]
}
function tc_log_var() {
	local abc=123 und=
	log_var abc
	log_var und
	log_var und "(nothing)"
}
function tc_log_cmd() {
	local out="$(log_cmd echo "Hello world" 2>&1)"
	echo "$out"
	[ $(wc -l <<< "$out") == 2 ]
}
function tc_log_status() {
	log_status "My text" -- true
	log_status "Nope" -- false
}
function tc_log_redirect() {
	local fn="$TMP_DIR/.$$_test"
	trap _on_exit_callback EXIT
	log_redirect_to "$fn"
	log_info OK
	[ $(wc -l "$fn") == 2 ]
	rm -f "$fn"
	log_info "Redrect finished."
}
function tc_indent() {
	indent <<< "Indented!"
	indent '-- ' <<< "Dash indent"
	indent_block <<< "Block" >/dev/null
}
function tc_color() {
	is_true COLOR_MODE
	echo "${COLOR_RED}Is this red?${COLOR_RESET}"
	echo -n "--${COLOR_RED}r${COLOR_GREEN}g${COLOR_BLUE}b"
	echo -n "  ${COLOR_CYAN}c${COLOR_MAGENTA}m${COLOR_YELLOW}y${COLOR_GRAY}k"
	echo "${COLOR_RESET}--"
	echo -n " ${COLOR_RED}red${COLOR_DEFAULT} ${COLOR_UNDERLINE}uu"
	echo " ${COLOR_BOLD}yes ${COLOR_REVERSE}reverse${COLOR_RESET}"
	color_disable
	echo "${COLOR_RED}Still normal text...${COLOR_RESET}"
	color_enable
}

# Checks

function tc_executable() {
	is_executable "$SHELL"
	! is_executable not_existing_command_test
}
function tc_has_var() {
	local hasit=x hasnothing=
	has_var hasit
	has_var hasnothing
	has_var TEST_FAILED
	! has_var not_existing_variable
}
function tc_has_var() {
	local hasit=x hasnothing=
	has_val hasit
	! has_val hasnothing
}
function tc_is_true() {
	local t=True f=False y=y Y=Y
	is_true t
	is_true y
	is_true Y
	! is_true f
	local some_ok=yes some_ko=no
	is_true some_ok
	! is_true some_ko
}
function tc_is_integer() {
	is_integer 153
	is_integer 0
	! is_integer 15d
	! is_integer Hello
	! is_integer 15.2
	! is_integer '15 2'
	! is_integer ""
}
function tc_is_number() {
	is_number 153
	is_number 0
	is_number 15.2
	is_number -0.3
	! is_number 15d
	! is_number Hello
	! is_number '15 2'
	! is_number ""
}
function tc_has_env() {
	! has_env TEST_FAILED
	has_env PATH
}

function tc_arg_index() {
	local i
	i=$(arg_index ok hokey none ok any)
	[ "$i" == 2 ]
	! arg_index ok ko
}
function tc_test_first_match() {
	local v="$(test_first_match -d /non-existing "$TMP_DIR" /)"
	[ "$v" == "$TMP_DIR" ]
	! test_first_match -f non_existing file
}

function tc_strictness() {
	non_strict
	false
	strict
	[[ $- == *e* ]]
}
function tc_stacktrace() {
	[ $(stacktrace | wc -l) -gt 2 ]
	[ $(stacktrace short | wc -l) -eq 1 ]
	stacktrace short 1 && echo
}
function tc_trap_add() {
	trap_add 'echo Line: $BASH_LINENO'
	log_info "Running..."
}
function tc_die() {
	(die "OK test") || true
}
function tc_die_ret() {
	local r
	(die_return 5 "OK test") || r=$?
	[[ "$r" == 5 ]]
}

# Input

function tc_prompt() {
	BATCH_MODE=Y
	local var
	prompt var 'Input' no
	[ "$var" == no ]
	prompt var 'Input' pass -s
	[ "$var" == pass ]
}
function tc_prompti() {
	BATCH_MODE=N
	local var
	prompt var <<< "oki"
	[ "$var" == "oki" ]
}
function tc_prompt_special_chars() {
	BATCH_MODE=Y
	local var
	prompt var '' "Hello\"'..."
	[ "$var" == 'Hello"'"'..." ]
}

function tc_confirm() {
	BATCH_MODE=Y
	confirm 'OK?' Y
	! confirm '' n
}
function tc_confirmi() {
	BATCH_MODE=N
	confirm <<< "yes"
	! confirm "Fail" <<< "0"
}
function tc_confirmi_invalid_value() {
	BATCH_MODE=N
	confirm <<< "
	hello
	yes"
}

function tc_prompt_choice() {
	BATCH_MODE=Y
	local var
	prompt_choice var 'Menu' 'menu2' -- \
		menu1 menu2 "hello world"
	[ "$var" == "menu2" ]
}
function tc_prompti_choice() {
	BATCH_MODE=N
	local var
	prompt_choice var 'Menu' -- \
		menu1 menu2 "hello world" <<< "3"
	echo
	[ "$var" == "hello world" ]
}
function tc_prompti_choice_invalid_value() {
	BATCH_MODE=N
	local var
	prompt_choice var 'Menu' -- \
		menu1 menu2 "hello world" <<< "
	5
	2"
	echo
	[ "$var" == "menu2" ]
}

function tc_prompt_menu() {
	BATCH_MODE=Y
	menu_loop -- 'true: OK' 'is_true BATCH_MODE: Check batch' true
}

function tc_wait_user_input() {
	BATCH_MODE=Y
	wait_user_input
}
function tc_wait_user_input_no() {
	BATCH_MODE=N
	! wait_user_input <<< "N"
	echo
}

function tc_wait_countdown() {
	wait_countdown 2 &
	local st=$SECONDS
	wait
	[ $(( ${SECONDS}-st )) == 2 ]
}

# Various

test_aopt=''
test_vopt=''
test_rest_opt=''
function test_arg_parser() {
	case "$1" in
	-a)
		test_aopt=Y
		return 1;;
	-v)
		test_vopt="$2"
		return 2;;
	-*)
		return;;
	*)
		test_rest_opt="$*"
		return $#;;
	esac
}
function tc_parse_args() {
	parse_args test_arg_parser -a -v xx
	[ "$test_vopt" == xx ]
	[ "$test_aopt" == Y ]
}
function tc_parse_args_at_least_one() {
	parse_args -n -f test_arg_parser -a OK
	! (parse_args -n test_arg_parser "$@" 2>/dev/null)
}
function tc_parse_args_files() {
	parse_args -f test_arg_parser ok
	[ "$test_rest_opt" == ok ]
}
function tc_parse_args_rest() {
	test_rest_opt=''
	parse_args -v test_rest_opt test_arg_parser \
		-- hello world
	[ "${#test_rest_opt[@]}" == 2 ]
}
function tc_parse_args_special() {
	VERBOSE_MODE=N
	color_enable
	parse_args test_arg_parser --no-color --verbose
	is_true COLOR_MODE
	color_enable
	[ "$VERBOSE_MODE" == Y ]
	VERBOSE_MODE=N
}
function tc_parse_args_help() {
	(parse_args test_arg_parser --help)
}

function tc_wait_until() {
	local st=$SECONDS
	wait_until 5 true
	[ $(( ${SECONDS}-st )) == 0 ]
	! wait_until 2 false
	[ $(( ${SECONDS}-st )) == 2 ]
}

# ---------------------------------------------------------
[[ "${1:-}" == run ]] || die_usage "Pass 'run' as a parameter"
log_start "$@"

# Tests
run_all_tests

log_section "Summary"
TEST_FAILED=$(($TEST_TOTAL - $TEST_SUCCESS))
log_var "Success" "$TEST_SUCCESS"
log_var "Total" "$TEST_TOTAL"
[ "$TEST_FAILED" -eq 0 ] || die "Failures detected"
