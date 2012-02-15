#!/bin/bash

script=${0##*/}
_u() { cat << EOF
usage: $script FILE GIT_DIRECTORY

This script copies a file to a git repository and commits the current version
of the file.

OPTIONS:
   -h      Print this help message.
   -v      Verbose output.

EXAMPLES:
    $script /path/to/file /var/git/vim
    $script file.txt /var/git/vim

    ## To use as a vim backup, add this line to ~/.vimrc
    autocmd BufWritePre * silent ! /root/bin/vim_git_backup.sh "%:p" /var/git/vim
    autocmd BufWritePost * silent ! /root/bin/vim_git_backup.sh "%:p" /var/git/vim

NOTES:
    If the file path is relative it is assumed relative to the current directory.

    This works for regular files only.

    If using as a backup for vim, at times you may experience noticable pauses
    when saving files as the git repo is updated.

    Requires rsync.
EOF
}

__mi() { __v && echo -e "===: $*" ;}
__me() { echo -e "$script: ERROR: $*" >&2; exit 1 ;}
__v()  { ${verbose-false} ;}

_options() {
    # set defaults
    args=()
    unset verbose

    while [[ $1 ]]; do
        case "$1" in
            -v) verbose=true    ;;
            -h) _u; exit 0      ;;
            --) shift; [[ $* ]] && args+=( "$@" ); break;;
            -*) _u; exit 1      ;;
             *) args+=( "$1" )  ;;
        esac
        shift
    done

    (( ${#args[@]} != 2 )) && { _u; exit 1; }
    file_relative=${args[0]}
    git_dir=${args[1]}
}

_options "$@"

filename=$(readlink -f "$file_relative")          # Convert relative to absolute

__v && __mi "Filename: $filename"

[[ ! -f $filename ]] && __me "Not a regular file: $filename"
[[ ! -d $git_dir ]] && __me "Directory not found or not a valid directory: $git_dir"
command -v rsync &>/dev/null || __me "rsync not installed"

if [[ ! -d $git_dir/.git ]]; then
    cd "$git_dir"
    echo '*.sw*' > .gitignore
    git init
fi

echo "$(date) $filename $git_dir/" > ~/foo
rsync -aR "$filename" "$git_dir/"

## Background git to speed up vim buffer writes
({ cd "$git_dir"
echo "FIXME PWD: $PWD" >> ~/foo
git add -A . || __me "git add -u failed."
# The --dry-run git commit will test if there is anything to commit.
if git commit --work-tree=$HOME/.vim/backup -q --dry-run; then
    out=$(git commit -q -a -m "${filename##*/}" || __me "git commit failed")
    __v && echo "$out"
fi; } 2>&1 | logger ) &
