#!/bin/bash

rm -rf /tmp/cr &>/dev/null
mkdir /tmp/cr
cp "$1" /tmp/cr
## This next part should be handled with 'file -b' and parameter expansion
[[ *.cbz ]] && unzip "/tmp/cr/*.cbz" -d /tmp/cr &>/dev/null
[[ *.cbr ]] && unrar e "/tmp/cr/*.cbr" /tmp/cr &>/dev/null
## if res == 1493, then -z 90
sxiv -r -z 10 -Z /tmp/cr &>/dev/null &
