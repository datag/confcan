# ConfCan

ConfCan is a simple script used for automatically triggering an action on file 
changes occuring in a directory. The directory is monitored by the `inotify-tools` 
program `inotifywait` and the action is usually a commit into a Git-repository.

## General usage

TBD

## Thanks to

* [Nevik Rehnel's gitwatch project](https://github.com/n3v1k/gitwatch) which gave me some inspiration

## License

See the `LICENSE` file in root of the repository.

## TODO

* Logging support
* Metadata (file attribute) logging support
* Auto-tagging by writing "magic" file (e.g. `touch TAG_config-test-1`)

