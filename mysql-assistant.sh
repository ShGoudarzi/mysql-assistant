#!/bin/bash
pidfile=/var/run/ma.sh.pid

INTERACTIVE="1"

DAYS=30
DATE=$(date +"%Y%m%d")
RAND_NUM=$(echo $RANDOM)

LOG_DIR="/var/log/mysqlAssistant"
BACKUP_LOG_FILE="$LOG_DIR/backup.log"
RESTORE_LOG_FILE="$LOG_DIR/restore.log"
TMP_RESTORE_DIR=/tmp/mysqlAssistant-$DATE-$RAND_NUM

red() {
  tput bold
  tput setaf 1
}
yellow() {
  tput bold
  tput setaf 3
}
white() {
  tput bold
  tput setaf 7
}
green() {
  tput bold
  tput setaf 2
}
blue() {
  tput bold
  tput setaf 6
}
resetcolor() {
  tput sgr0
}

#######################

G_PATH=""
G_CONTAINER_NAME=""
G_MYSQL_ROOT_PASSWORD=""
G_MYSQL=""
G_MYSQLDUMP=""
G_MYSQL_NAME=""
G_MYSQL_VERSION=""
G_MYSQL_DATABASES=""
G_MYSQLDUMP_SWITCHES="--add-drop-database --add-drop-table --routines --triggers --create-options --complete-insert --single-transaction --quick --add-locks --flush-privileges "
G_LOG_TYPE=""

fun_check_if_running() {
  if [ -f $pidfile ]; then
    echo "script is already running"
    exit 0
  else
    echo $$ >"$pidfile"
  fi
}

fun_finisher() {
  trap "rm -f -- '$pidfile'" EXIT
}


loader() {
  fun_args_validator $@ 
  fun_check_intractive 
  fun_os_initializer
  fun_check_mysql_local_login
  fun_mysql_initializer
}


fun_backup_path_generator() {
  echo "$1-$2-$3.$4"
}

fun_log_write() {
  if [ ! -d $LOG_DIR ]; then
    mkdir -p $LOG_DIR
  fi

  log_file=$BACKUP_LOG_FILE
  if [ "$G_LOG_TYPE" == "restore" ]; then
    log_file=$RESTORE_LOG_FILE
  fi

  while read data; do
    echo "[$(date +"%d/%B/%Y:%H:%M:%S %:::z")] $data" | tee -a $log_file | sed 's/\[.*]//'
  done

}

fun_check_mysql_local_login() {
  if [ "$G_MYSQL_ROOT_PASSWORD" == "" ] && [ "$G_CONTAINER_NAME" != "" ]; then
    local_login_status=$(docker exec $G_CONTAINER_NAME $G_MYSQL -u root >/dev/null 2>&1)
    if [ $? != 0 ]; then
      G_MYSQL_ROOT_PASSWORD=$(docker exec $G_CONTAINER_NAME env | egrep "[MYSQL|MARIADB]_ROOT_PASSWORD" | cut -d"=" -f2 2>&1)
      if [ "$G_MYSQL_ROOT_PASSWORD" == "" ]; then
        red
        echo -e "***************** Mysql Root-Pass Not Found *****************" | fun_log_write
        yellow
        echo -e "pass the mysql root pass as env argument in mysql fun_container \nexample:   docker run --name some-mariadb -e MARIADB_ROOT_PASSWORD=my-secret-pw -d mariadb:latest" | fun_log_write
        red
        echo -e "*************************************************************" | fun_log_write
        resetcolor
        exit 0
      fi
    fi
  fi

  if [ "$G_MYSQL_ROOT_PASSWORD" != "" ]; then
    G_MYSQL_ROOT_PASSWORD="-p$G_MYSQL_ROOT_PASSWORD"
  fi
}

