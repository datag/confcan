# ConfCan

ConfCan is a simple script used for automatically committing to a Git repository
on file changes occuring in a directory. The directory is monitored by the
`inotify-tools` program `inotifywait`.

Each occured inotify event causes a timeout task to start, which will finally 
trigger the configured action. While the timeout task is running, subsequent 
inotify events cause the timeout to be reset. This is done in order to wait for 
heavy I/O (e.g. copying large directory) to complete and avoid scattering commits.

Please note that with this approach **not every** file change may be versioned.


## General usage

	Usage: confcan.sh [OPTION...] <git-repository>

	Options:
		-t <timeout>      (Default: 5)
		    Timeout in seconds before action is triggered.
		-w <directory/file>    (Default: .)
		    Directory/File (relative) to be watched and provided to 'git add'.
		    This option can be specified multiple times.
		-n <directory/file>    (Internal: $GIT_REPO/.git)
		    Directory/File (relative) to exclude from watching.
		    This option can be specified multiple times.
		-i
		    Initialize Git repository and creates directories specified by '-a'.
		    The base directory must exist.
		-c
		    Stage and commit all changes before monitoring.
		-e <events>       (Default: create,close_write,moved_to,move_self,delete)
		    Comma separated list of events 'inotifywait' should listen to.
		    See man page of 'inotifywait' for available events.
		-v
		    Be verbose. Verbosity level increases when specified multiple times.
		-h
		    Print this usage message and exit.


## Examples

### Record both user and system changes to system configuration (directory `/etc`)

    # cd /etc     # chdir into /etc
    # git init    # initialize empty git repository
    # git add .   # initially add all files
    # git commit -m 'Initial state of /etc'   # commit original state
    # confcan.sh -v /etc   # let ConfCan monitor the changes
    ... system update, manual changes, ...
    ^C   # end ConfCan monitoring
    # git diff 193f49d18..HEAD    # review changes (193f49d18 is the hash of the initial commit here)

### Selective directory monitoring

    $ confcan.sh -v -w 'watch_me' -w 'another dir' ~/my_repo &
    $ touch ~/my_repo/foo           # nothing happens because there is no watch
    $ touch ~/my_repo/watch_me/bar  # change is detected and will be committed

### Initialize Git repository at `/` and stage, commit and watch `/etc` and `/var/lib/portage`

    # confcan.sh -v -i -c -w etc -w var/lib/portage /


## System requirements and settings

### Required software

* [Git](http://git-scm.com/)
* [inotify-tools](https://github.com/rvoicilas/inotify-tools/wiki)

### Settings

See the [inotify man page](http://www.kernel.org/doc/man-pages/online/pages/man7/inotify.7.html) for complete reference.

#### Increase the amount of allowed watches, e.g. to 32768:

    # echo 32768 >/proc/sys/fs/inotify/max_user_watches


## License

See the `LICENSE` file in root of the repository.


## Thanks to

* [Question "Making git auto-commit" on stackoverflow](http://stackoverflow.com/questions/420143/making-git-auto-commit) for the idea
* [Nevik Rehnel's gitwatch project](https://github.com/n3v1k/gitwatch) for inspiration


## Known bugs

* Copying another git-repository into watched repository might give strange effects (submodule; circular locking?)
* Directory/file must exist to be included in watch-list
* If directory/file is specified **not** to be watched and it doesn't exist, it will be removed from ignore-list
* If a watched directory/file is removed it will be removed from the watch-list and no longer be monitored, even when recreated


## TODO

* General:
  * Configurable commit message
  * Logging support
  * Config file support
* inotifywait-specific:
  * Use custom output format of inotifywait
  * Configurable pattern for ignoring files/directories
* Git-specific:
  * Metadata (file attribute) logging support
  * Auto-tagging by writing "magic" file (e.g. `touch TAG_config-test-1`)

