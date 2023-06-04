#!/bin/bash
#===============================================================================
#
#           DIR: /etc/backup-assistant
#
#         USAGE: backup-assistant.sh , backup-assistant.sh --force
#
#   DESCRIPTION: create a gz backup of your files and upload them to ftp,ssh server
#
#  REQUIREMENTS: curl, gpg, rsync, ftp 
#        AUTHOR: Shayan Goudarzi, me@shayangoudarzi.ir
#  ORGANIZATION: Linux
#       CREATED: 09/16/2022
#===============================================================================
export TOP_PID=$$
export ARGS=($@)


DATE=$(date +"%Y%m%d")
NOW=$(date +"%d/%b/%Y:%H:%M:%S %:::z")
HOSTNAME=$(hostname -s)
LOG_FILE="/var/log/backup-assistant.log"
tmp_log="/tmp/backup-assistant.log"

pidfile=/var/run/ba.sh.pid
config_path="/etc/backup-assistant"
intervalConfigFiles_path="$config_path/source"

week_day=$(date +"%u") 
week_backup_day="5" # 5:friday

month_day=$(date +"%d")
month_backup_day="28"

G_daily_fileName="backup.daily"
G_weekly_fileName="backup.weekly"
G_monthly_fileName="backup.monthly"


#### STATUS 
SSH_CONNECTION_STATUS=1
FTP_CONNECTION_STATUS=1



### Colors
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



##### Functions #####

function log_print() {
  while read data; do
    echo -e "$(date +"%d/%b/%Y:%H:%M:%S %:::z") $data" | tee -a $LOG_FILE
  done
}

function check_if_running() {
  if [ -f $pidfile ]; 
  then

    echo -e "script is already running"  | log_print
    resetcolor;

    local old_pid=$( cat $pidfile )
    if [ "${ARGS[0]}" == "--force" ]; then
        echo -e "clean script start..."  | log_print
        kill -9 $old_pid
        rm -rf $pidfile
        echo $TOP_PID >"$pidfile"
    else
        echo -e "run script by --force to skip limitation "  | log_print
        exit 0
    fi


  else
    echo $TOP_PID >"$pidfile"
  fi
}

function finisher() {
  trap "rm -f -- '$pidfile'" EXIT
}



function checkDpnd {
   command -v curl >/dev/null 2>&1 || { echo -e "I require 'curl' but it's not installed. Please install it and try again." | log_print; kill -s 1 "$TOP_PID"; }
   command -v gpg >/dev/null 2>&1 || { echo -e "I require 'gpg' but it's not installed. Please install it and try again." | log_print; kill -s 1 "$TOP_PID"; }
   command -v rsync >/dev/null 2>&1 || { echo -e "I require 'rsync' but it's not installed. Please install it and try again." | log_print; kill -s 1 "$TOP_PID"; }
   command -v ftp >/dev/null 2>&1 || { echo -e "I require 'ftp' but it's not installed. Please install it and try again." | log_print; kill -s 1 "$TOP_PID"; }
}

function config_check() {
    if [ ! -f $config_path/main.conf ];
    then
        mkdir -p $intervalConfigFiles_path > /dev/null 2>&1
        cat <<EOF > $config_path/main.conf

### Path ###
local_save_path="/local-backup/"
ftp_save_path="/ftp-backup/"
ssh_save_path="/ssh-backup/"

### Encryption ###
encryption_enable="no"
encryption_name="$HOSTNAME"


### FTP method ###
ftp_enable="no"
ftp_server="ftp.example.com"
ftp_username="ftpuser"
ftp_password="ftppassword"

### SSH method ###
ssh_enable="no"
ssh_server="ssh.example.com"
ssh_port=22
ssh_username="root"


#### Clean ###
local_save_last_versions=4
ftp_save_last_versions=12
ssh_save_last_versions=12
EOF

        cat <<EOF >>$intervalConfigFiles_path/$G_weekly_fileName
# Put you Absolute path bellow and seprate them by ENTER
$HOME
EOF

        touch $intervalConfigFiles_path/$G_daily_fileName $intervalConfigFiles_path/$G_monthly_fileName
        echo -e "$NOW script has been installed successfully\n$NOW write your paths in source config files: $intervalConfigFiles_path"
        exit 0
    fi
}


### init
echo -e "###########################" | log_print
echo -e "Preparing..." | log_print

check_if_running
finisher
checkDpnd
config_check

#loading conf
source $config_path/main.conf


