#!/bin/bash

log() {
    level=$1
    message=$2
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    case $level in
        info)
            printf "[%s] \033[34mINFO\033[0m: %s\n" "$timestamp" "$message"
            ;;
        success)
            printf "[%s] \033[32mSUCCESS\033[0m: %s\n" "$timestamp" "$message"
            ;;
        warn)
            printf "[%s] \033[33mWARN\033[0m: %s\n" "$timestamp" "$message"
            ;;
        error)
            printf "[%s] \033[31mERROR\033[0m: %s\n" "$timestamp" "$message"
            ;;
        *)
            printf "[%s] \033[37mUNKNOWN\033[0m: %s\n" "$timestamp" "$message"
            ;;
    esac
}

log "info" "Install MySQL Client and Server"
sudo apt install mysql-server -y

log "info" "Starting the MySQL Service"
start_output=$(sudo systemctl start mysql 2>&1)
start_status=$?

if [ $start_status -eq 0 ]; then
    log "success" "MySQL service started successfully."
else
    log "error" "Failed to start MySQL service. Output: $start_output"
fi