fun_os_initializer() {
  if [ "$G_CONTAINER_NAME" != "" ]; then
    G_MYSQL=$(docker exec $G_CONTAINER_NAME whereis mysql | cut -d ":" -f 2 | awk '{ print $1 }' | xargs echo)
    G_MYSQLDUMP=$(docker exec $G_CONTAINER_NAME whereis mysqldump | cut -d ":" -f 2 | awk '{ print $1 }' | xargs echo)

  else

    local_mysql=$(systemctl status mariadb.service | grep "running" >/dev/null 2>&1)
    if [ $? -eq 1 ]; then
      echo "MySQL not running/installed" | fun_log_write
      exit 0
    fi

    G_MYSQL=$(whereis mysql | cut -d ":" -f 2 | awk '{ print $1 }' | xargs echo)
    G_MYSQLDUMP=$(whereis mysqldump | cut -d ":" -f 2 | awk '{ print $1 }' | xargs echo)

  fi
}


fun_mysql_initializer() {
  if [ "$G_CONTAINER_NAME" != "" ]; then

    G_MYSQL_NAME=$(docker exec $G_CONTAINER_NAME $G_MYSQL -u root $G_MYSQL_ROOT_PASSWORD --skip-column-names -A -e \
      "SELECT VERSION()" | fun_log_write)
    G_MYSQL_DATABASES=$(docker exec $G_CONTAINER_NAME $G_MYSQL -u root $G_MYSQL_ROOT_PASSWORD --skip-column-names -A -e \
      "show databases;" | egrep -v "(mysql|performance_schema|information_schema|sys)")

  else

    G_MYSQL_NAME=$($G_MYSQL -u root $G_MYSQL_ROOT_PASSWORD --skip-column-names -A -e \
      "STATUS;" | grep "Server:" | awk -F ' ' '{print $2}')
    G_MYSQL_VERSION=$($G_MYSQL -u root $G_MYSQL_ROOT_PASSWORD --skip-column-names -A -e \
      "SELECT VERSION()")
    G_MYSQL_DATABASES=$($G_MYSQL -u root $G_MYSQL_ROOT_PASSWORD --skip-column-names -A -e \
      "show databases;" | egrep -v "(mysql|performance_schema|information_schema|sys)")
  fi
}


fun_args_validator() {
  for i in $*; do

    if [ $(echo $i | cut -d "=" -f 1) == "--full-backup" ]; then
      G_LOG_TYPE="backup"

    elif [ $(echo $i | cut -d "=" -f 1) == "--full-restore" ]; then
      G_LOG_TYPE="restore"

    elif [ $(echo $i | cut -d "=" -f 1) == "--path" ]; then
      G_PATH="$(echo $i | cut -d "=" -f 2 | sed 's/\/$//')"

    elif [ $(echo $i | cut -d "=" -f 1) == "--container-name" ]; then
      G_CONTAINER_NAME="$(echo $i | cut -d "=" -f 2)"
      container_exist=$(docker ps --format {{.Names}} | egrep "^($G_CONTAINER_NAME)$" | wc -w)
      if [ "$container_exist" == "0" ]; then
        red
        echo -e "Container( $G_CONTAINER_NAME ) is not running/exists"
        resetcolor
        exit 0
      fi

    elif [ $(echo $i | cut -d "=" -f 1) == "--mysql-root-pass" ]; then
      G_MYSQL_ROOT_PASSWORD="$(echo $i | cut -d "=" -f 2)"

    elif [ "$i" == "-y" ]; then
      INTERACTIVE="0"

    else
      G_MYSQLDUMP_SWITCHES="$G_MYSQLDUMP_SWITCHES $i"
    fi

  done
}

fun_check_intractive() {
  if [ "$G_LOG_TYPE" == "restore" ] && [ "$INTERACTIVE" == "1" ]; then
    yellow
    printf "WARNING! "
    resetcolor
    printf "This will Remove all existing databases and tables.\n"
    white
    printf "Are you sure you want to continue? [y/N] "
    resetcolor

    read INPUT
    if [ "$INPUT" == "N" ]; then
      echo "Operation has been cancelled..."
      exit 0
    fi
  fi
}

