#!/bin/bash
# Test suite for bashf.sh
# options must be 'run' to execute.

# source locally
source ./bashf.sh || exit 1

declare -i TEST_SUCCESS=0
declare -i TEST_TOTAL=0
run_test() {
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
	if (( ret == expected ))
	then
		(( ++TEST_SUCCESS ))
	else
		log_error "Failed [$name]: $ret"
	fi
}
run_all_tests() {
	log_info "Run all tests..."
	local name=
	for name in $(compgen -A function | grep '^tc_' | sort)
	do
		run_test 0 "$name"
	done
}

# ---------------------------------------------------------
# Prefix: tc_ for test cases

# Output

tc__is_bashf() {
	has_val BASHF
	[[ $- == *e* ]] # strict mode
	(( VERBOSE_MODE == 0 ))
	[[ "$BATCH_MODE" == N ]]
}
tc_vars() {
	local v=
	for v in SCRIPT_USER SCRIPT_WORK_DIR HOSTNAME OSTYPE \
		SCRIPT_DIR SCRIPT_NAME TIMESTAMP TMPDIR
	do
		log_var "$v"
	done
}

tc_log_debug() {
	local chars=
	chars=$(log_debug Nothing 2>&1)
	[ "$chars" == 0 ]
	VERBOSE_MODE=1
	chars=$(log_debug Something 2>&1)
	[ "$chars" != 0 ]
}
tc_log_var() {
	local abc=123 uninit
	log_var abc
	log_var und
	log_var und "(nothing)"
	log_var uninit
}
tc_log_var_array() {
	local abc=(a b c) empty=()
	log_var abc
	log_var empty
	log_var undef
	local -A m=([x]=1)
	log_var m
}
tc_log_cmd() {
	local out="$(log_cmd echo "Hello world" 2>&1)"
	echo "$out"
	[ $(wc -l <<< "$out") == 2 ]
}
tc_log_status() {
	log_status "My text" -- true
	log_status "Nope" -- false
}
tc_log_redirect() {
	local fn="$TMPDIR/.$$_test"
	trap _on_exit_callback EXIT
	log_redirect_to "$fn"
	log_info OK
	[ $(wc -l "$fn") == 2 ]
	rm -f "$fn"
	log_info "Redirect finished."
}
tc_indent() {
	indent <<< "Indented!"
	indent '-- ' <<< "Dash indent"
	indent_block <<< "Block" >/dev/null
}
tc_trim() {
	local v
	v="$(trim <<< " ok ")"
	[ "$v" == "ok" ]
	v="$(rtrim <<< " ok ")"
	[ "$v" == " ok" ]
}
tc_color() {
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

tc_executable() {
	is_executable "$SHELL"
	! is_executable not_existing_command_test
}
tc_has_var() {
	local hasit=x hasnothing=
	has_var hasit
	has_var hasnothing
	has_var TEST_FAILED
	! has_var not_existing_variable
}
tc_has_var() {
	local hasit=x hasnothing=
	has_val hasit
	! has_val hasnothing
}
tc_is_true() {
	is_true True
	is_true y
	is_true Y
	! is_true False
	is_true yes
	! is_true no
}
tc_is_integer() {
	is_integer 153
	is_integer 0
	! is_integer 15d
	! is_integer Hello
	! is_integer 15.2
	! is_integer '15 2'
	! is_integer ""
}
tc_is_number() {
	is_number 153
	is_number 0
	is_number 15.2
	is_number -0.3
	! is_number 15d
	! is_number Hello
	! is_number '15 2'
	! is_number ""
}
tc_has_env() {
	! has_env TEST_FAILED
	has_env PATH
}

tc_arg_index() {
	local i
	i=$(arg_index ok hokey none ok any)
	(( i == 2 ))
	! arg_index ok ko
}
tc_test_first_match() {
	local v="$(test_first_match -d /non-existing "$TMPDIR" /)"
	[ "$v" == "$TMPDIR" ]
	! test_first_match -f non_existing file
}

tc_strictness() {
	non_strict
	false
	strict
	[[ $- == *e* ]]
}
tc_strictness_subshell() {
	local r
	strict
	(
		false
	) || r=$?
	(( r == 1 ))
}
tc_stacktrace() {
	[ $(stacktrace | wc -l) -gt 2 ]
	[ $(stacktrace short | wc -l) -eq 1 ]
	stacktrace short 1 && echo
}
tc_trap_add() {
	trap_add 'echo Line: $BASH_LINENO'
	log_info "Running..."
}
tc_die() {
	(die "OK test") || true
}
tc_die_ret() {
	local r
	(die_return 5 "OK test") || r=$?
	(( r == 5 ))
}

# Input

tc_prompt() {
	BATCH_MODE=Y
	local var
	prompt var -t 'Input' -d no
	[ "$var" == no ]
	prompt var -t 'Input' -d pass -s
	[ "$var" == pass ]
}
tc_prompti() {
	BATCH_MODE=N
	local var
	prompt var <<< "oki"
	[ "$var" == "oki" ]
}
tc_prompt_special_chars() {
	BATCH_MODE=Y
	local var
	prompt var -d "Hello\"'..."
	[ "$var" == "Hello\"'..." ]
}

tc_confirm() {
	BATCH_MODE=Y
	confirm 'OK?' -d Y
	! confirm -d n
}
tc_confirmi() {
	BATCH_MODE=N
	confirm <<< "yes"
	! confirm "Fail" <<< "0"
}
tc_confirmi_invalid_value() {
	BATCH_MODE=N
	confirm <<< "
	hello
	yes"
}

tc_prompt_choice() {
	BATCH_MODE=Y
	local var
	prompt_choice var -t 'Menu' -d 'menu2' -- \
		menu1 menu2 "hello world"
	[ "$var" == "menu2" ]
}
tc_prompti_choice() {
	BATCH_MODE=N
	local var
	prompt_choice var -t 'Menu' -- \
		menu1 menu2 "hello world" <<< "3"
	echo
	[ "$var" == "hello world" ]
}
tc_prompti_choice_invalid_value() {
	BATCH_MODE=N
	local var
	prompt_choice var -t 'Menu' -- \
		menu1 menu2 "hello world" <<< "
	5
	2"
	echo
	[ "$var" == "menu2" ]
}
tc_prompt_choice_val() {
	BATCH_MODE=Y
	local var
	prompt_choice var -d a -- \
		'a|test' b
	[ "$var" == 'a' ]
}
tc_prompti_choice_val() {
	BATCH_MODE=N
	local var
	prompt_choice var -- \
		'a|test' b <<< "1"
	[ "$var" == 'a' ]
}

tc_prompt_menu() {
	BATCH_MODE=Y
	menu_loop -- 'true| OK' 'is_true \"\$BATCH_MODE\"| Check batch' true
}

tc_wait_user_input() {
	BATCH_MODE=Y
	wait_user_input
}
tc_wait_user_input_no() {
	BATCH_MODE=N
	! wait_user_input <<< "N"
	echo >&2
}

# Various

tc_arg_eval() {
	local xx
	set -- --xx
	eval $(arg_eval xx=T)
	is_true "$xx"
}
tc_arg_eval_alias() {
	local xx
	set -- --zz
	eval $(arg_eval zz xx=T)
	is_true "$xx"
}
tc_arg_eval_alias_short() {
	local xx
	set -- -z
	eval $(arg_eval z zz xx=T)
	is_true "$xx"
}
tc_arg_eval_block() {
	local xx
	set -- --xx
	eval $(arg_eval xx '{ xx=$(echo a); }')
	[ "$xx" == 'a' ]
}
tc_arg_eval_val() {
	local xx='' yy=''
	set -- --xx nothing --yes
	eval $(arg_eval xx=:val yes yy=T)
	[ "$xx" == 'nothing' ]
	is_true "$yy"
}
tc_arg_eval_val_next() {
	local xx='' yy=''
	set -- --xx --yes
	eval $(arg_eval xx=:val yes yy=T)
	[ "$xx" == '--yes' ]
	! is_true "$yy"
}
tc_arg_eval_val_missing() {
	local xx='ok' r
	set -- --xx
	(
		eval $(arg_eval xx=:val yes yy=T)
	) || r=$?
	(( r > 0 ))
	[ "$xx" == 'ok' ]
}
tc_arg_eval_equal() {
	local xx=''
	set -- --xx=nothing
	eval $(arg_eval xx=:val)
	[ "$xx" == 'nothing' ]
}
tc_arg_eval_multi_short() {
	local xx yy
	set -- -xy=test
	eval $(arg_eval x xx=1 y yy=:val)
	[ "$xx" == '1' ]
	[ "$yy" == 'test' ]
}
tc_arg_eval_partial() {
	local xx
	set -- --xx -- ok
	eval $(arg_eval xx=T --partial)
	[ "$1" == '--' ]
	[ "$2" == 'ok' ]
}
tc_arg_eval_opt_var() {
	local xx rr=()
	set -- --xx ok abc
	eval $(arg_eval xx=T --opt-var=rr)
	[ "${rr[0]}" == 'ok' ]
	[ ${#rr[@]} -eq 2 ]
}
tc_arg_eval_opt_var_partial() {
	local xx rr=()
	set -- --xx ok abc -- rest
	eval $(arg_eval xx=T --opt-var=rr --partial)
	[ ${#rr[@]} -eq 2 ]
	[ "$2" == 'rest' ]
}
tc_arg_eval_opt_break() {
	local xx yy=F
	set -- --xx ok --yy
	eval $(arg_eval xx=T yy=T --opt-break)
	[ "$1" == "ok" ]
	! is_true "$yy"
}

tc_arg_eval_named() {
	local a b=none
	set -- ok
	eval $(arg_eval_named a ? b)
	[ "$a" == ok ]
	[ "$b" == none ]
	set -- ok ko
	eval $(arg_eval_named a ? b)
	[ "$b" == ko ]
}
tc_arg_eval_named_missing(){
	local r a b
	(
		set -- ok
		eval $(arg_eval_named a b)
	) || r=$?
	(( r > 0 ))
}
tc_arg_eval_named_too_much_args(){
	local r a b
	(
		set -- ok ok ok
		eval $(arg_eval_named a b)
	) || r=$?
	(( r > 0 ))
}
tc_arg_eval_named_partial() {
	local r a='' b='' c=''
	(
		set -- a b c
		eval $(arg_eval_named a b --partial)
		[ -z "$c" ]
		[ -n "$1" ]
	)
}

tc_arg_eval_rest() {
	local a=()
	set -- a b -- ok
	eval $(arg_eval_rest a --partial)
	[[ ${#a[@]} -eq 2 && "${a[0]}" == 'a' ]]
	[ $# -eq 1 ] && [ "$1" == 'ok' ]
}
tc_arg_eval_rest_empty() {
	local a=()
	set --
	eval $(arg_eval_rest a)
}
tc_arg_eval_rest_empty_partial() {
	local a=()
	set -- -- ok
	eval $(arg_eval_rest a --partial)
	[ $# -eq 1 ] && [ "$1" == 'ok' ]
}
tc_arg_eval_rest_only_opts() {
	local a=()
	set -- a b
	eval $(arg_eval_rest a)
	[[ ${#a[@]} -eq 2 && "${a[0]}" == 'a' ]]
	[ $# -eq 0 ]
}

test_arg_parse() {
	test_aopt=''
	test_fopt=''
	test_vopt=''
	test_rest_opt=()
	arg_parse_reset
	arg_parse_opt a 'Command' test_aopt=Y
	arg_parse_opt f 'Flag' -v test_fopt -f
	arg_parse_opt v 'Variable' -v test_vopt -r
	arg_parse_rest -- test_rest_opt
}
tc_arg_parse() {
	test_arg_parse
	arg_parse -a -v xx
	[ "$test_vopt" == xx ]
	[ "$test_aopt" == Y ]
	arg_parse -a OK
	[ "${test_rest_opt[0]}" == OK ]
}
tc_arg_parse_at_least_one() {
	local myval
	test_arg_parse
	arg_parse
	[ ${#test_rest_opt[@]} -eq 0 ]
	arg_parse_rest myval
	arg_parse ok
	! ( arg_parse ) &> /dev/null
}
tc_arg_parse_rest() {
	test_arg_parse
	arg_parse hello world
	[ "${#test_rest_opt[@]}" == 2 ]
	test_rest_opt=''
	local other=()
	arg_parse_rest -- test_rest_opt other
	arg_parse abc -- hello world
	[ "${test_rest_opt[0]}" == abc ]
	[ "${#other[@]}" == 2 ]
}
tc_arg_parse_rest_named() {
	test_arg_parse
	local a b
	arg_parse_rest a b -- test_rest_opt
	arg_parse oka okb hello world
	[ "${#test_rest_opt[@]}" == 2 ]
	[ "$a" == oka ]
	[ "$b" == okb ]
}
tc_arg_parse_special() {
	arg_parse_reset default
	VERBOSE_MODE=0
	color_enable
	arg_parse --no-color --verbose
	is_true "$COLOR_MODE"
	color_enable
	(( VERBOSE_MODE > 0 ))
	VERBOSE_MODE=1
}
tc_arg_parse_help() {
	arg_parse_reset default
	(arg_parse --help)
}

tc_wait_until() {
	local st=$SECONDS end
	wait_until -t 5 -- true
	[[ $(( ${SECONDS}-st )) == 0 ]]
	! wait_until -t 2 -i 0.5 -- false
	# may be 3 seconds because of timing delays
	end=$SECONDS
	(( end - st == 2 || end - st == 3 ))
}

tc_parallel() {
	(
		init_jobs
		for i in {1..10}
		do
			spawn sleep 0.2
		done
		finish_jobs
	)
}

# ---------------------------------------------------------
main() {
	[[ "${1:-}" == "run" ]] || die_usage "Pass 'run' as a parameter"
	# Run
	run_all_tests
	# Results
	log_section "Summary"
	TEST_FAILED=$(( TEST_TOTAL - TEST_SUCCESS ))
	log_var "Success" "$TEST_SUCCESS"
	log_var "Total" "$TEST_TOTAL"
	(( TEST_FAILED == 0 )) || die "Failures detected"
}
run_main "$@"
