#!/bin/sh

readonly CONFDIR="/etc/sbfspot"
readonly HOMEDIR="/usr/local/bin/sbfspot.3"
readonly DATADIR="/var/sbfspot"
sbfspotbinary=""
sbfspotuploadbinary=""
sbfspot_cfg_file=""
sbfspot_upload_cfg_file=""
sbfspot_options=""

getConfigValue() {
    key=$1
    echo "$sbfspot_cfg_file" | grep -e "^$key=" | cut -f 2 -d "=" | sed 's/[    ]*$//' # search for key, get value, delete invisible chars at the end
}

setConfigValue() {
    key=$1
    value=$2
    temp_value="$(getConfigValue "$key")"
    if [ -n "$temp_value" ]; then   # key found, so update new value
        echo "$sbfspot_cfg_file" | sed "/^$key=.*/c $key=$value" > $CONFDIR/SBFspot.cfg
    else
        temp_value="$(getConfigValue "#$key")"  # search for inactive key
        if [ -n "$temp_value" ]; then  # append key=value after the first match
            echo "$sbfspot_cfg_file" | sed "0,/^#$key/!b;//a$key=$value" > $CONFDIR/SBFspot.cfg
        else
            temp_value="$(getConfigValue "# $key")"   # no inactive key found, test again with space after hashtag
            if [ -n "$temp_value" ]; then  # append key=value after the first match
                echo "$sbfspot_cfg_file" | sed "0,/^# $key/!b;//a$key=$value" > $CONFDIR/SBFspot.cfg
            else
                echo "Cannot find the option \"$key\" in SBFspot.cfg. Appending the option at the end of the file."
                echo "$sbfspot_cfg_file" | sed "\$a $key=$value" > $CONFDIR/SBFspot.cfg
            fi
        fi
    fi
    readConfig
}

readConfig() {
    sbfspot_cfg_file=$( cat $CONFDIR/SBFspot.cfg | dos2unix -u )
}

getUploadConfigValue() {
    key=$1
    echo "$sbfspot_upload_cfg_file" | grep -e "^$key=" | cut -f 2 -d "=" | sed 's/[     ]*$//' # search for key, get value, delete invisible chars at the end
}

setUploadConfigValue() {
    key=$1
    value=$2
    temp_value="$(getUploadConfigValue "$key")"
    if [ -n "$temp_value" ]; then   # key found, so update new value
        echo "$sbfspot_upload_cfg_file" | sed "/^$key=.*/c $key=$value" > $CONFDIR/SBFspotUpload.cfg
    else
        temp_value="$(getUploadConfigValue "#$key")"  # search for inactive key
        if [ -n "$temp_value" ]; then  # append key=value after the first match
            echo "$sbfspot_upload_cfg_file" | sed "0,/^#$key/!b;//a$key=$value" > $CONFDIR/SBFspotUpload.cfg
        else
            temp_value="$(getUploadConfigValue "# $key")"   # no inactive key found, test again with space after hashtag
            if [ -n "$temp_value" ]; then  # append key=value after the first match
                echo "$sbfspot_upload_cfg_file" | sed "0,/^# $key/!b;//a$key=$value" > $CONFDIR/SBFspotUpload.cfg
            else
                echo "Cannot find the option \"$key\" in SBFspotUpload.cfg. Appending the option at the end of the file."
                echo "$sbfspot_upload_cfg_file" | sed "\$a $key=$value" > $CONFDIR/SBFspotUpload.cfg
            fi
        fi
    fi
    readUploadConfig
}

readUploadConfig() {
    sbfspot_upload_cfg_file=$(cat $CONFDIR/SBFspotUpload.cfg | dos2unix -u)
}