fun_auto_delete_older_backups(){
  find $G_PATH -type f -name "*.gz" -mtime +$DAYS -delete
  find $LOG_DIR -type f -name "*.log" -ctime +$DAYS -delete
}

fun_help() {
  yellow
  echo -e "\n---Generating FullBackup---"
  echo -e "##############################"
  blue
  echo -e "Container mode:"
  white
  echo -e "./mysql-assistant.sh --full-backup --path=/Backup/db-dailyBackup --container-name=mariadb \n"
  blue
  echo -e "Normal mode:"
  white
  echo -e "./mysql-assistant.sh --full-backup --path=/Backup/db-dailyBackup --container-name=mariadb \n"
  resetcolor

  yellow
  echo -e "---Restoring FullBackup---"
  echo -e "##############################"
  blue
  echo -e "Container mode:"
  white
  echo -e "./mysql-assistant.sh --full-restore --path=/Backup/db-dailyBackup/sample-backup-file.tar.gz --container-name=mariadb \n"
  blue
  echo -e "Normal mode:"
  white
  echo -e "./mysql-assistant.sh --full-restore --path=/Backup/db-dailyBackup \n"
  resetcolor

  echo -e "for more help please visit:"
  green
  echo -e "https://github.com/ShGoudarzi/mysql-assistant \n"
  resetcolor
}

fun_normal-full-export() {
  echo -e "***********************************************************" | fun_log_write
  echo -e "Dump operation has been started" | fun_log_write
  echo -e "#####  Mode: Normal  #####" | fun_log_write

  blue
  echo -e "\nServer: $G_MYSQL_NAME ( $G_MYSQL_VERSION )" | fun_log_write
  resetcolor

  # Backup Users
  users_out=$(fun_backup_path_generator $G_MYSQL_NAME "fullbackup_users" $DATE "sql")
  until $($G_MYSQLDUMP -u root $G_MYSQL_ROOT_PASSWORD --system=users |
    sed 's/CREATE USER/CREATE USER IF NOT EXISTS/g' |
    sed -E '/root|mariadb.sys|mysql.sys|mysql.infoschema|mysql.session/d' \
    > $users_out | fun_log_write); 

  do
    sleep 1
  done

  if [ $? != 0 ]; then
    red
    echo -e "problem on Creating Users Backup!" | fun_log_write
    resetcolor
  else
    yellow
    echo -e "Users Backup completed." | fun_log_write
    resetcolor
  fi

  # Backup Databases
  databases_out=$(fun_backup_path_generator $G_MYSQL_NAME "fullbackup_databases" $DATE "sql")
  until $($G_MYSQLDUMP -u root $G_MYSQL_ROOT_PASSWORD --databases $G_MYSQL_DATABASES $G_MYSQLDUMP_SWITCHES \
    > $databases_out | fun_log_write); 
  do
    sleep 1
  done

  if [ $? != 0 ]; then
    red
    echo -e "problem on Creating Databases Backup!" | fun_log_write
    resetcolor
  else
    yellow
    echo -e "Databases Backup completed." | fun_log_write
    resetcolor
  fi

  # Compress as an archive
  result="$G_MYSQL_NAME"_"mysqlAssistant_fullbackup-$DATE.tar.gz"
  tar -czf $result $users_out $databases_out \
    && rm -f $users_out $databases_out

  if [ $? != 0 ]; then
    red
    echo -e "problem on Finalizing the result!" | fun_log_write
    resetcolor
    exit 0
  else
    yellow
    echo -e "Backup file path: $G_PATH/$result" | fun_log_write
    green
    echo -e "\n *** All Done! ***\n" | fun_log_write
    resetcolor
  fi
}

