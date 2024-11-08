# rua

ArchLinux User Repository Explorer Helper Utility Tool Thing

## Basics

rua has two options
```
rua list
```
Prints a list of all AUR packages into the stdout.

```
rua info <pkg>
```
Queries the AUR-api for information of the specified package, then outputs the json response to stdout.

## Usage

Standalone this is probably not very usefull, compose with other tools like this:

```
aur() {
    rua list \
    | fzf --multi \
          --inline-info \
          --preview='rua info {} | jq -r ".results[] | to_entries | .[] | \"\(.key): \(.value)\""' \
          --bind "enter:become(clone_and_cd https://aur.archlinux.org/{}.git)"
}
```

## Cache 

rua caches the AUR package list in `$XDG_CACHE_HOME/packages.rua` or `~/.cache/packages.rua` and checks on startup
if the package list should be redownloaded. To force a reload simply delete the file.

# Building
Build with `zig v0.14.0-dev.2182+54d0ba418`
it may or may not work with other commits, zig breaks often.
```
$ cd rua
$ zig build run -- list
```