checkSBFConfig() {
    ERROR_FLAG=0
    if grep -qs "$CONFDIR " /proc/mounts; then
        if [ -r "$CONFDIR/SBFspot.cfg" ]; then
            readConfig
            if [ -n "$CSV_STORAGE" ] && [ "$CSV_STORAGE" -eq 1 ]; then
                    if [ "$(getConfigValue CSV_Export)" -eq 0 ]; then
                    if [ -w $CONFDIR/SBFspot.cfg ]; then
                        setConfigValue "CSV_Export" "1"
                        echo "Wrong CSV_Export value in SBFspot.cfg. I change it to 1."
                    else
                            echo "$CONFDIR/SBFspot.cfg is not writeable by User with ID $(id -u sbfspot)."
                        echo "Please change file permissions of SBFspot.cfg or ensure, that the \"CSV_Export\""
                        echo "value is 1"
                        ERROR_FLAG=1
                    fi
                fi
            fi
            if [ "$(getConfigValue CSV_Export)" -eq 1 ]; then   # if CSV_Export=1 then OutputPath and OutputPathEvents must point to /var/sbfspot
                if grep -qs "$DATADIR " /proc/mounts; then
                    if [ -w $CONFDIR/SBFspot.cfg ]; then
                            if ! getConfigValue OutputPath | grep -q -e "^/var/sbfspot$" && \
                                    ! getConfigValue OutputPath | grep -q -e "^/var/sbfspot/"; then
                            setConfigValue "OutputPath" "$DATADIR/%Y"
                            echo "Wrong OutputPath value in SBFspot.cfg. I change it to \"$DATADIR/%Y\""
                        fi

                        if ! getConfigValue OutputPathEvents | grep -q -e "^/var/sbfspot$" && \
                                ! getConfigValue OutputPathEvents | grep -q -e "^/var/sbfspot/"; then
                            setConfigValue "OutputPathEvents" "$DATADIR/%Y/Events"
                            echo "Wrong OutputPathEvents value in SBFspot.cfg. I change it to \"$DATADIR/%Y/Events\""
                        fi
                    else
                            echo "$CONFDIR/SBFspot.cfg is not writeable by User with ID $(id -u sbfspot)."
                        echo "Please change file permissions of SBFspot.cfg or ensure, that the \"OutputPath\" and \"OutputPathEvents\" Options"
                        echo "point to the Directory $DATADIR/..."
                        ERROR_FLAG=1
                    fi
                else
                    echo "$DATADIR is not mapped to a directory outside the container => csv files would not be persistant."
                    echo "Please map the directory and restart the container."
                    exit 1
                fi

                # check if data directory is writeable
                if [ ! -w "$DATADIR" ]; then
                    echo "Mapped Data directory is not writeable for user with ID $(id -u sbfspot)."
                    echo "Please change file permissions accordingly and restart the container."
                    exit 1
                fi
            fi
            if [ -n "$MQTT_ENABLE" ] && [ "$MQTT_ENABLE" -eq 1 ]; then
                    if ! getConfigValue MQTT_Publisher | grep -q -e "^/usr/bin/mosquitto_pub"; then
                    setConfigValue "MQTT_Publisher" "/usr/bin/mosquitto_pub"
                    echo "Wrong MQTT_Publisher value in SBFspot.cfg corrected."
                fi
                if getConfigValue MQTT_Host | grep -q -e "^test.mosquitto.org"; then
                    echo "Warning: Please configure the \"MQTT_Host\" value in SBFspot.cfg."
                fi
            fi
            if [ "$DB_STORAGE" = "sqlite" ]; then
                if grep -qs "$DATADIR " /proc/mounts; then # check if data dir is mapped into the container
                    if [ ! -e "$DATADIR/sbfspot.db" ]; then # check if database file exists
                        if [ -z "$INIT_DB" ] || [ "$INIT_DB" -ne 1 ]; then
                            echo "SQLite database file under \"$DATADIR/sbfspot.db\" does not exist. Please initialize the database."
                            exit 1
                        fi
                    else
                        if [ ! -w "$DATADIR/sbfspot.db" ]; then
                                echo "SQLite database file under \"$DATADIR/sbfspot.db\" is not writeable for user with ID $(id -u sbfspot)."
                            echo "Please change file permissions accordingly and restart the container."
                            ERROR_FLAG=1
                        fi
                        if [ ! -r "$DATADIR/sbfspot.db" ]; then
                                echo "SQLite database file under \"$DATADIR/sbfspot.db\" is not readable for user with ID $(id -u sbfspot)."
                            echo "Please change file permissions accordingly and restart the container."
                            ERROR_FLAG=1
                        fi
                    fi
                else
                    echo "$DATADIR is not mapped to a directory outside the container => database would not be persistant."
                    echo "Please map the directory and restart the container."
                    exit 1
                fi

                if [ -w "$CONFDIR/SBFspot.cfg" ]; then # check if SQLite DB is correctly configured in SBFspot.cfg
                        if ! getConfigValue SQL_Database | grep -q -e "^$DATADIR/sbfspot.db"; then
                        setConfigValue "SQL_Database" "$DATADIR/sbfspot.db"
                        echo "Wrong SQL_Database value in SBFspot.cfg. I change it to \"$DATADIR/sbfspot.db\""
                    fi
                else
                        echo "$CONFDIR/SBFspot.cfg is not writeable by User with ID $(id -u sbfspot)."
                    echo "Please change file permissions of SBFspot.cfg or ensure, that the \"SQL_Database\" option"
                    echo "points to the file $DATADIR/sbfspot.db"
                    ERROR_FLAG=1
                fi
            fi
        else
                echo "$CONFDIR/SBFspot.cfg is not readable by user with ID $(id -u sbfspot)."
            echo "Please change file permissions accordingly and restart the container."
            exit 1
        fi
    else
        echo "$CONFDIR is not mapped to a directory outside the container => Config file can't be read."
                echo "Please map the directory and restart the container."
                exit 1
    fi

    if [ $ERROR_FLAG -eq 1 ]; then
        echo "Please configure the listed value(s) and restart the container."
        exit 1
    fi
}

