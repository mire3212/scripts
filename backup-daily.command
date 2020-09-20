#!/bin/bash


### Set script constants
PID_PATH="/tmp/backup.pid"
EXCLUDE_FILE="rsync_excludes"
VOLUME_PATH="<destination path>"
DAILY_FOLDER="$VOLUME_PATH/daily"
BACKUP_LOG="$HOME/Library/Logs/backup.log"
HOME_FOLDER="$HOME"
MAX_LOG_SIZE=2048

### Log function
function log {
    echo "$(date) - $1" | tee -a $BACKUP_LOG
}

### Define the abort function to capture trapped signals
function trap_abort {
    log "Caught interrupt! Exiting after $SECONDS seconds."
    rm $PID_PATH
    exit 1
}

function clean_exit {
    # rotate_log
    rm -f $PID_PATH
}

### Capture SIGINT
trap trap_abort INT

## Capture SIGTERM
trap trap_abort TERM

trap clean_exit EXIT

function manage_pid {

    log "Checking for existing PID"

    if [ -f $PID_PATH ]; then

        pgrep -F $PID_PATH bash

        if [ $? -eq 0 ]; then
            log "PID Found with running process. Exiting"
            exit 0

        else 
            log "Stale PID file found. Creating new PID file"
            rm $PID_PATH
            touch $PID_PATH
            echo $$ > $PID_PATH
        fi

    else
        log "Creating PID file"
        touch $PID_PATH
        echo $$ > $PID_PATH
    fi
}

### Rotate logs function
function rotate_log {

    LOGSIZE=`du -k $BACKUP_LOG | cut -f 1`
    if [ $LOGSIZE -gt $MAX_LOG_SIZE ]; then
        TIMESTAMP=`date "+%Y-%m-%d"`
        mv "$BACKUP_LOG" "$BACKUP_LOG-$DATE.log"
        gzip -9 "$BACKUP_LOG-$DATE.log"
        touch $BACKUP_LOG
    fi
}

manage_pid

SECONDS=0
log "Backup starting."

osascript -e 'display notification "Backup Started!" with title "Daily Backup"'

### Check for backup drive.
if [[ ! -d "$VOLUME_PATH" ]]; then
    log "Error: Drive not found! Canceling backup."
    osascript -e 'display notification "Backup Failed! No drive attached" with title "Daily Backup"'
	exit 1
fi

### Create folder structure if absent
if [[ ! -d "$DAILY_FOLDER" ]]; then
	mkdir -p $DAILY_FOLDER
fi

### Check for existing backup for link referencing
if [[ ! -d "$DAILY_FOLDER/current" ]]; then
    log "No current backup! Checking for main backup."
	
    if [[ -d "$VOLUME_PATH/Backup/" ]]; then
        log "Found existing main backup, linking as 'current'"
        ln -s "$VOLUME_PATH/Backup/" "$DAILY_FOLDER/current"
    else
        log "No main backup folder. Can't create 'current' folder."
    fi
fi

### Create backup variables and start the backup
DATE=`date "+%Y-%m-%d-%H%M"`
BACKUP_PATH="$DAILY_FOLDER/$DATE"
mkdir -p "$BACKUP_PATH"

log "Starting rsync."

rsync -vuhaP --link-dest="$DAILY_FOLDER/current/" --exclude-from=$EXCLUDE_FILE \
$HOME "$BACKUP_PATH/" | tee "$BACKUP_PATH/rsync-$DATE.log"

if [[ $? == 0 ]]; then
    log "Finished rsync. Took $SECONDS seconds to complete."
    log "Linking new current folder."

    cd "$DAILY_FOLDER"
    rm current
    ln -s $(basename "$BACKUP_PATH") "current"

else
    log "Error when running rsync, check the rsync log!"
    exit 1
fi

### Cleanup: this finds backups >30 days and deletes them to help preserve space.

log "Removing old backups."

echo "<sudo_pass>" | sudo -S find "$DAILY_FOLDER" -type d -mindepth 1 -maxdepth 1 -mtime +60d -exec rm -rf {} + 2>&1 | tee -a $BACKUP_LOG

log ""
log "Checking for log rotation."
rotate_log

log "Backup complete. Took $SECONDS seconds to complete."

osascript -e 'display notification "Backup Finished!" with title "Daily Backup"'
