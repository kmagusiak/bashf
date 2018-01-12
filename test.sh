#!/bin/bash

function usage() {
	cat <<EOF
Usage: $SCRIPT_NAME run
Test suite for bashf.sh.
EOF
}
source bashf.sh || exit 1

TEST_SUCCESS=0
TEST_TOTAL=0
function run_test() {
	local name="$1"
	log_info "Test: $name"
	local out=
	if ("$@" < /dev/null )
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

function tc_is_bashf() {
	is_true BASHF
	[[ $- == *e* ]]
	! is_verbose
	! is_batch
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
	is_verbose
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
	echo "Is this red?" | color red -
	echo -n "--$(color green)g$(color red)r"
	echo -n "$(color yellow)ee$(color blue)n$(color reset)"
	echo --
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
	(die "Inside test") || true
}
function tc_die_ret() {
	local r
	(die_return 5 "Inside ret") || r=$?
	[[ "$r" == 5 ]]
}

# Input

function tc_batch() {
	BATCH_MODE=abc
	is_batch
	BATCH_MODE=N
	! is_batch
	BATCH_MODE=Y
	is_batch
}

function tc_prompt() {
	BATCH_MODE=Y
	local var
	prompt -v var -d no -p 'Input'
	[ "$var" == no ]
	prompt -v var -d pass -p 'Input' -s
	[ "$var" == pass ]
}
function tc_prompti() {
	BATCH_MODE=N
	local var
	prompt -v var <<< "oki"
	[ "$var" == "oki" ]
}
function tc_prompt_special_chars() {
	BATCH_MODE=Y
	local var
	prompt -v var -d "Hello\"'..."
	[ "$var" == 'Hello"'"'..." ]
}

function tc_confirm() {
	BATCH_MODE=Y
	confirm -p 'OK?' -d 'Y'
	! confirm -d 'n'
}
function tc_confirmi() {
	BATCH_MODE=N
	confirm <<< "yes"
	! confirm -p "Fail" <<< "0"
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
	prompt_choice -v var -p 'Menu' -d 'menu2' -- \
		menu1 menu2 "hello world"
	[ "$var" == "menu2" ]
}
function tc_prompti_choice() {
	BATCH_MODE=N
	local var
	prompt_choice -v var -p 'Menu' -- \
		menu1 menu2 "hello world" <<< "3"
	[ "$var" == "hello world" ]
}
function tc_prompti_choice_invalid_value() {
	BATCH_MODE=N
	local var
	prompt_choice -v var -p 'Menu' -- \
		menu1 menu2 "hello world" <<< "
	5
	2"
	[ "$var" == "menu2" ]
}

function tc_wait_user_input() {
	BATCH_MODE=Y
	wait_user_input
}
function tc_wait_user_input_no() {
	BATCH_MODE=N
	! wait_user_input <<< "N"
}

function tc_wait_countdown() {
	wait_countdown 2 &
	date '+%T init'
	wait
	date '+%T 2s'
}

function tc_wait_until() {
	date '+%T init'
	wait_until 5 true
	date '+%T 0s'
	! wait_until 2 false
	date '+%T 2s'
}

# ---------------------------------------------------------
[[ "${1:-}" == run ]] || die_usage "Pass a parameter"
log_start "$@"

# Tests
run_all_tests

log_section "Summary"
TEST_FAILED=$(($TEST_TOTAL - $TEST_SUCCESS))
log_var "Success" "$TEST_SUCCESS"
log_var "Total" "$TEST_TOTAL"
[ "$TEST_FAILED" -eq 0 ] || die "Failures detected"