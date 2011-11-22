#!/bin/bash
#
# Script to repeated run a command and print its output.
# Copyright (c) 2009 Jim Karsten
#
# This script is licensed under GNU GPL version 2.0 or above.


usage() { cat << EOF
usage: $0 [options] keyword [number]

This script will run a command repeatedly printing output from the HOME position.
    -n  Refresh time in seconds. Default 15.

    -h  Print this help message.

EXAMPLES:
    $0 -n 2 ls -l

NOTES:
    If the terminal the script is run in changes size, the script will clear
    the screen before the next running of the command.
EOF
}

refresh=15

while [[ $1 == -* ]]; do
    case "$1" in
        -n) shift; refresh=$1;;
        -h) usage; exit 0    ;;
        --) shift; break     ;;
        -*) usage; exit 1    ;;
    esac
    shift
done

echo "$@"

trap 'echo -e $SHOW; exit;' EXIT SIGINT

TOP="\e[H"       # Set cursor at home position
HIDE="\e[?25l"   # Hide cursor
SHOW="\e[?25h"   # Show cursor

echo -ne "$HIDE"

prev_columns=0
prev_lines=0

while true; do
    columns=$(tput cols)
    lines=$(tput lines)

    [[ $columns != $prev_columns || $lines != $prev_lines ]] && clear

    prev_columns=$columns
    prev_lines=$lines

    echo -ne "$TOP"
    date "+%F %T"

    eval "$@"

    sleep "$refresh"
done

echo -e "$SHOW"
