#!/bin/bash

# MySQL Assistant Script Template
# ---
# This backup script can be used to automatically backup databases in docker containers and also from local host.
# It currently supports mariadb, mysql and bitnami containers.
#

################################################################################
#Copyright (c) 2022 Shayan Goudarzi ( me@ShGoudarzi.ir )

#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:

#The above copyright notice and this permission notice shall be included in all
#copies or substantial portions of the Software.

#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#SOFTWARE.
################################################################################

tabs 2
pidfile=/var/run/ma.sh.pid
INTERACTIVE="1"

DAYS=30
DATE=$(date +"%Y%m%d")
RAND_NUM=$(echo $RANDOM)

LOG_FILE="/var/log/mysql-assistant.log"
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
G_MYSQLDUMP_SWITCHES="--add-drop-database --add-drop-table --routines --triggers --create-options --complete-insert --single-transaction --quick --add-locks "
G_MYSQL_FLUSH="--flush-privileges"
G_FORCE=""
###################
G_MODE="Normal"
G_LOG_TYPE=""


function check_if_running() {
  if [ -f $pidfile ]; then
    echo "script is already running"
    exit 0
  else
    echo $$ >"$pidfile"
  fi
}

function finisher() {
  trap "rm -f -- '$pidfile'" EXIT
}


loader() {
  args_validator $@
  check_intractive
  os_initializer
  check_mysql_local_login
  mysql_initializer
}


function backup_path_generator() {
  echo "$1-$2-$3.$4"
}

function log_print() {
  while read data; do
    echo -e "[$(date +"%d/%b/%Y:%H:%M:%S %:::z")\t$G_LOG_TYPE]\t$data" | tee -a $LOG_FILE | sed 's/\[.*]//'
  done

}

function check_mysql_local_login() {
  if [ "$G_MYSQL_ROOT_PASSWORD" == "" ] && [ "$G_CONTAINER_NAME" != "" ]; then
    local_login_status=$(docker exec $G_CONTAINER_NAME $G_MYSQL -u root >/dev/null 2>&1)
    if [ $? != 0 ]; then
      G_MYSQL_ROOT_PASSWORD=$(docker exec $G_CONTAINER_NAME env | egrep "[MYSQL|MARIADB]_ROOT_PASSWORD" | cut -d"=" -f2 2>&1)
      if [ "$G_MYSQL_ROOT_PASSWORD" == "" ]; then
        red
        echo -e "***************** Mysql Root-Pass Not Found *****************" | log_print
        yellow
        echo -e "pass the mysql root pass as env argument in mysql fun_container \nexample:   docker run --name some-mariadb -e MARIADB_ROOT_PASSWORD=my-secret-pw -d mariadb:latest" | log_print
        red
        echo -e "*************************************************************" | log_print
        resetcolor
        exit 0
      fi
    fi
  fi

  if [ "$G_MYSQL_ROOT_PASSWORD" != "" ]; then
    G_MYSQL_ROOT_PASSWORD="-p$G_MYSQL_ROOT_PASSWORD"
  fi
}

function os_initializer() {
  if [ "$G_CONTAINER_NAME" != "" ]; then
    G_MYSQL=$(docker exec $G_CONTAINER_NAME whereis mysql | cut -d ":" -f 2 | awk '{ print $1 }' | xargs echo)
    G_MYSQLDUMP=$(docker exec $G_CONTAINER_NAME whereis mysqldump | cut -d ":" -f 2 | awk '{ print $1 }' | xargs echo)

  else

    local mysql_state=$(systemctl is-active mysql)
    if [ "$mysql_state" != "active" ]; then
      echo "MySQL not running/installed" | log_print
      exit 0
    fi

    G_MYSQL=$(whereis mysql | cut -d ":" -f 2 | awk '{ print $1 }' | xargs echo)
    G_MYSQLDUMP=$(whereis mysqldump | cut -d ":" -f 2 | awk '{ print $1 }' | xargs echo)

  fi
}