###################################
fun_container-full-export() {

  echo -e "***********************************************************" | fun_log_write
  echo -e "Dump operation has been started" | fun_log_write
  echo -e "#####  Mode: Container  #####" | fun_log_write

  blue
  echo -e "\nContainer: $G_CONTAINER_NAME ( $G_MYSQL_NAME )" | fun_log_write
  resetcolor

  # Backup Users
  users_out=$(fun_backup_path_generator $G_CONTAINER_NAME "fullbackup_users" $DATE "sql")
  until $(docker exec \
    $G_CONTAINER_NAME $G_MYSQLDUMP -u root $G_MYSQL_ROOT_PASSWORD --system=users |
    sed 's/CREATE USER/CREATE USER IF NOT EXISTS/g' |
    sed -E '/root|mariadb.sys|mysql.sys|mysql.infoschema|mysql.session/d' \
    > $users_out | fun_log_write); 
  do
    echo -e "Creating users Backup is in progress..." | fun_log_write
    sleep 1
  done

  if [ $? != 0 ]; then
    red
    echo -e "problem on Creating Users Backup!" | fun_log_write
    resetcolor
  else
    yellow
    echo -e "Users Backup completed." | fun_log_write
    resetcolor
  fi

  # Backup Databases
  databases_out=$(fun_backup_path_generator $G_CONTAINER_NAME "fullbackup_databases" $DATE "sql")
  until $(docker exec \
    $G_CONTAINER_NAME $G_MYSQLDUMP -u root $G_MYSQL_ROOT_PASSWORD --databases $G_MYSQL_DATABASES $G_MYSQLDUMP_SWITCHES \
    > $databases_out | fun_log_write); 
  do
    echo -e "Creating databases Backup is in progress..." | fun_log_write
    sleep 1
  done

  if [ $? != 0 ]; then
    red
    echo -e "problem on Creating Databases Backup!" | fun_log_write
    resetcolor
  else
    yellow
    echo -e "Databases Backup completed." | fun_log_write
    resetcolor
  fi

  # Compress as an archive
  result="$G_CONTAINER_NAME"_"mysqlAssistant_fullbackup-$DATE.tar.gz"
  tar -czf $result $users_out $databases_out \
    && rm -f $users_out $databases_out

  if [ $? != 0 ]; then
    red
    echo -e "problem on Finalizing the result!" | fun_log_write
    resetcolor
    exit 0
  else

    yellow
    echo -e "Backup file path: $G_PATH/$result" | fun_log_write
    green
    echo -e "\n *** All Done! ***\n" | fun_log_write
    resetcolor
  fi
}

#############################################################################

fun_normal-full-import() {

  echo -e "***********************************************************" | fun_log_write
  echo -e "Import operation has been started" | fun_log_write
  echo -e "#####  Mode: Normal  #####" | fun_log_write

  tar -xvzf $G_PATH -C $TMP_RESTORE_DIR 2> fun_log_write
  if [ $? != 0 ]; then
    red
    echo -e "problem on Extracting backup file!" | fun_log_write
    resetcolor
    exit 0
  fi

  blue
  echo -e "\nServer: $G_MYSQL_NAME ( $G_MYSQL_VERSION )" | fun_log_write
  resetcolor

  # Restore Users
  users_file=$(find $TMP_RESTORE_DIR -name "*-fullbackup_users-*.sql")
  until $($G_MYSQL -u root $G_MYSQL_ROOT_PASSWORD \
    < $users_file | fun_log_write);
  do
    echo -e "Restoring users Backup is in progress..." | fun_log_write
    sleep 1
  done

  if [ $? != 0 ]; then
    red
    echo -e "problem on Restore Users!" | fun_log_write
    resetcolor
    exit 0
  else
    yellow
    echo -e "Users Restoration completed." | fun_log_write
    resetcolor
  fi

  # Restore Databases --force
  db_file=$(find $TMP_RESTORE_DIR -name "*-fullbackup_databases-*.sql")
  until $($G_MYSQL -u root $G_MYSQL_ROOT_PASSWORD \
    < $db_file | fun_log_write); 
  do
    echo -e "Restoring databases Backup is in progress..." | fun_log_write
    sleep 1
  done

  if [ $? != 0 ]; then
    red
    echo -e "problem on Restore Databases!" | fun_log_write
    resetcolor
    exit 0
  else
    yellow
    echo -e "Databases Restoration completed." | fun_log_write
    green
    echo -e "\n *** All Done! ***\n" | fun_log_write
    resetcolor;
    
  fi

}

