#!/bin/sh

confdir=/etc/sbfspot
homedir=/usr/local/bin/sbfspot.3
datadir=/var/sbfspot
sbfspotbinary=""
sbfspotuploadbinary=""
sbfspot_cfg_file=""
sbfspot_options=""

getConfigValue() {
    key=$1
    echo "$sbfspot_cfg_file" | grep -e "^$key=" | cut -f 2 -d "=" | sed 's/[ 	]*$//' # search for key, get value, delete invisible chars at the end
}

setConfigValue() {
    key=$1
    value=$2
    temp_value=`getConfigValue $key`
    if [ -n "$temp_value" ]; then   # key found, so update new value
        echo "$sbfspot_cfg_file" | sed "/^$key=.*/c $key=$value" > $confdir/SBFspot.cfg
    else
        temp_value=`getConfigValue "#$key"`  # search for inactive key
        if [ -n "$temp_value" ]; then  # append key=value after the first match
            echo "$sbfspot_cfg_file" | sed "0,/^#$key/!b;//a$key=$value" > $confdir/SBFspot.cfg
        else
            temp_value=`getConfigValue "# $key"`   # no inactive key found, test again with space after hashtag
            if [ -n "$temp_value" ]; then  # append key=value after the first match
                echo "$sbfspot_cfg_file" | sed "0,/^# $key/!b;//a$key=$value" > $confdir/SBFspot.cfg
            else
                echo "Cannot find the option \"$key\" in SBFspot.cfg. Appending the option at the end of the file."
                echo "$sbfspot_cfg_file" | sed "\$a $key=$value" > $confdir/SBFspot.cfg
            fi
        fi
    fi
    readConfig
}

readConfig() {
    sbfspot_cfg_file=$( cat $confdir/SBFspot.cfg | dos2unix -u )
}

checkSBFConfig() {
	if `mount | grep -q -e "$confdir "`; then
        if [ -r $confdir/SBFspot.cfg ]; then
            readConfig
            if [ -n "$CSV_STORAGE" ] && [ $CSV_STORAGE -eq 1 ]; then
                if [ `getConfigValue CSV_Export` -eq 0 ]; then
                    if [ -w $confdir/SBFspot.cfg ]; then
                        setConfigValue "CSV_Export" "1"
                        echo "Wrong CSV_Export value in SBFspot.cfg. I change it to 1."
                    else
                        echo "$confdir/SBFspot.cfg is not writeable by User with ID `id -u sbfspot` or Group with ID `id -g sbfspot`."
                        echo "Please change file permissions of SBFspot.cfg or ensure, that the \"CSV_Export\""
                        echo "value is 1"
                        exit 1
                    fi
                fi
            fi
            if [ `getConfigValue CSV_Export` -eq 1 ]; then   # if CSV_Export=1 then OutputPath and OutputPathEvents must point to /var/sbfspot
                if `mount | grep -q -e "$datadir "`; then
                    if [ -w $confdir/SBFspot.cfg ]; then
                        if ! `getConfigValue OutputPath | grep -q -e "^/var/sbfspot$"` && \
                                ! `getConfigValue OutputPath | grep -q -e "^/var/sbfspot/"`; then    
                            setConfigValue "OutputPath" "$datadir/%Y"
                            echo "Wrong OutputPath value in SBFspot.cfg. I change it to \"$datadir/%Y\""
                        fi

                        if ! `getConfigValue OutputPathEvents | grep -q -e "^/var/sbfspot$"` && \
                                ! `getConfigValue OutputPathEvents | grep -q -e "^/var/sbfspot/"`; then
                            setConfigValue "OutputPathEvents" "$datadir/%Y/Events"
                            echo "Wrong OutputPathEvents value in SBFspot.cfg. I change it to \"$datadir/%Y/Events\""
                        fi
                    else
                        echo "$confdir/SBFspot.cfg is not writeable by User with ID `id -u sbfspot` or Group with ID `id -g sbfspot`."
                        echo "Please change file permissions of SBFspot.cfg or ensure, that the \"OutputPath\" and \"OutputPathEvents\" Options"
                        echo "point to the Directory $datadir/..."
                        exit 1
                    fi
                else
                    echo "$datadir is not mapped to a directory outside the container => csv files would not be persistant."
                    echo "Please map the directory and restart the container."
                    exit 1
                fi
                
                # check if data directory is writeable
                if [ ! -w $datadir ]; then
                    echo "Mapped Data directory is not writeable for user with ID `id -u sbfspot` or group with ID `id -g sbfspot`."
                    echo "Please change file permissions accordingly and restart the container."
                    exit 1
                fi
            fi
            if [ -n "$MQTT_ENABLE" ] && [ $MQTT_ENABLE -eq 1 ]; then
                if ! `getConfigValue MQTT_Publisher | grep -q -e "^/usr/bin/mosquitto_pub"`; then
                    setConfigValue "MQTT_Publisher" "/usr/bin/mosquitto_pub"
                    echo "Wrong MQTT_Publisher value in SBFspot.cfg corrected."
                fi
                if `getConfigValue MQTT_Host | grep -q -e "^test.mosquitto.org"`; then
                    echo "Warning: Please configure the \"MQTT_Host\" value in SBFspot.cfg."
                fi
            fi
        else
            echo "$confdir/SBFspot.cfg is not readable by user with ID `id -u sbfspot` or group with ID `id -g sbfspot`."
            echo "Please change file permissions accordingly and restart the container."
            exit 1
        fi
    else
        echo "$confdir is not mapped to a directory outside the container => Config file can't be read."
		echo "Please map the directory and restart the container."
		exit 1
    fi
}
 
