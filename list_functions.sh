#!/bin/bash
# List functions defined in a bash file.
# Takes file name as argument.

# try sourcing locally first
source ./bashf.sh || source bashf.sh || exit 1

function show_file_functions() {
	local file="$1"
	[ -r "$file" ] || die "Cannot read file [$file]"
	log_info "Listing functions of $file"
	(grep -n '^\(function \)\?[a-z]\w*()' "$file" || true) |
		sed 's/^\([0-9]\+\):\(function\s*\)\?\([a-z]\w*\)().*$/\3:\1/' |
		sort | indent
}

function arg_show_file() {
	! show_file_functions "$1"
}

log_start "$@"
parse_args -a -n arg_show_file "$@"
log_debug "Finished."
