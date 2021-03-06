bashf
=====

A collection of scripts to make ease writing other bash scripts.

	source bashf.sh || exit 1

Installation
------------

Just add `bashf.sh` to your `PATH` environment.
You can copy it to `/usr/local/bin` for example.

	# Simple installation
	curl -o bashf.sh https://raw.githubusercontent.com/kmagusiak/bashf/master/bashf.sh
	chmod a+x bashf.sh
	sudo cp bashf.sh /usr/local/bin

Features
--------

*Logging* is provided by multiple log functions.
Some other functions exist to manipulate the output.
All the logs are written to stderr.

*Checking* of variables can be done by utility functions.
A `die` function is available to exit with a message.
Strict mode is enabled and traps are handled by this script.

	log_section 'My section'
	log_var 'Message' "value"
	log_var TMPDIR
	OPTS=(1 2 3)
	log_var OPTS | indent_block
	has_flag STOP || log_info 'Hello world'
	is_number 5 || die '5 is not a number'

*Input* can be gathered from the user by `prompt`ing them,
waiting for confirmations or waiting for actions.

	prompt reply
	prompt some_var --text 'Enter value' -d 'default'
	wait_user_input
	prompt secret -s
	confirm "Are you sure?"
	prompt_choice reply -- hello world '|empty' 'val|The value val'

*Various* helper functions are provided to ease scripting.
The main one is `arg_parse` and related functions that help parsing script
options.
Also functions for managing execution and parallel jobs.

	local flag=F test='' rest=()
	eval $(arg_eval \
		f flag =T \
		test =:val \
		--opt-var=rest \
	)
	
	arg_parse_reset default
	ARG_PARSE_OPTS+=(
		flag f --desc='Flag option' flag=1
		test --desc='Test option' =:val
		ls --desc='Execute ls now' '{ ls; }'
	)
	ARG_PARSE_REST=(--opt-var=rest --partial)
	usage
	
	quiet noisy_command
	quiet_err grep something maybe_a_file
	exec_in /tmp ls
	retry -n 3 -- curl xxx
	
	(
		# run parallel jobs in a sub-shell
		init_jobs
		spawn sleep 5
		spawn sleep 10
		finish_jobs
	)

Defaults
--------

bashf will be sourced only once.
When you do it, some variables are defined that describe your script.
An `usage` function will automatically be defined for your script.
*Strict mode* is enabled when sourcing as well as a default trap function.

Best practices
--------------

- Enable strict mode.
- Double quote `$`.
- Use `local` variables.
- Use variable substitution before `tr`, `sed`, etc.
- Use `$(xx)` for sub-shells (no backquotes).
- Remove `function` keyword.
- Prefer `[[ ]]` for tests and `(( ))` for arithmetic.
- Write in style: `my_expected_status || action`.