checkSBFUploadConfig() {
	if `mount | grep -q -e "$confdir "`; then
        if [ ! -r $confdir/SBFspotUpload.cfg ]; then
            echo "$confdir/SBFspotUpload.cfg is not readable by user with ID `id -u sbfspot` or group with ID `id -g sbfspot.`"
            echo "Please change file permissions accordingly and restart the container."
            exit 1
        fi
    else
        echo "$confdir is not mapped to a directory outside the container => Config file can't be read."
		echo "Please map the directory and restart the container."
		exit 1
    fi
}

setupSBFspotOptions() {
    if [ -n "$SBFSPOT_ARGS" ]; then
        sbfspot_options=" $SBFSPOT_ARGS "
    fi
    if [ -n "$FORCE" ] && [ $FORCE -eq 1 ]; then
        sbfspot_options="$sbfspot_options -finq"
    fi
    if [ -n "$FINQ" ] && [ $FINQ -eq 1 ]; then
        sbfspot_options="$sbfspot_options -finq"
    fi
    if [ -n "$QUIET" ] && [ $QUIET -eq 1 ]; then
        sbfspot_options="$sbfspot_options -q"
    fi
    if [ -n "$MQTT_ENABLE" ] && [ $MQTT_ENABLE -eq 1 ]; then
        sbfspot_options="$sbfspot_options -mqtt"
    fi
}

