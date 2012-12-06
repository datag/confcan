# ConfCan

ConfCan is a simple script used for automatically triggering an action on file 
changes occuring in a directory. The directory is monitored by the `inotify-tools` 
program `inotifywait` and the action is usually a commit into a Git-repository.

