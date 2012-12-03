#!/usr/bin/env bash

set -e

INW_EVENTS="create,close_write,moved_to,move_self,delete"
TIMEOUT=5

###############################

if [[ $# != 1 ]]; then
    echo "Usage..." >&2
    exit
fi

REPO_DIR=$(readlink -f "$1") || { echo "Target does not exist." >&2; exit 1; }
[[ ! -d "$REPO_DIR" ]] && { echo "Error: The target is not a directory." >&2; exit 1; }
cd "$REPO_DIR"

###############################

git_trigger () {
	if ! git add .; then
		echo "WARN: git add failed" >&2
		return 1
	fi
	
	if [[ -n "$(git status --porcelain)" ]]; then
		if ! git commit -a -m "Auto commit $(date +'%Y-%m-%d %H:%M:%S')"; then
			echo "WARN: git commit failed" >&2
			return 2
		fi
	else
		echo "Nothing to do... skipping commit!" >&2
	fi
}

cleanup () {
	echo -e "\n$FUNCNAME" >&2
	if [[ -n "$SLEEP_PID" ]] && kill -0 $SLEEP_PID &>/dev/null; then
		echo "CLEANUP: killing $SLEEP_PID" >&2
		kill $SLEEP_PID &>/dev/null
	fi
	exit 0
}

usr_timeout () {
	git_trigger || echo "... something went wrong with git_trigger()" >&2
	
	return 0
}

###############################

PID=$$
SLEEP_PID=		# invalid pid

trap "cleanup" EXIT
trap "usr_timeout" SIGUSR1

while read -r line; do
	((++a))
	echo "NOTIFY $(printf '%05d' $a): ${line/$REPO_DIR/GIT_REPO}"
	
	if [[ -n "$SLEEP_PID" ]] && kill -0 $SLEEP_PID &>/dev/null; then
		#echo "DEFERRED timeout; killing $SLEEP_PID" >&2
		kill $SLEEP_PID &>/dev/null || true
		wait $SLEEP_PID &>/dev/null || true
	fi
	
	# timeout subshell
	(
		#echo "waiting some time..." >&2
		sleep $TIMEOUT
		#echo "timeout... sending signal USR1 to parent $PID" >&2
		kill -SIGUSR1 $PID || echo "WARN: Error sending USR1 to $PID" >&2
	) &
	SLEEP_PID=$!
done < <(inotifywait -m -r -e $INW_EVENTS "$REPO_DIR" "@${REPO_DIR}/.git" 2>/dev/null)


