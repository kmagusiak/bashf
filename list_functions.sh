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

log_start "$@"
arg_parse_rest files
ARG_PARSER_OPT['require']=1
arg_parse "$@"
for f in "${files[@]}"
do
	show_file_functions "$f"
done
log_debug "Finished."
