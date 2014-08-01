#!/bin/bash

HAMMER="env RUBYOPT=-I../lib hammer"
CSV_DIR="data"


die() {
   echo "$*" >&2
   exit 1
}

# params: subcommand
count_entities() {
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
    echo $HAMMER import $1 --csv-file=$2 $3 $4 --verbose
    $HAMMER import $1 --csv-file=$2 $3 $4 --verbose
}


# create entities
import_cmd organization ${CSV_DIR}/users.csv
import_cmd user ${CSV_DIR}/users.csv --new-passwords=new-passwords.csv
import_cmd host-collection ${CSV_DIR}/system-groups.csv
import_cmd repository ${CSV_DIR}/repositories.csv --synchronize --wait
TMP=$(mktemp -d)
chmod o+rx ${TMP}
cp -r ${CSV_DIR}/export.csv $(ls ${CSV_DIR}/*/ -d) ${TMP}
import_cmd content-view ${TMP}/export.csv --synchronize --wait

if [ "$1" != "--just-create" ]; then
    # delete entities in reverse order
    import_cmd content-view ${CSV_DIR}/export.csv --delete
    rm -rf ${{TMP}
    import_cmd repository ${CSV_DIR}/repositories.csv --delete
    import_cmd host-collection ${CSV_DIR}/system-groups.csv --delete
    import_cmd user ${CSV_DIR}/users.csv --delete
    rm -f new-passwords.csv
    import_cmd organization ${CSV_DIR}/users.csv --delete
fi

