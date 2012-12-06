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

cmsg () {
	echo "$@" >&2
}

cinfo () {
	(( VERBOSITY < 1 )) && return
	echo "$@" >&2
}

git_trigger () {
	# stage all changed/new/deleted files
	if ! $GIT add .; then
		cmsg "Warning: git add failed"
		return 1
	fi
	
	# are there any changes?
	if [[ -n "$($GIT status --porcelain)" ]]; then
		# commit changes (use -a in case something changed since `git add`
		if ! $GIT commit -a -m "Auto commit $(date +'%Y-%m-%d %H:%M:%S')"; then
			cmsg "Warning: git commit failed"
			return 2
		fi
	else
		cinfo "Notice: Nothing to do... skipping commit!"
	fi
}

cleanup () {
	timeout_task_stop $TIMEOUT_PID
	
	exit 0	# we need to exit here!
}

# Signal handler for USR1 which triggers an action
usr_timeout () {
	git_trigger || cmsg "Warning: Smething went wrong with git_trigger()"
	
	return 0
}

# Timeout task (which is run in a separate process) and sends signal USR1 to parent
# @param integer Parent process's PID
# @param integer Amount of seconds to wait
timeout_task () {
	local ppid=$1 timeout=$2
	
	# take a nap
	sleep $timeout
	
	# send signal USR1 to parent
	kill -SIGUSR1 $ppid || cmsg "WARN: Error sending signal USR1 to $ppid"
}

# Kills timeout task and waits for its completion
# @param integer PID of timeout process
timeout_task_stop () {
	local tpid=$1
	
	if [[ -n "$tpid" ]] && kill -0 $tpid &>/dev/null; then
		# kill it and wait for completion
		kill $tpid &>/dev/null || true
		wait $tpid &>/dev/null || true
	fi
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
		cmsg "Error: Invalid option -$OPTARG"
		usage >&2
		exit 1
		;;
	:)
		cmsg "Error: Option -$OPTARG requires an argument"
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

# determine realpath of repository, as inotifywait seems not to deal with symlinks
REPO_DIR=$(readlink -f "$1") || { cmsg "Error: Repository does not exist."; exit 1; }

# sanity check: is this a git repository?
[[ -d "$REPO_DIR/.git" ]] || { cmsg "Error: The repository is not a Git repository."; exit 1; }

# chdir into repositoy, as git wants to operate within it's repository
cd "$REPO_DIR" || { cmsg "Error: Cannot change into repository directory."; exit 1; }

################################################################################

PID=$$			# this script's PID
TIMEOUT_PID=      # timeout process's PID

# install signal handlers
trap "cleanup" EXIT
trap "usr_timeout" SIGUSR1

# for each requested inotify event
while read -r line; do
	# new inotify event occured
	((++evcount))
	cinfo "NOTIFY $(printf '%05d' $evcount): ${line/$REPO_DIR/GIT_REPO}"
	
	# are we already waiting to trigger an action? defer action and start timeout over again!
	timeout_task_stop $TIMEOUT_PID
	
	# run timeout task as background process and get its PID
	timeout_task $PID $TIMEOUT &
	TIMEOUT_PID=$!
done < <($INW -m -r -e $INW_EVENTS "$REPO_DIR" "@${REPO_DIR}/.git" 2>/dev/null)

