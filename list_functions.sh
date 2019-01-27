#!/bin/bash
# List functions defined in a bash file.
# Takes file name as argument.

# try sourcing locally first
source ./bashf.sh || source bashf.sh || exit 1

SHOW_DETAILS=N
FILTER=

function show_file_function() {
	# $1: file
	# $2: function name
	local func=${2%:*}
	local line=${2#*:}
	printf "%s ${COLOR_DIM}(%d)${COLOR_RESET}\n" "$func" "$line"
	if ! has_flag SHOW_DETAILS
	then
		echo "$2"
		return
	fi
	(
		sed -n "/func.*$func\(\)/q"
		# TODO read comments
	) | indent < "$1"
}
function show_file_functions() {
	local file="$1"
	[ -r "$file" ] || die "Cannot read file [$file]"
	log_info "Listing functions of $file"
	local f functions=($(
		(grep -n '^\(function \)\?[a-z]\w*()' "$file" || true) |
		sed 's/^\([0-9]\+\):\(function\s*\)\?\([a-z]\w*\)().*$/\3:\1/' |
		sort
		))
	for f in "${functions[@]}"
	do
		[ -z "$FILTER" ] || [[ "$f" == $FILTER ]] || continue
		show_file_function "$file" "$f"
	done
	return 0
}

log_start "$@"
arg_parse_opt details 'Show documentation' \
	-v SHOW_DETAILS -f
arg_parse_opt filter 'Filter functions' \
	-v FILTER -r -s f
arg_parse_rest files
arg_parse_require 1
arg_parse "$@"
for f in "${files[@]}"
do
	show_file_functions "$f"
done
log_debug "Finished."
