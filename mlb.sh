#!/bin/bash
#
# Script to view CBS Sports mlb gamecenter.
# Copyright (c) 2009 Jim Karsten
#
# This script is licensed under GNU GPL version 2.0 or above.

usage() {

cat << EOF
Version 0.1

usage: $0 [options] team

This script is used to view CBS Sports mlb gamecenter pages.

OPTIONS:

    -o  Orientation: v=vertical, h=horizontal
    -t  Run tests. (For developers.)

    -h  Print this help message.

EXAMPLES:

    $0                      # Display todays games
    clear; $0 TOR           # Display the gamecenter for Toronto Blue Jays
    clear; $0 Toronto       # Same thing
    clear; $0 NYY           # Display the gamecenter for New York Yankees
    refresh.sh "$0 TOR"     # Display the gamecenter with continuous updates

    $0 -c "\$BLUE" -o h TOR  # Display headings in blue, horizontal orientation.

NOTES:

    To display a specific gamecenter, simply provide the name or
    abbreviation of one of the teams in the game.

    If the -o orientation option is not provided, the script will select the
    orientation optimal for the current terminal size.
EOF
}


#
# block_coordinates
#
# Sent: row, col, height, width
# Return: x1, y1, x2, y2
# Purpose:
#
#   Return the block coordinates for a block given a start row and column, and
#   the block height and width.
#
#
function block_coordinates {

    r=$1
    c=$2
    h=$3
    w=$4

    echo "$r $c $(($r+$h-1)) $(($c+$w-1))"

    return
}


#
# block_scrub_coordinate
#
# Sent: value, min, max
# Return: scrubbed value
# Purpose:
#
#   Return a value within a range.
#
# Notes:
#
#   If min < value < max return value
#   If value < min return min
#   If value > max return max
#
#   If you want a one-sided check, just set the unlimited side to the value.
#   For example, to scrub a value so it's minimum is 0 but has no maximum
#   restriction, set the max = value. scrub_coordinate $value 0 $value
#
function block_scrub_coordinate {

    local value=$1
    local min=$2
    local max=$3

    local tmp=$(( ($value < $min) ? $min : $value  ))
    echo $(( ($tmp > $max) ? $max : $tmp  ))

    return
}


#
# block_print
#
# Sent: row1, col1, row2, col2 - upper left and lower right corner coordinates
#       text - text to print in block, multiline permissible.
# Return: nothing
# Purpose:
#
#   Print text in a block.
#
# Notes:
#
#   Text will only print within the coordinates of the block.
#   Text will not print outside the terminal coordinates.
#
function block_print {

    ## if block is outside the terminal range, then there is nothing to
    ## print
    [[ "$1" -gt "$LINES" ]] && return

    local row1=$(block_scrub_coordinate $1 1 $(( $LINES   - 1 )) )
    local col1=$(block_scrub_coordinate $2 1 $(( $COLUMNS - 1 )) )
    local row2=$(block_scrub_coordinate $3 1 $(( $LINES   - 1 )) )
    local col2=$(block_scrub_coordinate $4 1 $(( $COLUMNS - 1 )) )
    local text=$5

    saveIFS=$IFS
    IFS=$'\n'
    declare -a all_lines=( $text );
    IFS=$saveIFS

    local rows=$(( $row2 - $row1 + 1 ))
    local cols=$(( $col2 - $col1 + 1 ))

    # If there are more lines of text than rows to display them in, display the
    # bottom lines of text since they will contain the most recent info
    start=$(( ${#all_lines[@]} - $rows ))
    [[ "$start" -lt "0" ]] && start=0

    declare -a lines=( "${all_lines[@]:$start:$rows}" )

    for i in $( seq 0 $(( $rows - 1)) ); do


        local row=$(( $row1 + $i))
        local tmp=${CURSOR_POSITION/X/$row}
        echo -ne ${tmp/Y/$col1}
        local fill=$(echo "${lines[$i]}" | cut -b 1-$cols)

        # OMG colour!!
        local hl_on=""
        local hl_off=""

        if [[ -n $colouring ]]; then

            local first=${fill:0:1}
            if [[ $first == "*" ]]; then
                #fill=${fill/\*/ }
                hl_on=$colour_highlight
                hl_off=$COLOUR_OFF
            fi

            local first_two=${fill:0:2}
            case $first_two in
                B:) hl_on=$colour_ball
                    hl_off=$COLOUR_OFF;;
                S:) hl_on=$colour_strike
                    hl_off=$COLOUR_OFF;;
            esac


            local tmp=$(echo $fill | sed -e 's/^ \(.*\) /\1/')
            local first_word=${tmp%% *}
            case $first_word in
                  Ball) hl_on=$colour_ball
                        hl_off=$COLOUR_OFF;;
                Strike) hl_on=$colour_strike
                        hl_off=$COLOUR_OFF;;
                  Foul) hl_on=$colour_foul
                        hl_off=$COLOUR_OFF;;
            esac
        fi

        printf "%b%-${cols}s%b" "$hl_on" "$fill" "$hl_off"

    done
}