### init
i_config_files=()
interval_config_files=$(find $intervalConfigFiles_path -type f | grep -E "$G_daily_fileName|$G_weekly_fileName|$G_monthly_fileName" | xargs)
for interval_config_file in $interval_config_files;
do
    if [ $(cat $interval_config_file | wc -l) -ne 0 ];
    then

        input_name=$(basename $interval_config_file)
        case $input_name in 

           $G_daily_fileName)
             i_config_files+=($input_name) 
             ;;

           $G_weekly_fileName)
             if [ $week_day == $week_backup_day ];
             then
                 i_config_files+=($input_name)
             fi
             ;;

           $G_monthly_fileName)
             if [ $month_day == $month_backup_day ];
             then
                 i_config_files+=($input_name)
             fi 
             ;; 
        esac
    fi

done 


if [ -z "$i_config_files" ]; 
then
    echo -e "Not found any source config files or today is not the backup day!" | log_print
    exit 0
fi



sleep 1;
###########################
##### Creating Backup #####
###########################


# Create Backup
yellow;
echo "Creating Backup archives..." | log_print
resetcolor;

i_result_files=()
for source_file in ${i_config_files[@]};
do
    ext=$(echo $source_file | cut -d "." -f 2)
    result_pre_path=$local_save_path/$ext
    mkdir -p $result_pre_path > /dev/null 2>&1

    source_file_path=$intervalConfigFiles_path/$source_file
    source_file_contents=$(cat $source_file_path | sed '/^[[:space:]]*$/d' | sed '/^#/d' | xargs)
    result=$result_pre_path/$ext-fullbackup-$HOSTNAME-$DATE.tar.gz

    tar -czf $result $source_file_contents > /dev/null 2>&1
    i_result_files+=($result)
      
done
green;
echo -e "Backup archives has have been created successfully" | log_print
resetcolor;



# GPG Encryption 
if [ "$encryption_enable" == "yes" ];
then
    yellow;
    echo -e "Encrypting Backup archives..." | log_print
    resetcolor;

    counter=0
    for res in ${i_result_files[@]};
    do
        gpg --always-trust -e -r "$encryption_name" $res

        if [ $? -ne 0 ]
        then
            red;
            echo -e "Encrypting backup archives FAILD" | log_print
            resetcolor;
            exit 0;      
        fi

        rm -rf $res
        i_result_files[$counter]="$res.gpg"
        counter=$counter+1

    done

    green;
    echo -e "Encrypting backup archives has have been completed successfully" | log_print
    resetcolor;
fi


sleep 1;
###########################
##### Uploading #####
###########################


### FTP Upload
if [ "$ftp_enable" == "yes" ];
then
    is_ok=1

    yellow;
    echo -e "Uploading to FTP-server..." | log_print
    resetcolor;

    for res in ${i_result_files[@]};
    do  
        input=$(echo $local_save_path | sed 's/\//\\\//g')
        ftp_save_path=$(echo $ftp_save_path | sed 's/\//\\\//g')
        path=$(dirname $res | sed -e "s/$input/$ftp_save_path/")
        curl --show-error --connect-timeout 10 --retry 3 --retry-delay 30 --upload-file $res --ftp-create-dirs "ftp://$ftp_server:21/$path/" --user "$ftp_username:$ftp_password"
       
        if [ $? -ne 0 ]
        then
            red;
            echo -e "Uploading to FTP-server FAILD" | log_print
            resetcolor;  
            FTP_CONNECTION_STATUS=0 
            is_ok=0   
        fi

    done


    if [ $is_ok -eq 1 ]
    then
      green;
      echo -e "Uploading to FTP-server has have been completed successfully." | log_print
      resetcolor;
    fi
fi


### SSH Upload
if [ "$ssh_enable" == "yes" ];
then
    is_ok=1

    yellow;
    echo -e "Uploading to SSH-server..." | log_print
    resetcolor;


    for res in ${i_result_files[@]};
    do  
        input=$(echo $local_save_path | sed 's/\//\\\//g')
        ssh_save_path=$(echo $ssh_save_path | sed 's/\//\\\//g')
        path=$(dirname $res | sed -e "s/$input/$ssh_save_path/") 
        ssh -t $ssh_username@$ssh_server -p $ssh_port -o StrictHostKeyChecking=no "mkdir -p /$path/"
        rsync -avh -e "ssh -p $ssh_port -o StrictHostKeyChecking=no" $res $ssh_username@$ssh_server:/$path/ | log_print
       
        if [ $? -ne 0 ]
        then
            red;
            echo -e "Uploading to SSH-server FAILD" | log_print
            resetcolor;
            SSH_CONNECTION_STATUS=0
            is_ok=0    
        fi

    done

    if [ $is_ok -eq 1 ]
    then
      green;
      echo -e "Uploading to SSH-server has have been completed successfully." | log_print
      resetcolor;
    fi

fi



sleep 1;
###########################
##### Cleaning #####
###########################


### Local
yellow;
echo -e "Cleaning local backups older than $local_save_last_versions last old versions..." | log_print
resetcolor;