initDatabase() {
    if [ "$STORAGE_TYPE" = "sqlite" ]; then
        if `mount | grep -q -e "$datadir "`; then
            # check if data directory is writeable
			if [ ! -w $datadir ]; then
				echo "Mapped Data directory is not writeable for user with ID `id -u sbfspot` or group with ID `id -g sbfspot`."
				echo "Please change file permissions accordingly and restart the container."
				exit 1
			fi
            sqlite3 $datadir/sbfspot.db < $homedir/CreateSQLiteDB.sql
        else
            echo "$datadir is not mapped to a directory outside the container => database would not be persistant."
            echo "Please map the directory and restart the container."
            exit 1
        fi
    elif [ "$STORAGE_TYPE" = "mysql" ] || [ "$STORAGE_TYPE" = "mariadb" ]; then
        HOST=`getConfigValue SQL_Hostname`
        DB=`getConfigValue SQL_Database`
        USER=`getConfigValue SQL_Username`
        PW=`getConfigValue SQL_Password`
        LOCAL_IP=`ip ro show | grep 'docker0\|eth0' | awk '{print $(NF)}'`
        
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
        if [ $ERROR_FLAG = 1 ]; then
            echo "Please configure the listed value(s) and restart the container."
            exit 1
        fi

        if `mysql -h $HOST --protocol=TCP -u $DB_ROOT_USER -p$DB_ROOT_PW < $homedir/CreateMySQLDB.sql`; then
            echo "Database, tables and views created."
        else
            cp $homedir/CreateMySQLDB.sql $datadir
            echo "Error creating SBFspot Database, tables and views. Please manually add the file \"CreateMySQLDB.sql\""
            echo "(located in SBFspots data directory) to your Database, if the Database does not exist yet."
        fi
        SQL_USER_ADD="CREATE USER '$USER'@'$LOCAL_IP' IDENTIFIED BY '$PW';"
        SQL_USER_CHANGE="ALTER USER '$USER'@'$LOCAL_IP' IDENTIFIED BY '$PW';"
        SQL_GRANT1="GRANT INSERT,SELECT,UPDATE ON SBFspot.* TO '$USER'@'$LOCAL_IP';"
        SQL_GRANT2="GRANT DELETE,INSERT,SELECT,UPDATE ON SBFspot.MonthData TO '$USER'@'$LOCAL_IP';"
        
        if `mysql -h $HOST --protocol=TCP -u $DB_ROOT_USER -p$DB_ROOT_PW -e "SELECT User FROM mysql.user;" | grep -q -e $USER`; then
            echo "User $USER exists in Database, only changing password"
            mysql -h $HOST --protocol=TCP -u $DB_ROOT_USER -p$DB_ROOT_PW -e "$SQL_USER_CHANGE"
        else
            if `mysql -h $HOST --protocol=TCP -u $DB_ROOT_USER -p$DB_ROOT_PW -e "$SQL_USER_ADD"`; then
                echo "Database User created"
            fi
        fi
        if `mysql -h $HOST --protocol=TCP -u $DB_ROOT_USER -p$DB_ROOT_PW -e "$SQL_GRANT1"`; then
            echo "Following rights for User $USER set"
            echo "$SQL_GRANT1"
        fi
        if `mysql -h $HOST --protocol=TCP -u $DB_ROOT_USER -p$DB_ROOT_PW -e "$SQL_GRANT2"`; then
            echo "Following rights for User $USER set"
            echo "$SQL_GRANT2"
        fi
	    exit 0
    elif [ "$STORAGE_TYPE" != "sqlite" ] && [ "$STORAGE_TYPE" != "mysql" ] && [ "$STORAGE_TYPE" != "mariadb" ]; then
        echo "storage type \"$STORAGE_TYPE\" not available. Options: sqlite | mysql | mariadb"
        exit 1
    fi
}

selectSBFspotBinary() {
    if [ -n "$ENABLE_SBFSPOT" ] && [ $ENABLE_SBFSPOT -ne 0 ]; then
        if [ -z "$STORAGE_TYPE" ]; then
            sbfspotbinary=SBFspot_nosql
        elif [ "$STORAGE_TYPE" = "sqlite" ]; then
            sbfspotbinary=SBFspot_sqlite
        elif [ "$STORAGE_TYPE" = "mysql" ]; then
            sbfspotbinary=SBFspot_mysql
        elif [ "$STORAGE_TYPE" = "mariadb" ]; then
            sbfspotbinary=SBFspot_mariadb
        else
            echo "storage type \"$STORAGE_TYPE\" not available. Options: sqlite | mysql | mariadb"
            exit 1
        fi
        
        checkSBFConfig
    fi
}