#
# download
#
# Sent: nothing
# Return: nothing
# Purpose:
#
#   Download gamecenter pages.
#
function download {

    wget -q -O $index_file "http://lps.cbssports.com/mlbscores/index.dat"

    if [[ -n $game ]]; then

        game_page=$(cat $index_file | tr "~" "\n"  | tail --lines=+2 | grep "$game" | awk  'BEGIN {FS = "|"} {print $2}')
        wget -q -O $gamecenter_file "http://lps.cbssports.com/gcmlb/$game_page"
    fi

    return
}


#
# formatted_where
#
# Sent: where  eg "Bottom 6th", eg 1239847800
# Return: formatted where
# Purpose:
#
#   Return the "where" value formatted.
#
# Notes:
#
#   The where value differs depending on the status of the game.
#
#   status        code  where
#   not started     S   1239847800   seconds since epoch timestamp
#   in progress     P   Bottom 6th   current inning
#   completed       F   Final        status indicator
#   postponed       O   Postponed    status indicator
#
function formatted_where {

    local status=$1
    local where=$2

    case "$status" in
        S) date "+%l:%M %p" --date "$[$(date +%s)-$where] seconds ago";;
        *) echo "$where";;
    esac

    return
}


#
# max_length
#
# Sent: str1, str2
# Return: length of the longest of the two strings.
# Purpose:
#
#   Return the length of the longest of two strings.
#
function max_length {

    str1=$1
    str2=$2

    echo $(( ( ${#str1} > ${#str2} ) ? ${#str1}  : ${#str2}  ))

    return
}


#
# parse_game
#
# Sent: game details (pipe delimited string)
# Return: nothing
# Purpose:
#
#   Parse a single game from index page.
#   Fill games array.
#
function parse_game {

    local details=$1

    saveIFS=$IFS
    IFS=$"|"

    local game_id=${details%%|*}

    local offset=${games_index[$game_id]}

    local count=0
    for field in $details; do

        games[$(( $offset + $count ))]="$field"

        count=$(( $count + 1))
        [[ "$count" -ge "$IX_FIELDS" ]] && break
    done

    IFS=$saveIFS

    return
}


#
# parse_gamecenter
#
# Sent: nothing
# Return: nothing
# Purpose:
#
#   Parse the gamecenter page data.
#   Populates the gc_sections array.
#
function parse_gamecenter {

    # The gamecenter file sections are "\n\n" delimited. It requires some
    # gymnastics to get this to work. A blank line could indicate a new section
    # or it might be an empty section value.


    i=0         # Current section index
    nl=0        # Current count of new line characters
    str=        # Current section value

    while read line; do

        (( nl++ ))

        if [[ "$line" == "" && "$nl" -ge "2" ]]; then
            gc_sections[$i]="$str"
            (( i++ ))
            nl=0
            str=
            continue
        fi

        [[ -n "$str" ]] && str="$str $line" || str="$line"

    done < <(cat "$gamecenter_file")

    return
}


#
# parse_gamecenter_players
#
# Sent: list
# Return: nothing
# Purpose:
#
#   Parse a list of gamecenter players.
#   Populates the gc_batters and gc_pitchers arrays.
#
# Notes:
#
#   The list is expected to be a ~ delimited list of records. The fields
#   (player id and stats string) are delimited by a colon :. The string of
#   stats are not parsed by this routine since the string may be different for
#   players of different situations, eg pitchers vs batters, bench batters vs
#   playing batters.
#
#   The routine assumes each player id is unique.
#
#   gc_pitchers[player_id]="str of stats"
#   Eg   gc_pitchers[546234]="Johnson,2-0,0,0.57, 15.2,15"
#
function parse_gamecenter_players {

    # The order of these is intentional. A player could be in several lists.
    # The list processed last overwrites the data from a previous list if
    # saving to the same array. The active game stats should be processed last.

    parse_player_list "gc_batters"       "${gc_sections[$GC_SECTION_PLAYED_LIST]}"
    parse_player_list "gc_batters"       "${gc_sections[$GC_SECTION_BATTER_LIST]}"

    parse_player_list "gc_bench_batters" "${gc_sections[$GC_SECTION_BENCH_LIST]}"

    parse_player_list "gc_bullpen_pitchers" "${gc_sections[$GC_SECTION_BULLPEN_LIST]}"
    parse_player_list "gc_pitchers"         "${gc_sections[$GC_SECTION_PITCHER_LIST]}"

}


#
# parse_games
#
# Sent: nothing
# Return: nothing
# Purpose:
#
#   Parse games on index page.
#
function parse_games {

    for id in ${!games_index[@]}; do
        # The first two lines, the id line and "AL/NL breakdown line, of file are ignored
        game_details=$(cat $index_file | tr "~" "\n"  | tail --lines=+2 | grep "^$id")
        parse_game "$game_details"
    done

    return

}


#
# parse_games_index
#
# Sent: nothing
# Return: nothing
# Purpose:
#
#   Parse games index page. Fill games_index array.
#
function parse_games_index {

    # The index file has these delimiters
    # records: ~
    # fields : |

    # The first line in the index file is the games ids.
    ids=$(cat $index_file | tr "~" "\n"  | head -1 | tr "|" " ")

    local count=0
    for id in $ids; do
        games_index[$id]=$(( $count * $IX_FIELDS ))
        count=$(( $count + 1))
    done;

    return
}


#
# parse_player_list
#
# Sent: array - name of array eg 'gc_batters'
#        list
# Return: nothing
# Purpose:
#
#   Parse a list of gamecenter players.
#   Populates the array indicated.
#
# Notes:
#
#   The list is expected to be a ~ delimited list of records. The fields
#   (player id and stats string) are delimited by a colon :. The string of
#   stats are not parsed by this routine since the string may be different for
#   players of different situations, eg batters vs batters, bench batters vs
#   playing batters, batters vs pitchers, pitchers vs bullpen.
#
#   The routine assumes each player id is unique.
#
#   gc_batters[player_id]="str of stats"
#   Eg   gc_batters[546234]="Johnson,2-0,0,0.57, 15.2,15"
#
function parse_player_list {

    local array="$1"
    local list="$2"

    # Split the list into records

    saveIFS=$IFS
    IFS='~'
    declare -a records=( $list );
    IFS=$saveIFS

    for record in "${records[@]}"; do

        # Split the record into fields
        saveIFS=$IFS
        IFS=':'
        declare -a fields=( $record );
        IFS=$saveIFS

        eval $array[\${fields[0]}]=\${fields[1]}
    done

    return
}


#
# print_at_bat
#
# Sent: id
# Return: nothing
# Purpose:
#
#   Print game stats for the current at bat batter.
#
#    At Bat        Bats  AB  AVG HR RBI  R SB
#    #12 Scutaro     R  123 .415  3  12  9  0
#
function print_at_bat {

    saveIFS=$IFS
    IFS=','
    declare -a at_bat_stats=(${gc_sections[$GC_SECTION_AT_BAT_ID]});
    local id=${at_bat_stats[0]}
    stat_str="${gc_batters[$id]}"
    declare -a stats=( $stat_str );
    IFS=$saveIFS

    [[ -z $stat_str ]] && return

    # stats array Season Stats
    # AB R H HR RBI BB SO SB AVG
    # 6  7 8 9   10 11 12 13 14

    printf "#%-2s %-10.10s %s %3s %4s %2s %3s %3s %2s\n" \
        ${at_bat_stats[2]} \
        "${stats[0]/*&nbsp;/}" \
        ${at_bat_stats[1]} \
        ${stats[6]} \
        ${stats[14]} \
        ${stats[9]} \
        ${stats[10]} \
        ${stats[7]} \
        ${stats[13]}

}


#
# print_at_pitch
#
# Sent: id
# Return: nothing
# Purpose:
#
#   Print game stats for the current at pitch pitcher.
#
#    Pitching   Throws   IP W-L ERA   Ks  BB
#    #45 Halladay    R  123 3-1 1.45 123 123
#
function print_at_pitch {

    saveIFS=$IFS
    IFS=','
    declare -a at_pit_stats=(${gc_sections[$GC_SECTION_PITCHER_ID]});
    local id=${at_pit_stats[0]}
    stat_str="${gc_pitchers[$id]}"
    declare -a stats=( $stat_str );
    IFS=$saveIFS

    [[ -z $stat_str ]] && return

    # stats array Season Stats
    # W-L ERA IP H ER HR BB K
    # 7    8  9 10 11 12 13 14

    #    #45 Halladay    R  123 3-1  1.45 123 123
    printf "#%-2s %-10.10s %s %5s %5s %5s %3s %3s\n" \
        ${at_pit_stats[2]} \
        "${stats[0]/*&nbsp;/}" \
        ${at_pit_stats[1]} \
        ${stats[9]} \
        ${stats[7]} \
        ${stats[8]} \
        ${stats[14]} \
        ${stats[13]}

}


#
# print_batter
#
# Sent: id
#       highlight ( boolean, display name with/without highlight)
# Return: nothing
# Purpose:
#
#   Print game stats for a single batter.
#
#   Scutaro     0 0 0 0
#
function print_batter {

    local id=$1
    local highlight=$2

    stat_str="${gc_batters[$id]}"

    [[ -z $stat_str ]] && return


    saveIFS=$IFS
    IFS=','
    declare -a stats=( $stat_str );
    IFS=$saveIFS

    printf "%b%-10.10s %2s %s %s %s %s%s\n" \
        "${highlight:- }" \
        "${stats[0]/*&nbsp;/}" \
        ${stats[1]} \
        ${stats[2]} \
        ${stats[3]} \
        ${stats[4]} \
        ${stats[5]}
}


#
# print_batters
#
# Sent: nothing
# Return: nothing
# Purpose:
#
#   Print a game stats for a list of batters.
#
#   Scutaro     0 0 0 0
#   Hill        0 0 0 0
#   ...
#   Snider      0 0 0 0
#
function print_batters {

    local list="$1"

    saveIFS=$IFS
    IFS=','
    declare -a ids=( $list );
    declare -a at_bat_stats=(${gc_sections[$GC_SECTION_AT_BAT_ID]});
    declare -a at_bat_opponent=(${gc_sections[$GC_SECTION_AT_BAT_OPPONENT_ID]});
    IFS=$saveIFS


    local hl
    local id

    local count=0
    for id in "${ids[@]}"; do

        hl=
        [[ "${at_bat_stats[0]}" == "$id" ]] && hl="*"
        [[ "${at_bat_opponent[0]}" == "$id" ]] && hl='-'

        print_batter "$id" "$hl"

        count=$(( $count + 1))
    done

    return
}



#
# print_bso
#
# Sent: nothing
# Return: nothing
# Purpose:
#
#   Print the current at bat balls, strikes and outs.
#
#   B: 3
#   S: 2
#   2 Out
#
function print_bso {

    local game_id=${gc_sections[$GC_SECTION_GAME_ID]};

    local offset=${games_index[$game_id]}


    saveIFS=$IFS
    IFS=','
    declare -a bso_stats=(${games[$(( $offset + $IX_BSO)) ]});
    IFS=$saveIFS

    printf "B: %s\n" ${bso_stats[0]}
    printf "S: %s\n" ${bso_stats[1]}
    printf "%s Out\n" ${bso_stats[2]}

    return
}


#
# print_current_at_bat
#
# Sent: nothing
# Return: nothing
# Purpose:
#
#   Print the current at bat game text.
#
function print_current_at_bat {

    local game_id=${gc_sections[$GC_SECTION_GAME_ID]};

    local offset=${games_index[$game_id]}

    game_text=$( echo "${games[$(( $offset + $IX_GAME_TEXT)) ]}" | \
                 sed 's/<br>/,/g' | \
                 sed 's/<[^>]*>//g' | \
                 sed 's/&nbsp;/ /g')


    # Split game_text on commas and print each part on new line.
    # Exception: Commas inside parenthesis should not be broken on.
    #
    # Here is the pseudo code for the algorithm to handle that
    #
    #   while true
    #       extract up to first comma
    #       extract up to first (
    #       if both are the same, then we're done
    #           print game_text
    #           exit
    #       if ( is shortest
    #           print everything up to )
    #           set game_text = left over
    #       else
    #           print everything up to ,
    #           print new line
    #           set game_text = left over
    #

    while :; do

        if [[ "${game_text:0:7}" == "Due Up:" ]]; then
             printf "%s\n" "Due Up:"
             game_text=${game_text#Due Up:}
        fi

        if [[ "${game_text:0:1}" == ":" ]]; then
             printf "\n"
             game_text=${game_text#:}
        fi

        local comma=${game_text%%,*}
        local parenth=${game_text%%(*}

        if [[ "$parenth" == "$game_text" && "$comma" == "$game_text" ]]; then
            printf "%s\n" "$game_text"
            break
        fi

        if [[ "${#parenth}" -lt "${#comma}" ]]; then
            local close=${game_text%%)*}

            # Intentionally no newline in next printf.
            printf "%s)" "$close"
            game_text=${game_text#*)}

        else
            printf "%s\n" "$comma"
            game_text=${game_text#*,}
        fi
    done

    return
}


#
# print_game
#
# Sent: nothing
# Return: nothing
# Purpose:
#
#   Print a single game summary.
#
#   AWAY 0 0 0 0 0            1 3 0    Top 5th
#   HOME 0 0 0 0              0 5 1
#
function print_game {

    local game_id=$1

    local offset=${games_index[$game_id]}

    inning="${games[$(( $offset + $IX_INNING)) ]}"

    saveIFS=$IFS
    IFS=','
    declare -a away_lines=(${games[$(( $offset + $IX_AWAY_LINE)) ]});
    declare -a home_lines=(${games[$(( $offset + $IX_HOME_LINE)) ]});
    declare -a away_scores=(${games[$(( $offset + $IX_AWAY_SCORE)) ]});
    declare -a home_scores=(${games[$(( $offset + $IX_HOME_SCORE)) ]});
    IFS=$saveIFS

    [[ "$inning" -lt "9" ]] && inning=9

#    local rl=$(( (${#games[$(( $offset + $IX_AWAY_RECORD)) ]} > ${#games[$(( $offset + $IX_HOME_RECORD)) ]} ) ? \
#                  ${#games[$(( $offset + $IX_AWAY_RECORD)) ]} : \
#                  ${#games[$(( $offset + $IX_HOME_RECORD)) ]} ))
    local rl=$(max_length ${games[$(( $offset + $IX_AWAY_RECORD)) ]} ${games[$(( $offset + $IX_HOME_RECORD)) ]})


    local away_line=$(printf "%3s %${rl}s:" "${games[$(( $offset + $IX_AWAY_ABBR)) ]}" \
                                         "${games[$(( $offset + $IX_AWAY_RECORD)) ]}" )
    local home_line=$(printf "%3s %${rl}s:" "${games[$(( $offset + $IX_HOME_ABBR)) ]}" \
                                         "${games[$(( $offset + $IX_HOME_RECORD)) ]}" )

    # The line scores have to be built one inning at a time since it's possible
    # an inning has a multiple digit value. The other half of the inning has to
    # be spaced accordingly.

    local i

    for i in $(seq 0 $(( $inning - 1)) ); do
        local len=$(max_length ${away_lines[$i]} ${#home_lines[$i]})

        away_line=$(printf "%s %${len}s" "$away_line" "${away_lines[$i]:-" "}")
        home_line=$(printf "%s %${len}s" "$home_line" "${home_lines[$i]:-" "}")
    done

    # Add spacers between the lines and scores.
    away_line=$(printf "%s  " "$away_line")
    home_line=$(printf "%s  " "$home_line")

    for i in $(seq 0 2); do
        len=${#away_scores[$i]}
        [[ ${#home_scores[$i]} -gt ${#away_scores[$i]} ]] && len=${#home_scores[$i]}

        away_line=$(printf "%s %${len}s" "$away_line" "${away_scores[$i]:-" "}")
        home_line=$(printf "%s %${len}s" "$home_line" "${home_scores[$i]:-" "}")
    done

    printf "%s  %-10.10s\n" "$away_line" \
        "$(formatted_where "${games[$(( $offset + $IX_STATUS)) ]}" "${games[$(( $offset + $IX_WHERE)) ]}")"

    printf "%s\n" "$home_line"


    return
}


#
# print_gamecenter
#
# Sent: nothing
# Return: nothing
# Purpose:
#
#   Print a gamecenter.
#
function print_gamecenter {

    local game_id=${gc_sections[$GC_SECTION_GAME_ID]};

    local offset=${games_index[$game_id]}

    if [[ $orient == $VERTICAL ]]; then
        #                      row col height width
        declare -a        line_score=(  3  1  2 51 )
        declare -a         away_team=(  6  2  1  3 )
        declare -a         home_team=(  6 31  1  3 )
        declare -a    away_batters_h=(  6 15  1  8 )
        declare -a      away_batters=(  7  1  9 22 )
        declare -a    home_batters_h=(  6 44  1  8 )
        declare -a      home_batters=(  7 30  9 22 )
        declare -a   away_pitchers_h=( 17 14  1 16 )
        declare -a     away_pitchers=( 18  1  5 29 )
        declare -a   home_pitchers_h=( 17 43  1 16 )
        declare -a     home_pitchers=( 18 30  5 29 )
        declare -a          at_pit_h=( 24  1  1 45 )
        declare -a            at_pit=( 25  1  1 45 )
        declare -a          at_bat_h=( 27  1  1 39 )
        declare -a            at_bat=( 28  1  1 39 )
        declare -a               bso=( 30  1  3  5 )
        declare -a           runners=( 30 11  3 20 )
        declare -a  current_at_bat_h=( 34  1  1 80 )
        declare -a    current_at_bat=( 35  1  9 80 )
        declare -a    play_by_play_h=( 44  1  1 80 )
        declare -a      play_by_play=( 45  1 10 80 )
        declare -a scoring_summary_h=( 55  1  1 80 )
        declare -a   scoring_summary=( 56  1 10 80 )
    else
        #                      row col height width
        declare -a        line_score=(  3  1  2 51 )
        declare -a         away_team=(  6  2  1  3 )
        declare -a         home_team=(  6 31  1  3 )
        declare -a    away_batters_h=(  6 15  1  8 )
        declare -a      away_batters=(  7  1  9 22 )
        declare -a    home_batters_h=(  6 44  1  8 )
        declare -a      home_batters=(  7 30  9 22 )
        declare -a   away_pitchers_h=( 17 14  1 16 )
        declare -a     away_pitchers=( 18  1  5 29 )
        declare -a   home_pitchers_h=( 17 43  1 16 )
        declare -a     home_pitchers=( 18 30  5 29 )
        declare -a          at_pit_h=(  6 62  1 45 )
        declare -a            at_pit=(  7 62  1 45 )
        declare -a          at_bat_h=(  9 62  1 39 )
        declare -a            at_bat=( 10 62  1 39 )
        declare -a               bso=(  2 62  3  5 )
        declare -a           runners=(  2 72  3 20 )
        declare -a  current_at_bat_h=( 12 62  1 50 )
        declare -a    current_at_bat=( 13 62  9 50 )
        declare -a    play_by_play_h=( 23 62  1 50 )
        declare -a      play_by_play=( 24 62 10 50 )
        declare -a scoring_summary_h=( 23  2  1 58 )
        declare -a   scoring_summary=( 24  2 10 58 )
    fi

    block_print $(block_coordinates ${line_score[@]}) "$( print_game "${gc_sections[$GC_SECTION_GAME_IS]}")"

    block_print $(block_coordinates ${away_team[@]}) "${games[$(( $offset + $IX_AWAY_ABBR)) ]}"
    block_print $(block_coordinates ${home_team[@]}) "${games[$(( $offset + $IX_HOME_ABBR)) ]}"

    echo -ne "$colour_heading"
    block_print $(block_coordinates ${away_batters_h[@]}) "AB R H I"
    block_print $(block_coordinates ${home_batters_h[@]}) "AB R H I"
    block_print $(block_coordinates ${away_pitchers_h[@]}) "IP  PC  H E B K"
    block_print $(block_coordinates ${home_pitchers_h[@]}) "IP  PC  H E B K"
    block_print $(block_coordinates ${at_pit_h[@]}) "Pitching   Throws IP     W-L  ERA   Ks  BB"
    block_print $(block_coordinates ${at_bat_h[@]}) "At Bat      Bats  AB  AVG HR RBI   R SB"
    block_print $(block_coordinates ${play_by_play_h[@]}) "= Current Inning Play by Play ="
    block_print $(block_coordinates ${current_at_bat_h[@]}) "= Current At Bat ="
    block_print $(block_coordinates ${scoring_summary_h[@]}) "= Scoring Summary ="
    echo -ne "$COLOUR_OFF"

    block_print $(block_coordinates ${away_batters[@]}) "$(print_batters "${gc_sections[$GC_SECTION_AWAY_BATTERS]}")"
    block_print $(block_coordinates ${home_batters[@]}) "$(print_batters "${gc_sections[$GC_SECTION_HOME_BATTERS]}")"
    block_print $(block_coordinates ${away_pitchers[@]}) "$(print_pitchers "${gc_sections[$GC_SECTION_AWAY_PITCHER_ORDER]}")"
    block_print $(block_coordinates ${home_pitchers[@]}) "$(print_pitchers "${gc_sections[$GC_SECTION_HOME_PITCHER_ORDER]}")"
    block_print $(block_coordinates ${at_pit[@]})   "$(print_at_pitch)"
    block_print $(block_coordinates ${at_bat[@]})   "$(print_at_bat)"
    block_print $(block_coordinates ${bso[@]})      "$(print_bso)"
    block_print $(block_coordinates ${runners[@]})  "$(print_runners)"
    block_print $(block_coordinates ${play_by_play[@]}) "$(print_play_by_play)"
    block_print $(block_coordinates ${current_at_bat[@]}) "$(print_current_at_bat)"
    block_print $(block_coordinates ${scoring_summary[@]}) "$(print_scoring_summary)"

    echo ""
    return
}

#
# print_games
#
# Sent: nothing
# Return: nothing
# Purpose:
#
#   Print all games.
#
function print_games {

    local i
    for i in ${!games_index[@]}; do
        print_game "$i"
        echo ""
    done

    return
}


#
# print_pitcher
#
# Sent: id
# Return: nothing
# Purpose:
#
#   Print game stats for a single pitcher.
#
#   Halladay   8.0  115   7   1   1   5
#
function print_pitcher {

    local id=$1
    local highlight=$2

    stat_str="${gc_pitchers[$id]}"

    [[ -z $stat_str ]] && return


    saveIFS=$IFS
    IFS=','
    declare -a stats=( $stat_str );
    IFS=$saveIFS

    # Some stats have no spaces between them but they are almost always a
    # single digit so not a problem.

    printf "%s%-10.10s %3s %3s %2s%2s%2s%2s\n" \
        "${highlight:- }" \
        "${stats[0]/*&nbsp;/}" \
        ${stats[1]} \
        ${stats[2]} \
        ${stats[3]} \
        ${stats[4]} \
        ${stats[5]} \
        ${stats[6]}

}


#
# print_pitchers
#
# Sent: nothing
# Return: nothing
# Purpose:
#
#   Print a game stats for a list of pitchers.
#
#   Halladay   8.0  115   7   1   1   5
#   Downs      1.0   12   0   0   0   3
#
function print_pitchers {

    local list="$1"

    saveIFS=$IFS
    IFS=','
    declare -a ids=( $list );
    declare -a at_pit_stats=(${gc_sections[$GC_SECTION_PITCHER_ID]});
    IFS=$saveIFS

    local hl
    local id

    for id in "${ids[@]}"; do
        hl=
        [[ "${at_pit_stats[0]}" == "$id" ]] && hl='*'

        print_pitcher "$id" "$hl"
    done

    return
}


#
# print_play_by_play
#
# Sent: nothing
# Return: nothing
# Purpose:
#
#   Print current inning play by play.
#
#   Wells doubled to deep left center, Snider and Scutaro scored, Hill out at home.
#   Hill walked, Scutaro to second.
#   Scutaro reached on an infield single, Snider to third.
#   Snider singled to center.
#
function print_play_by_play {

    # The play by play section contains records ^ delimited.

    saveIFS=$IFS
    IFS='^'
    declare -a plays=(${gc_sections[$GC_SECTION_CURRENT_PLAYBYPLAY]});
    IFS=$saveIFS

    local i
    for i in $(seq 1 ${#plays[@]}); do
        printf "%s\n" "${plays[$i]}"
    done

    return
}


#
# print_runners
#
# Sent: nothing
# Return: nothing
# Purpose:
#
#   Print the current at bat balls, strikes and outs.
#
#    First : -
#    Second: * Wells
#    Third : -
#
function print_runners {

    # The runners_ids section is a ~ delimited list of player records. The fields
    # (player id, bats, number, name) are delimited by a comma.

    saveIFS=$IFS
    IFS='~'
    declare -a runners=(${gc_sections[$GC_SECTION_RUNNER_IDS]});
    IFS=$saveIFS

    declare -a runner_names=( '' '' '' )
    declare -a labels=('1st' '2nd' '3rd')

    for i in $( seq 0 2 ); do
        IFS=','
        declare -a runner_specs=(${runners[$i]});
        IFS=$saveIFS

        printf "%s: %-10.10s\n" \
            "${labels[$i]}" \
            "${runner_specs[3]/*&nbsp;/}"

    done

    return
}


#
# print_scoring_summary
#
# Sent: nothing
# Return: nothing
# Purpose:
#
#   Print the game scoring summary.
#
# 1st Overbay singled to center, Snider and Rolen scored.
# 2nd Rodriguez reached on fielder's choice to third, Jeter scored, Posida out at second.
# 6th Vernon Wells solo shot to right off Petitte. Rios solo shot to left off Petitte.
#
function print_scoring_summary {

    # The play by play section contains records ^ delimited.
    # Fields are ~ delimited.
    # 0 - team, 0 - away, 1 - home
    # 1 - inning, eg 1st
    # 2,3... - description, eg Rod Barajas (1) solo run shot to left center

    saveIFS=$IFS
    IFS='^'
    declare -a records=(${gc_sections[$GC_SECTION_SCORING_SUMMARY]});
    IFS=$saveIFS

    for record in "${records[@]}"; do

        team="${games[$(( $offset + $IX_HOME_ABBR)) ]}"
        [[ "${record%%~*}" == "0" ]] && team="${games[$(( $offset + $IX_AWAY_ABBR)) ]}"

        # Strip off team
        data=${record#*~}
        inning=${data%%~*}

        saveIFS=$IFS
        IFS='~'
        declare -a fields=(${data#*~});
        IFS=$saveIFS

        for field in "${fields[@]}"; do
            text=$( echo "$field" | sed -e 's/<[/]*[bi]>//g' | tr "~" "\n  " | fmt -w 50 -t | sed -e 's/^   /        /')
            printf "%-3.3s %-3.3s %s\n" "$team" "$inning" "$text"
            team=""
            inning=""
        done
    done

    return
}


#
# tests
#
# Sent: nothing
# Return: nothing
# Purpose:
#
#   Return tests.
#
function tests {

    offset=0

    for i in ${!index_fields[@]}; do
        local offset=$(eval echo \${index_fields[i]} )
        #printf "%20s => %s\n" "${index_fields[i]}" "${games[$offset]}"
    done

    return
}


colour_heading=""
colour_highlight=""
colour_strike=""
colour_ball=""
colour_foul=""
orientation=

# Source rc file if it exists
rcfile="$HOME/.mlbrc"

if [[ -e $rcfile ]]; then
    source $rcfile
fi

use_test_files=
while getopts "ho:t" options; do
  case $options in
    o ) orientation=$OPTARG;;

    h ) usage
        exit 0;;
    t ) use_test_files=1;;
    \?) usage
        exit 1;;
    * ) usage
        exit 1;;

  esac
done

shift $(($OPTIND - 1))

which wget > /dev/null 2>&1
if [[ "$?" -ne "0" ]]; then
    echo "ERROR: Requires wget." >&2
    exit 1
fi


game=$1

# Cursor control

CURSOR_HOME="\e[H"          # Set cursor at home position
CURSOR_UP="\e[XA"           # Move cursor up one row. The number can be changed to move several rows.
CURSOR_DOWN="\e[XB"         # Move cursor down one row. The number can be changed to move several rows.
CURSOR_FORWARD="\e[XC"      # Move cursor forward one column. The number can be changed to move several columns.
CURSOR_BACKWARD="\e[XD"     # Move cursor backward one column. The number can be changed to move several columns.
CURSOR_POSITION="\e[X;Yf"   # Move cursor to position 1,2. Use whatever coordinates.
CURSOR_SAVE="\e[s"          # Save cursor position
CURSOR_UNSAVE="\e[u"        # Restore saved cursor position
CURSOR_SAVE_ATTR="\e7"      # Save cursor position and attributes.
CURSOR_UNSAVE_ATTR="\e8"    # Restore saved cursor position and attributes.
CURSOR_HIDE="\e[?25l"       # Hide cursor
CURSOR_SHOW="\e[?25h"       # Show cursor

COLUMNS=$(tput cols)
LINES=$(tput lines)
VERTICAL=0
HORIZONTAL=1

[[ $orientation == "h" ]] && orient=$HORIZONTAL
[[ $orientation == "v" ]] && orient=$VERTICAL

if [[ -z $orient ]]; then
    orient=$VERTICAL
    [[ $(echo "$COLUMNS > ($LINES * 3 / 2)" | bc) -eq "1" ]] && orient=$HORIZONTAL
fi

COLOUR_OFF="\e[0m" # No Color

colouring=
[[ -n $colour_ball || -n $colour_strike || -n $colour_foul || -n $colour_highlight ]] && colouring=1


# Game index variables

declare -a games_index
declare -a games


saveIFS=$IFS
IFS=$'\n'
declare -a index_fields=(
    IX_ID
    IX_PAGE
    IX_AWAY
    IX_HOME
    IX_AWAY_ABBR
    IX_HOME_ABBR
    IX_X1
    IX_X2
    IX_X3
    IX_X4
    IX_X5
    IX_STATUS
    IX_WHERE
    IX_AWAY_LINE
    IX_AWAY_SCORE
    IX_HOME_LINE
    IX_HOME_SCORE
    IX_BSO
    IX_INNING
    IX_BASES
    IX_GAME_TEXT
    IX_GAME_HRS
    IX_AWAY_RECORD
    IX_HOME_RECORD
    IX_INNING_TEXT
    IX_AWAY_STANDING
    IX_HOME_STANDING
    IX_AWAY_STREAK
    IX_HOME_STREAK
    IX_UNKNOWN_ID
    IX_LEAGUE_ABBR
    IX_PITCHING_CHANGE
    IX_PHOTO_URL
    IX_UNKNOWN_TEXT
    IX_AWAY_ABBR_LC
    IX_HOME_ABBR_LC
    IX_GLOG_FLAG
    IX_PERFORMANCE_ALERT
    IX_LEAGUE_ALERT_TEXT
    IX_SHORT_LAST_PLAY
);
IFS=$saveIFS

# Create constant variables, each assigned the value of their index
# Eg IX_ID=0, IX_PAGE=1, etc
for i in ${!index_fields[@]}; do
    declare ${index_fields[i]}=$i
done

IX_FIELDS=${#index_fields[@]}



# Game center variables

declare -a gc_sections
declare -a gc_batters
declare -a gc_bench_batters
declare -a gc_pitchers
declare -a gc_bullpen_pitchers

saveIFS=$IFS
IFS=$'\n'
declare -a gc_fields=(
    GC_SECTION_GAME_ID
    GC_SECTION_VENUE
    GC_SECTION_BATTER_LIST
    GC_SECTION_AWAY_BATTERS
    GC_SECTION_HOME_BATTERS
    GC_SECTION_BENCH_LIST
    GC_SECTION_AWAY_BENCH_ORDER
    GC_SECTION_HOME_BENCH_ORDER
    GC_SECTION_PLAYED_LIST
    GC_SECTION_AWAY_PLAYED_ORDER
    GC_SECTION_HOME_PLAYED_ORDER
    GC_SECTION_AT_BAT_ID
    GC_SECTION_AT_BAT_OPPONENT_ID
    GC_SECTION_PITCHER_ID
    GC_SECTION_RUNNER_IDS
    GC_SECTION_PITCHER_LIST
    GC_SECTION_AWAY_PITCHER_ORDER
    GC_SECTION_HOME_PITCHER_ORDER
    GC_SECTION_BULLPEN_LIST
    GC_SECTION_AWAY_BULLPEN_ORDER
    GC_SECTION_HOME_BULLPEN_ORDER
    GC_SECTION_CURRENT_PITCHER_SPLIT_DATA
    GC_SECTION_CURRENT_BATTER_SPLIT_DATA
    GC_SECTION_CURRENT_RUNNERS_SPLIT_DATA
    GC_SECTION_PITCH_LOCATION
    GC_SECTION_CURRENT_PLAYBYPLAY
    GC_SECTION_SCORING_SUMMARY
    GC_SECTION_X1
    GC_SECTION_TOP_BOTTOM
    GC_SECTION_X2
    GC_SECTION_HIT_CHARTS_AVAILABILITY
    GC_SECTION_CURRENT_BATTER_SEASON_STATS
    GC_SECTION_AWAY_PLAYERS_ON_FIELD
    GC_SECTION_HOME_PLAYERS_ON_FIELD
    GC_SECTION_HIT_CHART_LIVE_DATA
    GC_SECTION_X3
    GC_SECTION_HOT_COLD_ZONES
    GC_SECTION_WEATHER
    GC_SECTION_X4
    GC_SECTION_X5
    GC_SECTION_PLAYER_AT_BAT_STATS
    GC_SECTION_PITCHERS_WARMING_UP
);
IFS=$saveIFS

# Create constant variables, each assigned the value of their index
# Eg GC_SECTION_GAME_ID=0, GC_SECTION_VENUE=1, etc
for i in ${!gc_fields[@]}; do
    declare ${gc_fields[i]}=$i
done

GC_SECTIONS=${#gc_fields[@]}


index_file=$(mkdir -p /tmp/tools && echo /tmp/tools/cbs_mlb_index.txt)
gamecenter_file=$(mkdir -p /tmp/tools && echo /tmp/tools/cbs_mlb_gamecenter.txt)

if [[ -n $use_test_files ]]; then
    index_file=$(mkdir -p /tmp/tools && echo /tmp/tools/cbs_test_index.txt)
    gamecenter_file=$(mkdir -p /tmp/tools && echo /tmp/tools/cbs_test_gamecenter.txt)
fi

[[ ! -n $use_test_files ]] && download

parse_games_index
parse_games

if [[ -n $game ]]; then

    parse_gamecenter
    parse_gamecenter_players
fi

if [[ -n $game ]]; then
    print_gamecenter
else
    print_games
fi

[[ -n $use_test_files ]] && tests
