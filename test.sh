#!/bin/bash
# Test suite for bashf.sh
# options must be 'run' to execute.

# source locally
source ./bashf.sh || exit 1

TEST_SUCCESS=0
TEST_TOTAL=0
function run_test() {
	local expected="$1" name="$2" ret
	shift
	log_info "Test: $name"
	if ("$@" < /dev/null)
	then
		ret=0
	else
		ret=$?
	fi
	(( ++TEST_TOTAL ))
	if [ "$ret" -eq "$expected" ]
	then
		(( ++TEST_SUCCESS ))
	else
		log_error "Failed [$name]"
	fi
}
function run_all_tests() {
	log_info "Run all tests..."
	local name=
	for name in $(compgen -A function | grep '^tc_')
	do
		run_test 0 "$name"
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
	for v in CURRENT_USER CURRENT_DIR HOSTNAME OSTYPE \
		SCRIPT_DIR SCRIPT_NAME TIMESTAMP TMP_DIR
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
function tc_log_var_array() {
	local abc=(a b c) empty=()
	log_var_array abc
	log_var_array empty
	log_var_array undef
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
	is_true "$COLOR_MODE"
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
	is_true True
	is_true y
	is_true Y
	! is_true False
	is_true yes
	! is_true no
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
function tc_prompt_choice_val() {
	BATCH_MODE=Y
	local var
	prompt_choice var '' a -- \
		'a|test' b
	[ "$var" == 'a' ]
}
function tc_prompti_choice_val() {
	BATCH_MODE=N
	local var
	prompt_choice var -- \
		'a|test' b <<< "1"
	[ "$var" == 'a' ]
}

function tc_prompt_menu() {
	BATCH_MODE=Y
	menu_loop -- 'true| OK' 'is_true \"\$BATCH_MODE\"| Check batch' true
}

function tc_wait_user_input() {
	BATCH_MODE=Y
	wait_user_input
}
function tc_wait_user_input_no() {
	BATCH_MODE=N
	! wait_user_input <<< "N"
	echo >&2
}

# Various

function test_arg_parse() {
	test_aopt=''
	test_fopt=''
	test_vopt=''
	test_rest_opt=''
	arg_parse_reset
	arg_parse_opt a 'Command' -s a test_aopt=Y
	arg_parse_opt f 'Flag' -s f -v test_fopt -f
	arg_parse_opt v 'Variable' -s v -v test_vopt -r
	arg_parse_rest test_rest_opt
}
function tc_arg_parse() {
	test_arg_parse
	arg_parse -a -v xx
	[ "$test_vopt" == xx ]
	[ "$test_aopt" == Y ]
	arg_parse -a OK
	[ "${test_rest_opt[0]}" == OK ]
}
function tc_arg_parse_at_least_one() {
	test_arg_parse
	arg_parse
	[ ${#test_rest_opt[@]} -eq 0 ]
	arg_parse_require 1
	arg_parse ok
	! ( arg_parse ) 2> /dev/null
}
function tc_arg_parse_rest() {
	test_arg_parse
	arg_parse hello world
	[ "${#test_rest_opt[@]}" == 2 ]
	test_rest_opt=''
	local other=()
	arg_parse_rest test_rest_opt -- other
	arg_parse abc -- hello world
	[ "${test_rest_opt[0]}" == abc ]
	[ "${#other[@]}" == 2 ]
}
function tc_arg_parse_rest_named() {
	test_arg_parse
	local a b c
	arg_parse_rest 2 a b test_rest_opt
	log_var_array ARG_PARSER_OPT
	arg_parse oka okb -- hello world
	[ "${#test_rest_opt[@]}" == 2 ]
	[ "$a" == oka ]
	[ "$b" == okb ]
}
function tc_arg_parse_special() {
	arg_parse_reset default
	VERBOSE_MODE=N
	color_enable
	arg_parse --no-color --verbose
	is_true "$COLOR_MODE"
	color_enable
	[ "$VERBOSE_MODE" == Y ]
	VERBOSE_MODE=N
}
function tc_arg_parse_help() {
	arg_parse_reset default
	(arg_parse --help)
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
TEST_FAILED=$(( TEST_TOTAL - TEST_SUCCESS ))
log_var "Success" "$TEST_SUCCESS"
log_var "Total" "$TEST_TOTAL"
[ "$TEST_FAILED" -eq 0 ] || die "Failures detected"
