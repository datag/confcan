#!/usr/bin/env bash
################################################################################
# ConfCan - Monitors file changes within a directory and triggers actions.
# 
# Copyright 2012  Dominik D. Geyer <dominik.geyer@gmail.com>
# License: GPLv3 (see file LICENSE)
################################################################################
set -o errexit -o nounset

INW=inotifywait
GIT=git

################################################################################

usage () {
	cat <<-EOT
		Usage: ${0##*/} [OPTION...] <git-repository>
		
		Options:
		    -t <timeout>      (Default: $TIMEOUT)
		        Timeout in seconds before action is triggered.
		    -a <directory>    (Default: .)
		        Directory (relative) watched by inotifywait and provided to 'git add'.
		        This option can be specified multiple times.
		    -i
		        Initialize Git repository and creates directories specified by '-a'.
		        The base directory must exist.
		    -c
		        Stage and commit all changes before monitoring.
		    -e <events>       (Default: $INW_EVENTS)
		        Comma separated list of events 'inotifywait' should listen to.
		        See man page of 'inotifywait' for available events.
		    -v
		        Be verbose. Verbosity level increases when specified multiple times.
	EOT
}

# Print message out to stderr
cmsg () { echo "$@" >&2; }

# Print error message out to stderr and exit
cerrexit () { echo "$@" >&2; exit 1; }

# Print informational message out to stderr (depending on verbosity level)
cinfo () { (( VERBOSITY > 0 )) && echo "$@" >&2; }

# Git actions
git_trigger () {
	# stage all changed/new/deleted files
	if ! $GIT add --all -- "${GIT_ADD_DIRS[@]}"; then
		cmsg "Warning: git add failed."
		return 1
	fi
	
	# are there any changes?
	if [[ -n "$($GIT status --porcelain -- "${GIT_ADD_DIRS[@]}")" ]]; then
		# commit staged changes
		if ! $GIT commit --message "Auto commit $(date +'%Y-%m-%d %H:%M:%S')"; then
			cmsg "Warning: git commit failed."
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
	git_trigger || cmsg "Warning: Not all git actions were successful."
	
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
	local tpid=${1-}
	
	if [[ -n "$tpid" ]] && kill -0 $tpid &>/dev/null; then
		# kill it and wait for completion
		kill $tpid &>/dev/null || true
		wait $tpid &>/dev/null || true
	fi
}

################################################################################

declare -i TIMEOUT=5
declare -a GIT_ADD_DIRS
declare INW_EVENTS="create,close_write,moved_to,move_self,delete"
declare -i VERBOSITY=0

# invoked without any arguments -> print usage to stdout and exit with success
[[ $# == 0 ]] && { usage; exit 0; }

while getopts ":t:a:ice:vh" opt; do
	case $opt in
	t) # timeout in seconds for timeout task
		TIMEOUT=$OPTARG
		;;
	a) # directories to be watched by inotify and provided to 'git add'
		GIT_ADD_DIRS+=( "$OPTARG" )
		;;
	i) # initialize Git repository
		GIT_INIT=true
		;;
	c) # stage and commit on start
		GIT_INITCOMMIT=true
		;;
	e) # events inotifywait should listen to
		INW_EVENTS=$OPTARG
		;;
	v) # be verbose; each -v increases the verbosity level
		VERBOSITY=$((VERBOSITY + 1))
		;;
	h)
		usage
		exit 0
		;;
	\?)
		cmsg "Error: Invalid option -$OPTARG."
		usage >&2
		exit 1
		;;
	:)
		cmsg "Error: Option -$OPTARG requires an argument."
		usage >&2
		exit 1
		;;
	esac
done

# shift out options
shift $((OPTIND - 1))

# exact one argument for repository is required
[[ $# == 1 ]] || { usage >&2; exit 1; }


# determine canonical path of repository, as inotifywait seems not to deal with symlinks
REPO_DIR=$(readlink -f "$1") || cerrexit "Error: Base directory does not exist."

if [[ -z "${GIT_INIT-}" ]]; then
	# sanity check: is this a git repository?
	[[ -d "$REPO_DIR/.git" ]] || cerrexit "Error: Directory '$REPO_DIR' is not a Git repository."
else
	# initialize Git repository if requested by option '-i'
	cinfo "Initializing Git repository '$REPO_DIR'."
	$GIT init "$REPO_DIR" &>/dev/null || cerrexit "Error: Could not initialize Git repository '$REPO_DIR'."
	
	if (( ${#GIT_ADD_DIRS[@]} > 0 )); then
		for d in "${GIT_ADD_DIRS[@]}"; do
			d="$REPO_DIR/$d"
			if [[ ! -d "$d" ]]; then
				cinfo "Creating directory '$d'."
				mkdir -p "$d" || cerrexit "Error: Could not create directory '$d'."
			fi
		done
	fi
fi

# chdir into repository, as git used to operate within its repository
cd "$REPO_DIR" || cerrexit "Error: Cannot change into repository directory."


# selective directory watches
if (( ${#GIT_ADD_DIRS[@]} == 0 )); then
	GIT_ADD_DIRS=( "." )	# whole repository as default
fi

declare -a INW_DIRS
for d in "${GIT_ADD_DIRS[@]}"; do
	d="$REPO_DIR/$d"
	[[ -d "$d" ]] || cerrexit "Error: Directory '$d' does not exist."
	INW_DIRS+=( "$(readlink -f "$d")" )
done

# stage and commit all changes before monitoring?
if [[ -n "${GIT_INITCOMMIT-}" ]]; then
	cinfo "Initially stage and commit."
	git_trigger
fi

################################################################################

declare TIMEOUT_PID=	# timeout process's PID
declare -i EVENT_NUM=0

# install signal handlers
trap "cleanup" EXIT
trap "usr_timeout" SIGUSR1

# for each requested inotify event
while read -r line; do
	# new inotify event occured
	((++EVENT_NUM))
	cinfo "INOTIFY $(printf '%05d' $EVENT_NUM): ${line/$REPO_DIR/}"
	
	# defer action and restart timeout if timeout task is already runnning
	timeout_task_stop $TIMEOUT_PID
	
	# run timeout task as background process and get its PID
	timeout_task $$ $TIMEOUT &
	TIMEOUT_PID=$!
done < <($INW -q -m -r -e $INW_EVENTS "${INW_DIRS[@]}" "@${REPO_DIR}/.git")

# if we reach this point, inotifywait failed watching or ended unexpectedly
cmsg "Error: notifywait monitoring failed."
exit 1