function mysql_initializer() {
  if [ "$G_CONTAINER_NAME" != "" ]; then

    G_MYSQL_NAME=$G_CONTAINER_NAME
    G_MYSQL_VERSION=$(docker exec $G_CONTAINER_NAME $G_MYSQL -u root $G_MYSQL_ROOT_PASSWORD --skip-column-names -A -e \
      "SELECT VERSION()" )
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


function args_validator() {
  for i in $*; do

    if [ $(echo $i | cut -d "=" -f 1) == "--full-backup" ]; then
      G_LOG_TYPE="Backup"

    elif [ $(echo $i | cut -d "=" -f 1) == "--full-restore" ]; then
      G_LOG_TYPE="Restore"

    elif [ $(echo $i | cut -d "=" -f 1) == "--path" ]; then
      G_PATH="$(echo $i | cut -d "=" -f 2 | sed 's/\/$//')"

    elif [ $(echo $i | cut -d "=" -f 1) == "--container-name" ]; then
      G_CONTAINER_NAME="$(echo $i | cut -d "=" -f 2)"
      container_exist=$(docker ps --format {{.Names}} | egrep "^($G_CONTAINER_NAME)$" | wc -w)
      if [ "$container_exist" == "0" ]; then
        red
        echo -e "Container( $G_CONTAINER_NAME ) is not running/exists" | log_print
        resetcolor
        exit 0
      fi

      G_MODE="Container"

    elif [ $(echo $i | cut -d "=" -f 1) == "--mysql-root-pass" ]; then
      G_MYSQL_ROOT_PASSWORD="$(echo $i | cut -d "=" -f 2)"

    elif
      [ "$i" == "-f" ] || [ "$i" == "--force" ]; then
      G_FORCE="--force"

    elif [ "$i" == "-y" ]; then
      INTERACTIVE="0"

    else
      G_MYSQLDUMP_SWITCHES="$G_MYSQLDUMP_SWITCHES $i"
    fi

  done
}

function check_intractive() {
  if [ "$G_LOG_TYPE" == "Restore" ] && [ "$INTERACTIVE" == "1" ]; then
    yellow
    printf "\tWARNING! "
    resetcolor
    printf "This will Remove all existing databases and tables.\n"
    white
    printf "\tAre you sure you want to continue? [y/N] "
    resetcolor

    read INPUT
    if [ "$INPUT" == "N" ]; then
      echo -e "\tOperation has been cancelled..."
      exit 0
    fi
  fi
}

function auto_delete_older_backups(){
  find $G_PATH -type f -name "*.gz" -mtime +$DAYS -delete
  find $LOG_FILE -ctime +$DAYS -delete
}

function help() {
  yellow
  echo -e "\n---Generating FullBackup---"
  echo -e "##############################"
  blue
  echo -e "Container mode:"
  white
  echo -e "mysql-assistant.sh --full-backup --path=/Backup/db-dailyBackup --container-name=mariadb \n"
  blue
  echo -e "Normal mode:"
  white
  echo -e "mysql-assistant.sh --full-backup --path=/Backup/db-dailyBackup \n"
  resetcolor

  yellow
  echo -e "---Restoring FullBackup---"
  echo -e "##############################"
  blue
  echo -e "Container mode:"
  white
  echo -e "mysql-assistant.sh --full-restore --path=/Backup/db-dailyBackup/sample-backup-file.tar.gz --container-name=mariadb \n"
  blue
  echo -e "Normal mode:"
  white
  echo -e "mysql-assistant.sh --full-restore --path=/Backup/db-dailyBackup \n"
  resetcolor

  echo -e "for more help please visit:"
  green
  echo -e "https://github.com/ShGoudarzi/mysql-assistant \n"
  resetcolor
}


function backup_fun() {
    local api=""
    if [ "$G_MODE" == "Normal" ]; then
        api=""
    fi
    if [ "$G_MODE" == "Container" ]; then
        api="docker exec $G_MYSQL_NAME"
    fi


    echo -e "***********************************************************"
    echo -e "$G_LOG_TYPE operation has been started"
    echo -e "#####  Mode: $G_MODE  #####"
    blue
    echo -e "$G_MYSQL_NAME ( $G_MYSQL_VERSION )"
    echo ""
    resetcolor
### Backup Users
    echo -e "Creating users Backup is in progress..."
    users_out=$(backup_path_generator $G_MYSQL_NAME "fullbackup_users" $DATE "sql")
    $api $G_MYSQLDUMP -u root $G_MYSQL_ROOT_PASSWORD --system=users $G_MYSQL_FLUSH $G_FORCE |
      sed 's/CREATE USER/CREATE USER IF NOT EXISTS/g' |
      sed -E '/root|mariadb.sys|mysql.sys|mysql.infoschema|mysql.session/d' \
      1> $users_out 2> >(tee -a $LOG_FILE)

    if [ $? != 0 ]; then
      red
      echo -e "Problem on Creating Users Backup!\n"
      white
      echo -e "Log: tail $LOG_FILE\n\n"
      resetcolor
      exit 0
    else
      yellow
      echo -e "Users Backup completed."
      resetcolor
    fi

### Backup Databases
    echo -e "Creating databases Backup is in progress..."
    databases_out=$(backup_path_generator $G_MYSQL_NAME "fullbackup_databases" $DATE "sql")
    $api $G_MYSQLDUMP -u root $G_MYSQL_ROOT_PASSWORD --databases $G_MYSQL_DATABASES $G_MYSQLDUMP_SWITCHES $G_MYSQL_FLUSH $G_FORCE \
      1> $databases_out 2> >(tee -a $LOG_FILE)

    if [ $? != 0 ]; then
      red
      echo -e "Problem on Creating Databases Backup!\n"
      white
      echo -e "Log: tail $LOG_FILE\n\n"
      resetcolor
      exit 0
    else
      yellow
      echo -e "Databases Backup completed."
      resetcolor
    fi

### Compress as an archive
    result="$G_MYSQL_NAME"_"mysql-assistant_fullbackup-$DATE.tar.gz"
    tar -czf $result $users_out $databases_out \
      && rm -f $users_out $databases_out

    if [ $? != 0 ]; then
      red
      echo -e "problem on Finalizing the result!\n"
      white
      echo -e "Log: tail $LOG_FILE\n\n"
      resetcolor
      exit 0
    else

    yellow
      echo -e "Backup file path: $G_PATH/$result"
      green
      echo -e "\n *** All Done! ***\n"
      resetcolor
    fi
}

########################################################

function restore_fun() {
    local api=""
    if [ "$G_MODE" == "Normal" ]; then
        api=""
    fi
    if [ "$G_MODE" == "Container" ]; then
        api="docker exec -i $G_MYSQL_NAME"
    fi


    echo -e "***********************************************************"
    echo -e "$G_LOG_TYPE operation has been started"
    echo -e "#####  Mode: $G_MODE  #####"
    blue
    echo -e "$G_MYSQL_NAME ( $G_MYSQL_VERSION )"
    echo ""
    resetcolor
### Restore
    tar -xvzf $G_PATH -C $TMP_RESTORE_DIR 2> >(tee -a $LOG_FILE)
    if [ $? != 0 ]; then
      red
      echo -e "Problem on Extracting backup file!\n"
      white
      echo -e "Log: tail $LOG_FILE\n\n"
      resetcolor
      exit 0
    fi

### Restore Users
    echo -e "Restoring users Backup is in progress..."
    users_file=$(find $TMP_RESTORE_DIR -name "*-fullbackup_users-*.sql")
    $api $G_MYSQL -u root $G_MYSQL_ROOT_PASSWORD $G_FORCE \
    < $users_file > $LOG_FILE 2>&1

    if [ $? != 0 ]; then
      red
      echo -e "Problem on Restore Users!\n"
      white
      echo -e "Log: tail $LOG_FILE\n\n"
      resetcolor
      exit 0
    else
      yellow
      echo -e "Users Restoration completed."
      resetcolor
    fi


### Restore Databases
    echo -e "Restoring databases Backup is in progress..."
    db_file=$(find $TMP_RESTORE_DIR -name "*-fullbackup_databases-*.sql")
    $api $G_MYSQL -u root $G_MYSQL_ROOT_PASSWORD $G_FORCE \
    < $db_file > $LOG_FILE 2>&1

    if [ $? != 0 ]; then
      red
      echo -e "problem on Restore Databases!\n"
      white
      echo -e "Log: tail $LOG_FILE\n\n"
      resetcolor
      exit 0
    else
      yellow
      echo -e "Databases Restoration completed."
      green
      echo -e "\n *** All Done! ***\n"
      resetcolor
    fi
}


main-exporter() {
  if [ "$G_PATH" != "" ]; then

    if [ ! -d $G_PATH ]; then
      mkdir -p $G_PATH
    fi
    cd $G_PATH

    backup_fun
    auto_delete_older_backups

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

    restore_fun
    rm -rf $TMP_RESTORE_DIR

  else
    printf "unknown input.\n"
    exit 0
  fi
}

# MAIN SCRIPT
check_if_running
finisher

if [ -z "$1" ]; then
  yellow
  printf ">>> Use --help \n"
  resetcolor

else
  if [ "$1" == "--help" ]; then
    help
  else
    if [ "$#" -gt "1" ]; then
      echo -e "\tPreparing..."
      loader $@

      case $1 in
      --full-backup)
        main-exporter | log_print
        ;;

      --full-restore)
        main-importer | log_print
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
