#!/usr/bin/env bash
################################################################################
# ConfCan - Monitors file changes within a directory and triggers actions.
# 
# Author:  Dominik D. Geyer <dominik.geyer@gmail.com>
# License: GPLv3 (see LICENSE)
# Version: $VERSION$
################################################################################
set -e

INW=inotifywait
INW_EVENTS="create,close_write,moved_to,move_self,delete"

GIT=git

TIMEOUT=5

################################################################################

usage () {
	cat <<-EOT
		Usage: ${0##*/} [OPTION]... <git-repository>
		
		Options:
		    -v	Be verbose (given multiple times increases verbosity level)

	EOT
}

msg () {
	echo "$@" >&2
}

info () {
	(( VERBOSITY < 1 )) && return
	echo "$@" >&2
}

git_trigger () {
	# stage all changed/new/deleted files
	if ! $GIT add .; then
		msg "WARN: git add failed"
		return 1
	fi
	
	# are there any changes?
	if [[ -n "$($GIT status --porcelain)" ]]; then
		# commit changes (use -a in case something changed since `git add`
		if ! $GIT commit -a -m "Auto commit $(date +'%Y-%m-%d %H:%M:%S')"; then
			msg "WARN: git commit failed"
			return 2
		fi
	else
		msg "Nothing to do... skipping commit!"
	fi
}

cleanup () {
	if [[ -n "$SLEEP_PID" ]] && kill -0 $SLEEP_PID &>/dev/null; then
		msg "CLEANUP: killing $SLEEP_PID"
		kill $SLEEP_PID &>/dev/null
	fi
	exit 0
}

usr_timeout () {
	git_trigger || msg "... something went wrong with git_trigger()"
	
	return 0
}

################################################################################

declare -i VERBOSITY=0

while getopts ":vh" opt; do
	case $opt in
	# be verbose; each -v increases the verbosity level
	v)
		VERBOSITY=$((VERBOSITY + 1))
		;;
	h)
		usage >&2
		exit 0
		;;
	\?)
		msg "Error: Invalid option -$OPTARG"
		usage >&2
		exit 1
		;;
	:)
		msg "Error: Option -$OPTARG requires an argument"
		usage >&2
		exit 1
		;;
	esac
done

shift $((OPTIND-1))		# shift options
unset opt OPTIND		# unset variables used for option parsing

if [[ $# != 1 ]]; then
    usage >&2
    exit 1
fi

REPO_DIR=$(readlink -f "$1") || { msg "Error: Repository does not exist."; exit 1; }
[[ ! -d "$REPO_DIR" ]] && { msg "Error: The repository is not a directory."; exit 1; }
cd "$REPO_DIR" || { msg "Error: Cannot change into repository directory."; exit 1; }

###############################

PID=$$			# this script's PID
SLEEP_PID=      # timeout process's PID

trap "cleanup" EXIT
trap "usr_timeout" SIGUSR1

while read -r line; do
	((++evcount))
	info "NOTIFY $(printf '%05d' $evcount): ${line/$REPO_DIR/GIT_REPO}"
	
	# is there already a timeout process running?
	if [[ -n "$SLEEP_PID" ]] && kill -0 $SLEEP_PID &>/dev/null; then
		# kill it and wait for completion
		kill $SLEEP_PID &>/dev/null || true
		wait $SLEEP_PID &>/dev/null || true
	fi
	
	# start timeout process
	(
		sleep $TIMEOUT
		
		# send signal USR1 to parent
		kill -SIGUSR1 $PID || msg "WARN: Error sending signal USR1 to $PID"
	) &
	SLEEP_PID=$!
done < <($INW -m -r -e $INW_EVENTS "$REPO_DIR" "@${REPO_DIR}/.git" 2>/dev/null)