checkSBFUploadConfig() {
    ERROR_FLAG=0
        if grep -qs "$CONFDIR " /proc/mounts; then
        if [ -r "$CONFDIR/SBFspotUpload.cfg" ]; then
            readUploadConfig
            tempValue=$(getUploadConfigValue PVoutput_SID)
            if [ -z "$tempValue" ];then
                echo "Please set the \"PVoutput_SID\" option in \"SBFspotUpload.cfg\"."
                echo "Otherwise the production data can't be uploaded to PVoutput."
                ERROR_FLAG=1
            fi
            tempValue=$(getUploadConfigValue PVoutput_Key)
            if [ -z "$tempValue" ];then
                echo "Please set the \"PVoutput_Key\" option in \"SBFspotUpload.cfg\"."
                echo "Otherwise the production data can't be uploaded to PVoutput."
                ERROR_FLAG=1
            fi

            if [ "$DB_STORAGE" = "sqlite" ]; then # check if SQLite DB is correctly configured in SBFspot.cfg
                    if ! getUploadConfigValue SQL_Database | grep -q -e "^$DATADIR/sbfspot.db"; then
                    if [ -w "$CONFDIR/SBFspotUpload.cfg" ]; then
                        setUploadConfigValue "SQL_Database" "$DATADIR/sbfspot.db"
                        echo "Wrong SQL_Database value in SBFspotUpload.cfg. I change it to \"$DATADIR/sbfspot.db\""
                    else
                            echo "$CONFDIR/SBFspotUpload.cfg is not writeable by User with ID $(id -u sbfspot)."
                        echo "Please change file permissions of SBFspotUpload.cfg or ensure, that the \"SQL_Database\" option"
                        echo "points to the file $DATADIR/sbfspot.db"
                        ERROR_FLAG=1
                    fi
                fi
            fi
        else
                echo "$CONFDIR/SBFspotUpload.cfg is not readable by user with ID $(id -u sbfspot)."
            echo "Please change file permissions accordingly and restart the container."
            exit 1
        fi
    else
        echo "$CONFDIR is not mapped to a directory outside the container => Config file can't be read."
                echo "Please map the directory and restart the container."
                exit 1
    fi

    if [ $ERROR_FLAG -eq 1 ]; then
        echo "Please configure the listed value(s) and restart the container."
        exit 1
    fi
}

