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
	if ("$@")
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
