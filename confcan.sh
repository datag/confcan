#!/usr/bin/env bash

set -e

INW_EVENTS="create,close_write,moved_to,move_self,delete"
TIMEOUT=5

###############################

msg () {
	echo "$@" >&2
}

git_trigger () {
	if ! git add .; then
		msg "WARN: git add failed"
		return 1
	fi
	
	if [[ -n "$(git status --porcelain)" ]]; then
		if ! git commit -a -m "Auto commit $(date +'%Y-%m-%d %H:%M:%S')"; then
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

###############################

if [[ $# != 1 ]]; then
    echo "Usage..." >&2
    exit
fi

REPO_DIR=$(readlink -f "$1") || { msg "Error: Repository does not exist."; exit 1; }
[[ ! -d "$REPO_DIR" ]] && { msg "Error: The repository is not a directory."; exit 1; }
cd "$REPO_DIR" || { msg "Error: Cannot change into repository directory."; exit 1; }

###############################

PID=$$
SLEEP_PID=		# invalid pid

trap "cleanup" EXIT
trap "usr_timeout" SIGUSR1

while read -r line; do
	((++a))
	echo "NOTIFY $(printf '%05d' $a): ${line/$REPO_DIR/GIT_REPO}"
	
	if [[ -n "$SLEEP_PID" ]] && kill -0 $SLEEP_PID &>/dev/null; then
		kill $SLEEP_PID &>/dev/null || true
		wait $SLEEP_PID &>/dev/null || true
	fi
	
	# timeout subshell
	(
		sleep $TIMEOUT
		kill -SIGUSR1 $PID || msg "WARN: Error sending USR1 to $PID"
	) &
	SLEEP_PID=$!
done < <(inotifywait -m -r -e $INW_EVENTS "$REPO_DIR" "@${REPO_DIR}/.git" 2>/dev/null)

