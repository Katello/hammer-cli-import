#!/bin/bash

HAMMER="env RUBYOPT=-I../lib hammer"
CSV_DIR="data"


die() {
   echo "$*" >&2
   exit 1
}

# params: subcommand
count_entities() {
    # workaround due to Bug 1094635
    if [[ "repository" =~ $1 ]]; then
        return
    fi
    if [[ "organization user" =~ $1 ]]; then
        echo $( $HAMMER --csv $1 list | sed '1 d' | wc -l )
    else
        COUNT=0
        for org_id in $(get_org_ids); do
            COUNT_ORG=$($HAMMER --csv $1 list --organization-id="$org_id" | sed '1 d' | wc -l)
#COUNT_ORG=1
            let "COUNT=$COUNT + $COUNT_ORG"
        done
        echo $COUNT
    fi
}

get_org_ids() {
    echo $( $HAMMER --output=base organization list | sed -n 's/^Id:\s*//p' )
}

# params: subcommand, csv_file, extra cmd arguments
import_cmd() {
    COUNT1=$(count_entities $1)
    $HAMMER import $1 --csv-file=$2 $3
    RET=$?
    if [ "$RET" -ne 0 ]; then
        die "'$HAMMER import $1 --csv-file=$2 $3' failed with $RET."
    fi
    COUNT2=$(count_entities $1)
    # workaround due to Bug 1094635
    if [[ "repository" =~ $1 ]]; then
        return
    fi
    # echo "$1 COUNT: $COUNT1 -> $COUNT2"
    if [ "$3" == "--delete" ]; then
        let "COUNT2_EXP = $COUNT1 - 1"
    else
        let "COUNT2_EXP = $COUNT1 + 1"
     fi
    if [ $COUNT2 -ne $COUNT2_EXP ]; then
        die "Expecting $COUNT2_EXP $1(s) instead of $COUNT2."
    fi
}


# create entities
import_cmd organization ${CSV_DIR}/users.csv
import_cmd user ${CSV_DIR}/users.csv --new-passwords=new-passwords.csv
import_cmd host-collection ${CSV_DIR}/system-groups.csv
import_cmd repository ${CSV_DIR}/repositories.csv

if [ "$1" != "--just-create" ]; then
    # delete entities in reverse order
    import_cmd repository ${CSV_DIR}/repositories.csv --delete
    import_cmd host-collection ${CSV_DIR}/system-groups.csv --delete
    import_cmd user ${CSV_DIR}/users.csv --delete
    import_cmd organization ${CSV_DIR}/users.csv --delete
fi