setupSBFspotOptions() {
    if [ -n "$SBFSPOT_ARGS" ]; then
        sbfspot_options=" $SBFSPOT_ARGS "
    fi
    if [ -n "$FORCE" ] && [ "$FORCE" -eq 1 ]; then
        sbfspot_options="$sbfspot_options -finq"
    fi
    if [ -n "$FINQ" ] && [ "$FINQ" -eq 1 ]; then
        sbfspot_options="$sbfspot_options -finq"
    fi
    if [ -n "$QUIET" ] && [ "$QUIET" -eq 1 ]; then
        sbfspot_options="$sbfspot_options -q"
    fi
    if [ -n "$MQTT_ENABLE" ] && [ "$MQTT_ENABLE" -eq 1 ]; then
        sbfspot_options="$sbfspot_options -mqtt"
    fi
}

initDatabase() {
    if [ "$DB_STORAGE" = "sqlite" ]; then
        if grep -qs "$DATADIR " /proc/mounts; then
            # check if data directory is writeable
                        if [ ! -w "$DATADIR" ]; then
                                echo "Mapped Data directory is not writeable for user with ID $(id -u sbfspot)."
                                echo "Please change file permissions accordingly and restart the container."
                                exit 1
                        fi
            sqlite3 "$DATADIR/sbfspot.db" < "$HOMEDIR/CreateSQLiteDB.sql"
        else
            echo "$DATADIR is not mapped to a directory outside the container => database would not be persistant."
            echo "Please map the directory and restart the container."
            exit 1
        fi
        exit 0
    elif [ "$DB_STORAGE" = "mysql" ] || [ "$DB_STORAGE" = "mariadb" ]; then
        HOST=$(getConfigValue SQL_Hostname)
        DB=$(getConfigValue SQL_Database)
        USER=$(getConfigValue SQL_Username)
        PW=$(getConfigValue SQL_Password)
        LOCAL_IP=$(ip ro show | grep 'docker0\|eth0' | awk '{print $(NF)}')

        ERROR_FLAG=0
        if [ -z "$HOST" ]; then
            ERROR_FLAG=1
            echo "No SQL_Hostname configured in SBFspot.cfg."
        fi
        if [ -z "$DB" ]; then
            ERROR_FLAG=1
            echo "No SQL_Database configured in SBFspot.cfg."
        fi
        if [ -z "$USER" ]; then
            ERROR_FLAG=1
            echo "No SQL_Username configured in SBFspot.cfg."
        fi
        if [ -z "$PW" ]; then
            ERROR_FLAG=1
            echo "No SQL_Password configured in SBFspot.cfg."
        fi
        if [ -z "$DB_ROOT_USER" ]; then
            ERROR_FLAG=1
            echo "Add \"DB_ROOT_USER\" Environment Variable with appropriate value e.g. \"root\" to your docker run command."
        fi
        if [ -z "$DB_ROOT_PW" ]; then
            ERROR_FLAG=1
            echo "Add \"DB_ROOT_PW\" Environment Variable with appropriate value to your docker run command."
        fi
        if [ $ERROR_FLAG -eq 1 ]; then
            echo "Please configure the listed value(s) and restart the container."
            exit 1
        fi

        if mysql -h "$HOST" --protocol=TCP -u "$DB_ROOT_USER" -p"$DB_ROOT_PW" < "$HOMEDIR/CreateMySQLDB.sql"; then
            echo "Database, tables and views created."
        else
            cp "$HOMEDIR/CreateMySQLDB.sql" "$DATADIR"
            echo "Error creating SBFspot Database, tables and views. Please manually add the file \"CreateMySQLDB.sql\""
            echo "(located in SBFspots data directory) to your Database, if the Database does not exist yet."
        fi
        SQL_USER_ADD="CREATE USER '$USER'@'$LOCAL_IP' IDENTIFIED BY '$PW';"
        SQL_USER_CHANGE="ALTER USER '$USER'@'$LOCAL_IP' IDENTIFIED BY '$PW';"
        SQL_GRANT1="GRANT INSERT,SELECT,UPDATE ON SBFspot.* TO '$USER'@'$LOCAL_IP';"
        SQL_GRANT2="GRANT DELETE,INSERT,SELECT,UPDATE ON SBFspot.MonthData TO '$USER'@'$LOCAL_IP';"

        if mysql -h "$HOST" --protocol=TCP -u "$DB_ROOT_USER" -p"$DB_ROOT_PW" -e "SELECT User FROM mysql.user;" | grep -q -e "$USER"; then
            echo "User $USER exists in Database, only changing password"
            mysql -h "$HOST" --protocol=TCP -u "$DB_ROOT_USER" -p"$DB_ROOT_PW" -e "$SQL_USER_CHANGE"
        else
                if mysql -h "$HOST" --protocol=TCP -u "$DB_ROOT_USER" -p"$DB_ROOT_PW" -e "$SQL_USER_ADD"; then
                echo "Database User created"
            fi
        fi
        if mysql -h "$HOST" --protocol=TCP -u "$DB_ROOT_USER" -p"$DB_ROOT_PW" -e "$SQL_GRANT1"; then
            echo "Following rights for User $USER set"
            echo "$SQL_GRANT1"
        fi
        if mysql -h "$HOST" --protocol=TCP -u "$DB_ROOT_USER" -p"$DB_ROOT_PW" -e "$SQL_GRANT2"; then
            echo "Following rights for User $USER set"
            echo "$SQL_GRANT2"
        fi
            exit 0
    elif [ "$DB_STORAGE" != "sqlite" ] && [ "$DB_STORAGE" != "mysql" ] && [ "$DB_STORAGE" != "mariadb" ]; then
        echo "storage type \"$DB_STORAGE\" not available. Options: sqlite | mysql | mariadb"
        exit 1
    fi
}

