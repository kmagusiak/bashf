bashf
=====

A collection of scripts to make ease writing other bash scripts.

	# just define usage and import the script
	function usage() { ... }
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
Also, strict mode can be enabled and EXIT traps handled by this script.

*Input* can be gathered from the user by `prompt`ing them,
waiting for confirmations or waiting for actions.

Defaults
--------

By default, you can source the file only once.
When you do it, some variables are defined that describe your script.
*Stric mode* is enabled when sourcing as well as a default exit trap function.