i_local_queue=()
for source_file in ${i_config_files[@]};
do
  source_file=$(echo $source_file | cut -d "." -f 2)
  local_path_dir=$local_save_path/$source_file

  count=$(( $(ls -ltr $local_path_dir | grep "^-r" | wc -l) - $local_save_last_versions ))
  if [ $count -gt 0 ]; 
  then
      files=$(ls -ltr $local_path_dir | grep "^-r" | head -n $count | awk '{print $NF}' | awk -F ' ' -v awklocal_path_dir="$local_path_dir/" '{print awklocal_path_dir $1}' | xargs)
      i_local_queue+=($files)
  fi

done

if [ -z "$i_local_queue" ]; 
then
    echo -e "ّNot need." | log_print
else
    rm -rf ${i_local_queue[@]}
    echo -e "ّFiles: $files" | log_print

    green;
    echo -e "Cleaning Done." | log_print
fi

resetcolor;



### FTP
if [ "$ftp_enable" == "yes" ] && [ $FTP_CONNECTION_STATUS == 1 ];
then
    is_ok=1

    yellow;
    echo -e "Cleaning remote ftp backups older than $ftp_save_last_versions last old versions..." | log_print
    resetcolor;

    i_ftp_queue=()
    for source_file in ${i_config_files[@]};
    do
        sleep 1

        source_file=$(echo $source_file | cut -d "." -f 2) 
        ftp_path_dir=$ftp_save_path/$source_file

        ftp -i -n $ftp_server <<EOMYF > $tmp_log
        user $ftp_username $ftp_password
        binary
        cd $ftp_path_dir
        ls --sort 
        quit
EOMYF

        count=$(( $(cat $tmp_log | grep -v "drwxr" | wc -l) - $ftp_save_last_versions ))
        if [ $count -gt 0 ]; 
        then
            ftp_dirs_list_path=$(cat $tmp_log | grep -v "drwxr" | awk '{print $NF}' | head -n $count | awk -F ' ' -v awkftp_path_dir="$ftp_path_dir/" '{print awkftp_path_dir $1}' | xargs)
            i_ftp_queue+=($ftp_dirs_list_path)
        fi
      
    done


    if [ -z "$i_ftp_queue" ]; 
    then
        echo -e "ّNot need." | log_print
    else

        ftp -i -n $ftp_server <<EOMYF 
        user $ftp_username $ftp_password
        binary
        mdelete ${i_ftp_queue[@]}
        quit
EOMYF

        echo -e "ّFiles: ${i_ftp_queue[@]}" | log_print

        green;
        echo -e "Cleaning FTP-server Done." | log_print

    fi
    resetcolor;

fi


### SSH
if [ "$ssh_enable" == "yes" ] && [ $SSH_CONNECTION_STATUS == 1 ];
then
    yellow;
    echo -e "Cleaning SSH backups older than $ssh_save_last_versions last old versions..." | log_print
    resetcolor;

    i_ssh_queue=()
    for source_file in ${i_config_files[@]};
    do
        source_file=$(echo $source_file | cut -d "." -f 2)
        ssh_path_dir=$ssh_save_path/$source_file

        
        ssh -t $ssh_username@$ssh_server -p $ssh_port -o StrictHostKeyChecking=no <<EOMYF > $tmp_log
        ls -ltr $ssh_path_dir
EOMYF

        count=$(( $(cat $tmp_log | grep "^-r" | wc -l) - $ssh_save_last_versions ))
        if [ $count -gt 0 ]; 
        then
          ssh_dirs_list_path=$(cat $tmp_log | grep "^-r" | head -n $count | awk '{print $NF}' | awk -F ' ' -v awkssh_path_dir="$ssh_path_dir/" '{print awkssh_path_dir $1}' | xargs)
          i_ssh_queue+=($ssh_dirs_list_path)
        fi

    done


    if [ -z "$i_ssh_queue" ]; 
    then
        echo -e "ّNot need." | log_print
    else
        ssh -t $ssh_username@$ssh_server -p $ssh_port -o StrictHostKeyChecking=no "rm -rf ${i_ssh_queue[@]}"
        echo -e "ّFiles: $ssh_dirs_list_path" | log_print

        green;
        echo -e "Cleaning Done." | log_print
    fi
    resetcolor;
fi



########## Final ###########
echo -e "" | log_print
green;
echo -e "*** Backup finished ***" | log_print
resetcolor;
echo -e "Backup files:" | log_print

for res in ${i_result_files[@]};
do
    res=$(echo $res | sed "s/\/\//\//")
    archive_size=$(ls -lh $res | awk '{print  $5}')
    yellow;
    echo -e "$res : $archive_size" | log_print
    resetcolor;
done

rm -rf $tmp_log
exit 0