selectSBFspotBinary() {
    if [ -n "$ENABLE_SBFSPOT" ] && [ "$ENABLE_SBFSPOT" -ne 0 ]; then
        if [ -z "$DB_STORAGE" ]; then
            sbfspotbinary=SBFspot_nosql
        elif [ "$DB_STORAGE" = "sqlite" ]; then
            sbfspotbinary=SBFspot_sqlite
        elif [ "$DB_STORAGE" = "mysql" ]; then
            sbfspotbinary=SBFspot_mysql
        elif [ "$DB_STORAGE" = "mariadb" ]; then
            sbfspotbinary=SBFspot_mariadb
        else
            echo "storage type \"$DB_STORAGE\" not available. Options: sqlite | mysql | mariadb"
            exit 1
        fi

        checkSBFConfig
    fi
}

selectSBFspotUploadBinary() {
    if [ -n "$ENABLE_SBFSPOT_UPLOAD" ] && [ "$ENABLE_SBFSPOT_UPLOAD" -ne 0 ]; then
        if [ "$DB_STORAGE" = "sqlite" ]; then
            sbfspotuploadbinary=SBFspotUploadDaemon_sqlite
        elif [ "$DB_STORAGE" = "mysql" ]; then
            sbfspotuploadbinary=SBFspotUploadDaemon_mysql
        elif [ "$DB_STORAGE" = "mariadb" ]; then
            sbfspotuploadbinary=SBFspotUploadDaemon_mariadb
        else
            echo "storage type \"$DB_STORAGE\" not available for SBFspotUploadDaemon. Options: sqlite | mysql | mariadb"
            exit 1
        fi

        checkSBFUploadConfig
    fi
}

copyDefaultConf() {
    if [ ! -e "$CONFDIR/SBFspot.default.cfg" ]; then
        cp "$HOMEDIR/SBFspot.default.cfg" "$CONFDIR" 2>/dev/null
        chmod 666 "$CONFDIR/SBFspot.default.cfg" 2>/dev/null
    fi
    if [ ! -e "$CONFDIR/SBFspotUpload.default.cfg" ]; then
        cp "$HOMEDIR/SBFspotUpload.default.cfg" "$CONFDIR" 2>/dev/null
        chmod 666 "$CONFDIR/SBFspotUpload.default.cfg" 2>/dev/null
    fi
}

checkStorageType() {
    if [ -z "$DB_STORAGE" ] && { [ -z "$CSV_STORAGE" ] || [ "$CSV_STORAGE" -ne 1 ]; } && { [ -z "$MQTT_ENABLE" ] || [ "$MQTT_ENABLE" -ne 1 ]; }; then
        echo "Error, no Data Output is selected. Please configure at least one of the options: DB_STORAGE, CSV_STORAGE or MQTT_ENABLE"
        exit 1
    fi
}

