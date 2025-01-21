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

# Set DNS server (Google DNS)
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf > /dev/null

# Install Dependencies
log "info" "Update Repositories"
sudo apt-get update -y
sudo apt upgrade -y

# Install Net Tools
log "info" "Installing net-tools..."
sudo apt install -y net-tools openssl pwgen