###################################
fun_container-full-import() {
  echo -e "***********************************************************" | fun_log_write
  echo -e "Import operation has been started" | fun_log_write
  echo -e "#####  Mode: Container  #####" | fun_log_write

  tar -xvzf $G_PATH -C $TMP_RESTORE_DIR 2>fun_log_write
  if [ $? != 0 ]; then
    red
    echo -e "problem on Extracting backup file!" | fun_log_write
    resetcolor
    exit 0
  fi

  blue
  echo -e "\nContainer: $G_CONTAINER_NAME ( $G_MYSQL_NAME )" | fun_log_write
  resetcolor

  # Restore Users
  users_file=$(find $TMP_RESTORE_DIR -name "*-fullbackup_users-*.sql")
  until $(docker exec -i \
    $G_CONTAINER_NAME $G_MYSQL -u root $G_MYSQL_ROOT_PASSWORD \
    < $users_file | fun_log_write); 
  do
    echo -e "Restoring users Backup is in progress..." | fun_log_write
    sleep 1
  done

  if [ $? != 0 ]; then
    red
    echo -e "problem on Restore Users!" | fun_log_write
    resetcolor
    exit 0
  else
    yellow
    echo -e "Users Restoration completed." | fun_log_write
    resetcolor
  fi

  # Restore Databases
  db_file=$(find $TMP_RESTORE_DIR -name "*-fullbackup_databases-*.sql")
  until $(docker exec -i \
    $G_CONTAINER_NAME $G_MYSQL -u root $G_MYSQL_ROOT_PASSWORD \
    < $db_file | fun_log_write); 
  do
    echo -e "Restoring databases Backup is in progress..." | fun_log_write
    sleep 1
  done

  if [ $? != 0 ]; then
    red
    echo -e "problem on Restore Databases!" | fun_log_write
    resetcolor
    exit 0
  else
    yellow
    echo -e "Databases Restoration completed." | fun_log_write
    green
    echo -e "\n *** All Done! ***\n" | fun_log_write
    resetcolor
  fi

}

main-exporter() {
  if [ "$G_PATH" != "" ]; then

    if [ ! -d $G_PATH ]; then
      mkdir -p $G_PATH
    fi
    cd $G_PATH

    if [ "$G_CONTAINER_NAME" != "" ]; then
      fun_container-full-export
    else
      fun_normal-full-export
    fi
    
    fun_auto_delete_older_backups

  else
    printf "unknown input.\n"
    exit 0
  fi
}

main-importer() {
  if [ "$G_PATH" != "" ]; then
    if [ ! -d $TMP_RESTORE_DIR ]; then
      mkdir -p $TMP_RESTORE_DIR
    fi

    if [ "$G_CONTAINER_NAME" != "" ]; then
      fun_container-full-import
    else
      fun_normal-full-import
    fi

    rm -rf $TMP_RESTORE_DIR

  else
    printf "unknown input.\n"
    exit 0
  fi
}

# MAIN SCRIPT
fun_check_if_running
fun_finisher

if [ -z "$1" ]; then
  yellow
  printf ">>> Use --help \n"
  resetcolor

else
  if [ "$1" == "--help" ]; then
    fun_help
  else
    if [ "$#" -gt "1" ]; then
      echo " Preparing..."
      loader $@

      case $1 in
      --full-backup)
        main-exporter
        ;;

      --full-restore)
        main-importer
        ;;

      *)
        printf "unknown input.\n"
        ;;
      esac
    else
      printf "You must pass atleast 2 arrguments.\n"
    fi
  fi
fi