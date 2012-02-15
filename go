#!/bin/bash

script=${0##*/}

_u() { cat << EOF
usage: $script [username@]HOST|SESSION

This script handles ssh'ing to different hosts running tmux.

EOF
}

(( $? > 1 )) && { _u; exit; }

grep -q '@' <<< $1 && user="-l ${1%@*}"     ## If parameter has an '@' then set var 'user'
hn="${1#*@}"                                ## If applicable, strip username from hostname

## This should be handled with 'case'
[[ $hn == pp ]]         && sn=pp        hn=dtsteve  ## pair programming
[[ $hn == im ]]         && sn=im        hn=dtsteve  ## weechat
[[ $hn == mail ]]       && sn=mail      hn=dtsteve  ## mutt
[[ $hn == torrent ]]    && sn=torrent   hn=donkey   ## rtorrent
[[ $hn == ng ]]         && sn=ng        hn=nagios   ## nagcon
[[ ! $sn ]]             && sn=main
[[ ! $user && $hn == $HOSTNAME ]]  && { tmux attach \; switchc -t "$sn"; exit; }

##[[ $TMUX ]] && tmux detach

## don't quote $user
ssh $user -t "$hn" "LANG=en_CA.utf8 tmux attach \; switchc -t $sn"

## 'tmux new-session -t $sn' will connect to a session and have its own window
## control, versus sharing as 'new-session -s $sn' does