selectSBFspotUploadBinary() {
    if [ -n "$ENABLE_SBFSPOT_UPLOAD" ] && [ $ENABLE_SBFSPOT_UPLOAD -ne 0 ]; then
        if [ "$STORAGE_TYPE" = "sqlite" ]; then
            sbfspotuploadbinary=SBFspotUploadDaemon_sqlite
            echo "SBFspotUploadDaemon for sqlite storage selected"
        elif [ "$STORAGE_TYPE" = "mysql" ]; then
            sbfspotuploadbinary=SBFspotUploadDaemon_mysql
            echo "SBFspotUploadDaemon for mysql storage selected"
        elif [ "$STORAGE_TYPE" = "mariadb" ]; then
            sbfspotuploadbinary=SBFspotUploadDaemon_mariadb
            echo "SBFspotUploadDaemon for mariadb storage selected"
        else
            echo "storage type \"$STORAGE_TYPE\" not available for SBFspotUploadDaemon. Options: sqlite | mysql | mariadb"
            exit 1
        fi
        
        checkSBFUploadConfig
    fi
}

copyDefaultConf() {
    if [ ! -e $confdir/SBFspot.default.cfg ]; then
        cp $homedir/SBFspot.default.cfg $confdir 2>/dev/null
        chmod 666 $confdir/SBFspot.default.cfg 2>/dev/null
    fi
    if [ ! -e $confdir/SBFspotUpload.default.cfg ]; then
        cp $homedir/SBFspotUpload.default.cfg $confdir 2>/dev/null
        chmod 666 $confdir/SBFspotUpload.default.cfg 2>/dev/null
    fi
}

checkStorageType() {
    if [ -z "$STORAGE_TYPE" ] && ( [ -z "$CSV_STORAGE" ] || [ $CSV_STORAGE -ne 1 ] ) && ( [ -z "$MQTT_ENABLE" ] || [ $MQTT_ENABLE -ne 1 ] ); then
        echo "Error, no Data Output is selected. Please configure at least one of the options: STORAGE_TYPE, CSV_STORAGE or MQTT_ENABLE"
        exit 1
    fi
}

checkNoServiceSelected() {
    if ( [ -z "$ENABLE_SBFSPOT" ] || [ $ENABLE_SBFSPOT -eq 0 ] ) && ( [ -z "$ENABLE_SBFSPOT_UPLOAD" ] || [ $ENABLE_SBFSPOT_UPLOAD -eq 0 ] ); then
        if ( [ -n "$INIT_DB" ] && [ $INIT_DB -ne 1 ] ); then
            echo "Warning: Neither SBFspot nor SBFspotUploadDaemon were enabled"
            echo "Enable at least one by setting ENABLE_SBFSPOT or ENABLE_SBFSPOT_UPLOAD environment variable to 1"
            exit 1
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
if [ -n "$INIT_DB" ] && [ $INIT_DB -eq 1 ]; then
    initDatabase
else
    if [ -n "$DB_ROOT_USER" ] || [ -n "$DB_ROOT_PW" ]; then
        echo "Please delete the environment variables \"DB_ROOT_USER\" and \"DB_ROOT_PW\" for security reasons and restart the container."
        exit 1
    fi
fi

# Start SBFspotUploadDaemon in background
if [ -n "$sbfspotuploadbinary" ]; then
    $homedir/$sbfspotuploadbinary -c $confdir/SBFspotUpload.cfg &
fi

# add Options to SBFspot cmdline
setupSBFspotOptions

while [ TRUE ]; do
	if [ -n "$sbfspotbinary" ]; then
		$homedir/$sbfspotbinary $sbfspot_options -cfg$confdir/SBFspot.cfg
	fi
    
	if [ $SBFSPOT_INTERVAL -lt 60 ]; then
        SBFSPOT_INTERVAL=60;
        echo "SBFSPOT_INTERVAL is very short. It will be set to 60 seconds."
    fi
    
    # if QUIET SBFspot Option is set, produce less output
    if echo $sbfspot_options | grep -q "\-q"; then
        DELTA=`expr 60 - $SBFSPOT_INTERVAL / 60`
        if [ `date +%H` -eq 23 ] && [ `date +%M` -ge $DELTA ];then   # last entry of a day
            if [ `date +%u` -eq 7 ];then   # sunday
                expr `date +%W`
            else                           # all other days
                echo ";"
            fi
        else
            echo -n "."
        fi
    else
        echo "Sleeping $SBFSPOT_INTERVAL seconds."
    fi
	sleep $SBFSPOT_INTERVAL
done
