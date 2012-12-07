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

################################################################################

usage () {
	cat <<-EOT
		Usage: ${0##*/} [OPTION...] <git-repository>
		
		Options:
		    -t <timeout>
		        Timeout in seconds before action is triggered (Default: 5)
		    -a <directory>
		        Directory (relative) watched by inotifywait and provided to 'git add'
		        (can be specified multiple times; Default: .)
		    -v
		        Be verbose (given multiple times increases verbosity level)
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
	if ! $GIT add -- "${GIT_ADD_DIRS[@]}"; then
		cmsg "Warning: git add failed"
		return 1
	fi
	
	# are there any changes?
	if [[ -n "$($GIT status --porcelain -- "${GIT_ADD_DIRS[@]}")" ]]; then
		# commit staged changes
		if ! $GIT commit -m "Auto commit $(date +'%Y-%m-%d %H:%M:%S')"; then
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

declare -i TIMEOUT=5
declare -a GIT_ADD_DIRS
declare -i VERBOSITY=0

while getopts ":vt:a:h" opt; do
	case $opt in
	# timeout in seconds for timeout task
	t)
		TIMEOUT=$OPTARG
		;;
	# directories to be watched by inotigy and provided to 'git add'
	a)
		GIT_ADD_DIRS+=( "$OPTARG" )
		;;
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

# determine canonical path of repository, as inotifywait seems not to deal with symlinks
REPO_DIR=$(readlink -f "$1") || { cmsg "Error: Repository does not exist."; exit 1; }

# sanity check: is this a git repository?
[[ -d "$REPO_DIR/.git" ]] || { cmsg "Error: The repository is not a Git repository."; exit 1; }

# chdir into repository, as git used to operate within its repository
cd "$REPO_DIR" || { cmsg "Error: Cannot change into repository directory."; exit 1; }


# selective directory watches
if (( ${#GIT_ADD_DIRS[@]} == 0 )); then
	GIT_ADD_DIRS=( "." )	# whole repository as default
fi

declare -a INW_DIRS
for d in "${GIT_ADD_DIRS[@]}"; do
	d="$REPO_DIR/$d"
	[[ -d "$d" ]] || { cmsg "Error: Directory '$d' does not exist."; exit 1; }
	INW_DIRS+=( "$d" )
done
unset d

################################################################################

TIMEOUT_PID=	# timeout process's PID

# install signal handlers
trap "cleanup" EXIT
trap "usr_timeout" SIGUSR1

# for each requested inotify event
while read -r line; do
	# new inotify event occured
	((++evcount))
	cinfo "INOTIFY $(printf '%05d' $evcount): ${line/$REPO_DIR/GIT_REPO}"
	
	# defer action and restart timeout if timeout task is already runnning
	timeout_task_stop $TIMEOUT_PID
	
	# run timeout task as background process and get its PID
	timeout_task $$ $TIMEOUT &
	TIMEOUT_PID=$!
done < <($INW -m -r -e $INW_EVENTS "${INW_DIRS[@]}" "@${REPO_DIR}/.git" 2>/dev/null)

