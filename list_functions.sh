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

[ $# -eq 0 ] && die_usage "No parameters provided"
while [ $# -gt 0 ]
do
	case "$1" in
	-h|--help)
		usage
		exit;;
	-*)
		die "Invalid option [$1]"
		;;
	*)
		show_file_functions "$1"
		shift
		;;
	esac
done
log_debug "Finished."
