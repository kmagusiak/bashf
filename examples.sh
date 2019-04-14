#!/bin/bash
# Examples of scripts

# try sourcing locally first
source ./bashf.sh || source bashf.sh || exit 1
# by default
#source bashf.sh || exit 1

log_info "Started $SECONDS ago"
TMOUT=10 # read timeout
wait_user_input

prompt var -d 'aa_test_aa'
log_var var

log_section 'Variable definition'
log_var '+x (is defined)' ${var:+x}
log_var '-x (default)' ${var:-x}

log_section 'Variable manipulation'
log_var "Length" ${#var}
log_var 'First char' "${var:0:1}"
log_var 'Remove leading a' ${var#a}
log_var 'Remove tailing a' ${var%a}
log_var 'Replace a' ${var/a/b}
log_var 'Replace all a' ${var//a/b}

log_section 'Tests'
[ -x "$0" ] && log_info "$0 is executable"
[ 5 -gt 2 ] && log_info '-gt -eq works with numbers'
[ "5" == "5" ] && log_info '== works with strings'
[[ "5" == "5" ]] && log_info '[[ is preferred ]]'
[[ "hello" == he* ]] && log_info '[[ glob matches ]]'
[[ "hello" == he* && -n 'ok' && a < b ]] && log_info '[[ is more powerful ]]'
regex='t..t'
log_var regex
[[ "$var" =~ $regex ]] && log_info "var matched regex" \
	|| log_warn "var not matched regex"
log_var 'First tmp dir' "$(test_first_match -d "$HOME/tmp" /var/tmp /tmp)"

log_section 'Split and join'
prompt version -d '1.2-def'
IFS='.-'
split=($version)
log_var 'Split length' ${#split[@]}
IFS='.'
join=${split[*]}
log_var 'Joined split' "$join"
IFS=' '

log_section 'Math'
line=''
for (( i=0; i<5; i++ ))
do
	line+='-'
done
log_var "loop for $i char" "$line"
(( i*=2 ))
log_var 'i*=2' $i
let i=i+2 # prefer (( ... ))
log_var 'let i=i+2' $i
log_var '$(( i / 2 ))' "$(( i/2 ))"

log_section 'Input'
prompt secret -s
log_var secret
prompt_choice choice -t 'Choose something' -d hello -- \
	hello "$SCRIPT_USER|user" '|Nothing'
log_var choice

log_section 'Usage and parsing arguments'
ARG_PARSE_OPTS+=(
	flag f --desc='Flag option' flag=1
	test --desc='Test option' =:val
)
ARG_PARSE_REST=(--opt-var=rest --partial)
usage
log_debug "Parsing..."
log_var "Arguments" "$(quote "$@")"
arg_parse "$@"
log_var flag
log_var test
log_var rest

log_section 'Jobs (and parallelism)'
wait_user_input
(
	VERBOSE_MODE=1
	init_jobs -p 3
	for i in {1..8}
	do
		spawn sleep 0.$RANDOM
	done
	finish_jobs || log_error "Failed jobs ($?)"
)

log_section 'End'