checkNoServiceSelected() {
    if { [ -z "$ENABLE_SBFSPOT" ] || [ "$ENABLE_SBFSPOT" -eq 0 ]; } && { [ -z "$ENABLE_SBFSPOT_UPLOAD" ] || [ "$ENABLE_SBFSPOT_UPLOAD" -eq 0 ]; }; then
        if [ -n "$INIT_DB" ] && [ "$INIT_DB" -ne 1 ]; then
            echo "Warning: Neither SBFspot nor SBFspotUploadDaemon were enabled"
            echo "Enable at least one by setting ENABLE_SBFSPOT or ENABLE_SBFSPOT_UPLOAD environment variable to 1"
            exit 1
        else
            checkSBFConfig   // if no service but "$INIT_DB" is selected, checkSBFConfig has to be called
        fi
    fi
}

############################################################################################################################################

# Scriptstart

############################################################################################################################################

copyDefaultConf

checkStorageType

checkNoServiceSelected

selectSBFspotBinary

selectSBFspotUploadBinary

# initialize Database
if [ -n "$INIT_DB" ] && [ "$INIT_DB" -eq 1 ]; then
    initDatabase
else
    if [ -n "$DB_ROOT_USER" ] || [ -n "$DB_ROOT_PW" ]; then
        echo "Please delete the environment variables \"DB_ROOT_USER\" and \"DB_ROOT_PW\" for security reasons and restart the container."
        exit 1
    fi
fi

# Start SBFspotUploadDaemon in background
if [ -n "$sbfspotuploadbinary" ]; then
    "$HOMEDIR/$sbfspotuploadbinary" -c "$CONFDIR/SBFspotUpload.cfg" &
fi

# add Options to SBFspot cmdline
setupSBFspotOptions

if [ "$SBFSPOT_INTERVAL" -lt 30 ]; then
    SBFSPOT_INTERVAL=30;
    echo "SBFSPOT_INTERVAL is very short. It will be set to 30 seconds."
fi

if [ "$SBFSPOT_INTERVAL" -gt 86400 ]; then
    SBFSPOT_INTERVAL=86400;
    echo "SBFSPOT_INTERVAL is too long. It will be set to 1 day."
fi

while true; do
    if [ -n "$sbfspotbinary" ]; then
        start_time=$(date +%s)
        "$HOMEDIR/$sbfspotbinary" $sbfspot_options -cfg:"$CONFDIR/SBFspot.cfg" &   # start sbfspot in background
        pid=$!

        sbfspot_overtime=false

        while kill -0 $pid 2>/dev/null; do
            runtime=$(($(date +%s) - start_time))

            if ! $sbfspot_overtime && [ $runtime -ge $SBFSPOT_INTERVAL ]; then
                sbfspot_overtime=true
                echo "SBFspot has benn running for longer then $SBFSPOT_INTERVAL seconds and is still running."
                echo "Consider updating your SBFSPOT_INTERVAL variable."
            fi

            if [ "$runtime" -ge "$MAX_SBFSPOT_RUNTIME" ]; then
                echo "SBFspot has been running for longer than $MAX_SBFSPOT_RUNTIME seconds. Terminating SBFspot."
                break
            fi
            sleep 10   # checking every 10 seconds if SBFspot is still running
        done

        kill -9 $pid 2>/dev/null
    fi

    # if QUIET SBFspot Option is set, produce less output
    if echo "$sbfspot_options" | grep -q "\-q"; then
        if [ $(($(date +%s) - $(date -d 00:00 +%s))) -lt $SBFSPOT_INTERVAL ];then   # first entry of new day
            if [ "$(date +%u)" -eq 1 ];then   # monday
                echo -n "week "
                date -d @$(($(date +%s) - 86400)) +%W\ %Y
            else                           # all other days
                date -d @$(($(date +%s) - 86400)) +%a   # Name of Yesterday
            fi
        else
            echo -n "."
        fi
    else
        date
        echo "Sleeping $SBFSPOT_INTERVAL seconds."
    fi
        sleep $SBFSPOT_INTERVAL
done
