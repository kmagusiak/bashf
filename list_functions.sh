#!/bin/bash
# List functions defined in a bash file.
# Takes file name as argument.
source ./bashf.sh || exit 1

log_start "$@"

function show_file_functions() {
	local file="$1"
	log_info "Listing functions of $file"
	(grep -n '^\(function \)\?[a-z]\w*()' "$file" || true) |
		sed 's/^\([0-9]\+\):\(function\s*\)\?\([a-z]\w*\)().*$/\3:\1/' |
		sort | indent
}

function arg_show_file() {
	show_file_functions "$1"
	return 1
}
[ $# -eq 0 ] && die_usage "No parameters provided"
parse_args arg_show_file "$@"
log_debug "Finished."
