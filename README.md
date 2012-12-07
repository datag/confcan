# ConfCan

ConfCan is a simple script used for automatically triggering an action on file 
changes occuring in a directory. The directory is monitored by the `inotify-tools` 
program `inotifywait` and the action is usually a commit into a Git-repository.

Each occured inotify event causes a timeout task to start, which will finally 
trigger the configured action. While the timeout task is running, subsequent 
inotify events cause the timeout to be reset. This is done in order to wait for 
heavy I/O (e.g. copying large directory) to complete and avoid scattering commits.

Please note that which this approach **not every** file change may be versioned.


## General usage

FIXME


## Known bugs

* Copying another git-repository into watched repository gives strange effects (submodule; circular locking?)


## Thanks to

* [Nevik Rehnel's gitwatch project](https://github.com/n3v1k/gitwatch) which gave me some inspiration.


## License

See the `LICENSE` file in root of the repository.


## TODO

* General:
  * Logging support
  * Make every hard-coded value configurable (e.g. timeout)
* inotifywait-specific:
  * Use custom output format of inotifywait
  * Configurable pattern for ignoring files/directories
* Git-specific:
  * Metadata (file attribute) logging support
  * Auto-tagging by writing "magic" file (e.g. `touch TAG_config-test-1`)

