#!/bin/bash

ebook_dir=$HOME/tbr/
fn="-*-terminus-medium-r-*-*-14-*-*-*-*-*-*-*"
nb="#585858"
nf="#dadada"
sb="#121212"
sf="#dadada"
unset c e f

command -v dmenu >/dev/null || f=$1

cd "$ebook_dir"
c=$(uniq "$HOME/doc/tbr" | tac)
shopt -s globstar
f=$({ echo "$c"; for i in **; do [[ -f $i ]] && echo "$i"; done; } | dmenu -l 10 -fn "$fn" -nb "$nb" ${1+"@"})
shopt -u globstar
echo "$f" >> "$HOME/doc/tbr"

rm -rf /tmp/cr &>/dev/null
mkdir /tmp/cr
f=$(readlink -f "$f")
cp "$f" /tmp/cr

e=$(file -b "$f")
[[ $e == Zip* ]] && unzip "/tmp/cr/*.cbz" -d /tmp/cr &>/dev/null
[[ $e == RAR* ]] && unrar e "/tmp/cr/*.cbr" /tmp/cr &>/dev/null

## if res == 1493, then -z 90
sxiv -r -z 10 -Z /tmp/cr &>/dev/null &
## trap; rm -rf /tmp/cr &>/dev/null
