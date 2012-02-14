#!/bin/bash

export LC_COLLATE=C

script=${0##*/}
af=$HOME/doc/af               ## to be read
afmaster=$HOME/doc/aflist     ## have been read
afexclude=$HOME/doc/afexclude ## words to exclude

_usage() { cat << EOF
usage: $script

This script will download the most recent archlinux.org forum posts.
Forum posts means the post title along with its URL. It has the ability
to track which posts the user has viewed and store the unread forum
posts in a file.

EOF
}

(( $# != 0 )) && { _usage && exit 1 ;}

## If $af is open; exit
ps a | grep -q "[0-9] vim -c sort! /^https/ + $af" && exit 1

## Read $afmaster into an array
## Append new posts to the master list array, leaving unseen posts marked with a '>'
## Remove any duplicate posts from master list
set -f; O=$IFS IFS=$'\n'
aflist=( $(< "$afmaster") )
aflist+=( $(curl -Ls "https://bbs.archlinux.org/search.php?action=show_24h" | \
    awk -F'["=<]' '/viewtopic.php\?id=/ && !/stickytext/ {printf "%06d%s\n",$5,$6}') )
aflist=( $(printf "%s\n" "${aflist[@]}" | sort | uniq -w 6) )

## Read $af into an array. Format unseen posts. Exclude posts which aren't of interest.
## Recode html and unicode to ASCII.
af_array=( $(< "$af") )
af_array+=( $(printf "%s\n" "${aflist[@]}" | \
    awk -F'>' '!/^[0-9]*#/ {gsub(/^0*/, "");print "https://bbs.archlinux.org/viewtopic.php?id=" $1,$2}' | \
    grep -ivEf "$afexclude" | \
    recode HTML) )
IFS=$O; set +f

## Mark all posts as read and write to master file
printf "%s\n" "${aflist[@]}" | sed -e 's/^\([0-999999]*\)>/\1#/g' > "$afmaster"

## Print unseen forum posts to $af file.
printf "%s\n" "${af_array[@]}"  > "$af"

## OPTIONAL
## Add mail headers so file is viewable in mutt.
#mailfilenew=$HOME/.mail/ml-rss/arch/new/1271109605.5731_0.donkey
#mailfilecur=${mailfilenew/new/cur}:2,S
#header=$(echo -e "Date: $(date -R)\nSubject: ArchLinux Forums\nTo: User\nFrom: User\n\n---")

#printf "%s\n" "$header" "${af_array[@]}" > "$mailfilecur"

## If there are new forum posts, set mail file as unread
## SB 2012-02-13 18:34  The forums have gotten too busy for me to keep.
## For now I'm going to not mark the email file as new.
#grep -q bbs <<< "${af_array[@]}" && mv "$mailfilecur" "$mailfilenew"

## The key binding in mutt
#macro generic,index,pager   E "<shell-escape>vim '-c sort /\^https/' + $HOME/doc/af<enter>" "unread archlinux forum post titles"
