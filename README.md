bashf
=====

A collection of scripts to make ease writing other bash scripts.

	source bashf.sh || exit 1

Installation
------------

Just add `bashf.sh` to your `PATH` environment.
You can copy it to `/usr/local/bin` for example.

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
	log_var_array OPTS 2>&1 | indent_block >&2
	has_flag STOP || log_info 'Hello world'
	is_number 5 || die '5 is not a number'

*Input* can be gathered from the user by `prompt`ing them,
waiting for confirmations or waiting for actions.

	prompt reply
	prompt some_var 'Enter value' 'default'
	wait_user_input
	prompt secret -s
	confirm "Are you sure?"
	prompt_choice reply -- hello world '|empty' 'val|The value val'

*Various* helper functions are provided to ease scripting.
The main one is `arg_parse` and related functions that help parsing script
options.
Also functions for managing execution and parallel jobs.

	arg_parse_reset default
	arg_parse_opt 'flag' 'Flag option' -s f -v flag -f
	arg_parse_opt 'test' 'Test option' -V -r
	arg_parse_rest -- rest
	usage
	
	quiet noisy_command
	quiet_err grep something maybe_a_file
	exec_in /tmp ls
	
	(
		# run parallel jobs in a sub-shell
		init_jobs
		spawn sleep 5
		spawn sleep 10
		finish_jobs
	)

Defaults
--------

By default, you can source the file only once.
When you do it, some variables are defined that describe your script.
An `usage` function will be automatically built for your script.
*Strict mode* is enabled when sourcing as well as a default trap function.
