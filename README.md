# ConfCan

ConfCan is a simple script used for automatically triggering an action on file 
changes occuring in a directory. The directory is monitored by the `inotify-tools` 
program `inotifywait` and the action is usually a commit into a Git-repository.

Each occured inotify event causes a timeout task to start, which will finally 
trigger the configured action. While the timeout task is running, subsequent 
inotify events cause the timeout to be reset. This is done in order to wait for 
heavy I/O (e.g. copying large directory) to complete and avoid scattering commits.

Please note that with this approach **not every** file change may be versioned.


## General usage

    Usage: confcan.sh [OPTION...] <git-repository>
    
    Options:
            -t <timeout>
                Timeout in seconds before action is triggered (Default: 5)
            -a <directory>
                Directory (relative) watched by inotifywait and provided to 'git add'
                (can be specified multiple times; Default: .)
            -v
                Be verbose (given multiple times increases verbosity level)


## Examples

### Record both user and system changes to system configuration (directory /etc)

    # cd /etc     # chdir into /etc
    # git init    # initialize empty git repository
    # git add .   # initially add all files
    # git commit -m 'Initial state of /etc'   # commit original state
    # confcan.sh -v /etc   # let ConfCan monitor the changes
    ... system update, manual changes, ...
    ^C   # end ConfCan monitoring
    # git diff 193f49d18..HEAD    # review changes (193f49d18 is the hash of the initial commit here)

### Selective directory monitoring

    $ confcan.sh -v -a 'watch_me' -a 'another dir' ~/my_repo &
    $ touch ~/my_repo/foo           # nothing happens because there is no watch
    $ touch ~/my_repo/watch_me/bar  # change is detected and will be committed


## Known bugs

* Copying another git-repository into watched repository might give strange effects (submodule; circular locking?)


## Thanks to

* [Nevik Rehnel's gitwatch project](https://github.com/n3v1k/gitwatch) which gave me some inspiration.


## License

See the `LICENSE` file in root of the repository.


## TODO

* General:
  * Logging support
  * Config file support
  * Automatically init Git repository (and maybe even watched directories)
  * Be more generic: Allow any (configurable/includable) action, not just a git commit
* inotifywait-specific:
  * Use custom output format of inotifywait
  * Configurable pattern for ignoring files/directories
* Git-specific:
  * Metadata (file attribute) logging support
  * Auto-tagging by writing "magic" file (e.g. `touch TAG_config-test-1`)

