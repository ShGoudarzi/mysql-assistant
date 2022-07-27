# mysql-assistant
Pure Bash script for Generate/Restore Full Backup of MySQL Users and Databases in/to Normal or Container Base mode

+ Generate/Restore Full backup of MySQL `Users` and `Databases`
+ Worck both for MySQL server running in `Container` or `Normal` mode
+ Write the output log to `/var/log/mysql-assistant/`
+ Auto delete backup files older than 30 days
+ Easy to use as cron jobs


## Download
```bash
curl -o /usr/bin/mysql-assistant.sh -L https://raw.githubusercontent.com/ShGoudarzi/mysql-assistant/main/mysql-assistant.sh \
&& chmod +x /usr/bin/mysql-assistant.sh
```

## Usage
```
mysql-assistant.sh --help
```

## Options

| switch | Default | Example | Description |
| - | - | - | - |
| `--path` | - | `--path=/Backup/db-dailyBackup` | for generating Backup is Where to save backup file. for Restoring backup is the path of the backup file(.tar.gz) |
| `--container-name` | - | `--container-name=mariadb` | Name of MySQL container ( If in container base mode ) |
| `--mysql-root-pass` | `MySQL container env` | `--mysql-root-pass=12345` | MySQL root password ( Only necessary if not found automatically ) |
> 💡 At generating full-backup mode you can also pass every mysqldump switches to the script for use during dumping databases ( like: --force )


## Examples

#### Generate FullBackup:

> Container mode:

+ mysql-assistant.sh   --full-backup --path=`/Backup/db-dailyBackup` --container-name=`mariadb`

> Normal mode:

+ mysql-assistant.sh   --full-backup --path=`/Backup/db-dailyBackup`

-----------------------------------------------------------------

#### Restore FullBackup:

> Container mode:

+ mysql-assistant.sh   --full-restore --path=`/Backup/db-dailyBackup/sample-backup-file.tar.gz` --container-name=`mariadb`

> Normal mode:

+ mysql-assistant.sh   --full-restore --path=`/Backup/db-dailyBackup`


-----------------------------------------------------------------

-----------------------------------------------------------------

### Cron Job
```
00 04 * * * mysql-assistant.sh --full-backup --path=/Backup/db-dailyBackup --container-name=mariadb >/dev/null 2>&1
```
> 💡 This will start backing up the databases, daily 4:00 AM
