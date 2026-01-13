#!/bin/bash

#================
# Log Definitions
#================
export LINE='\n'                        # Line Break
export RESET='\033[0m'                  # Text Reset
export WhiteText='\033[0;37m'           # White

# Bold
export RedBoldText='\033[1;31m'         # Red
export GreenBoldText='\033[1;32m'       # Green
export YellowBoldText='\033[1;33m'      # Yellow
export CyanBoldText='\033[1;36m'        # Cyan
#================
# End Log Definitions
#================

LogInfo() {
  Log "$1" "$WhiteText"
}
LogWarn() {
  Log "$1" "$YellowBoldText"
}
LogError() {
  Log "$1" "$RedBoldText"
}
LogSuccess() {
  Log "$1" "$GreenBoldText"
}
LogAction() {
  Log "$1" "$CyanBoldText" "====" "===="
}
Log() {
  local message="$1"
  local color="$2"
  local prefix="$3"
  local suffix="$4"
  printf "$color%s$RESET$LINE" "$prefix$message$suffix"
}

download_server() {
  LogAction "Starting server download"
  LogInfo "Downloading Hytale Dedicated Server"
  
  local SERVER_FILES="/home/hytale/server-files"
  local DOWNLOADER_URL="https://downloader.hytale.com/hytale-downloader.zip"
  local DOWNLOADER_ZIP="$SERVER_FILES/hytale-downloader.zip"
  local DOWNLOADER_DIR="$SERVER_FILES/downloader"
  
  mkdir -p "$SERVER_FILES"
  cd "$SERVER_FILES" || exit 1
  
  # Check if server files already exist
  if [ -f "$SERVER_FILES/Server/HytaleServer.jar" ] && [ -f "$SERVER_FILES/Assets.zip" ]; then
    LogSuccess "Server files already exist, checking for updates..."
    
    # Download the downloader if it doesn't exist
    DOWNLOADER_EXEC=$(find "$DOWNLOADER_DIR" -name "hytale-downloader-linux-*" -type f | head -1)
    if [ -z "$DOWNLOADER_EXEC" ]; then
      LogInfo "Downloading Hytale Downloader..."
      wget -q "$DOWNLOADER_URL" -O "$DOWNLOADER_ZIP" || {
        LogError "Failed to download Hytale Downloader"
        return 1
      }
      
      mkdir -p "$DOWNLOADER_DIR"
      unzip -o -q "$DOWNLOADER_ZIP" -d "$DOWNLOADER_DIR" || {
        LogError "Failed to extract Hytale Downloader"
        return 1
      }
      
      DOWNLOADER_EXEC=$(find "$DOWNLOADER_DIR" -name "hytale-downloader-linux-*" -type f | head -1)
      if [ -z "$DOWNLOADER_EXEC" ]; then
        LogError "Could not find hytale-downloader executable"
        return 1
      fi
      
      chmod +x "$DOWNLOADER_EXEC"
      rm "$DOWNLOADER_ZIP"
    fi
    
    # Check current version
    local CURRENT_VERSION
    CURRENT_VERSION=$("$DOWNLOADER_EXEC" -print-version 2>&1 | grep -v "^$" | tail -1)
    LogInfo "Current version: ${CURRENT_VERSION}"
    
    # Download latest version
    LogInfo "Downloading latest server files..."
    cd "$(dirname "$DOWNLOADER_EXEC")" || exit 1
    ./$(basename "$DOWNLOADER_EXEC") -download-path "$SERVER_FILES/game.zip" || {
      LogError "Failed to download server files"
      return 1
    }
    
    # Check if authentication was successful by looking for credentials file
    if [ -f "$DOWNLOADER_DIR/.hytale-downloader-credentials.json" ]; then
      LogSuccess "Hytale Authentication Successful"
    fi
    
    # Extract the new files
    LogInfo "Extracting server files..."
    cd "$SERVER_FILES" || exit 1
    unzip -o -q game.zip || {
      LogError "Failed to extract server files"
      return 1
    }
    rm game.zip
    
    LogSuccess "Server files updated successfully"
  else
    LogInfo "First time setup - downloading server files..."
    
    # Download the downloader
    LogInfo "Downloading Hytale Downloader..."
    wget -q "$DOWNLOADER_URL" -O "$DOWNLOADER_ZIP" || {
      LogError "Failed to download Hytale Downloader"
      LogError "Please check your internet connection and try again"
      return 1
    }
    
    mkdir -p "$DOWNLOADER_DIR"
    unzip -o -q "$DOWNLOADER_ZIP" -d "$DOWNLOADER_DIR" || {
      LogError "Failed to extract Hytale Downloader"
      return 1
    }
    
    # Find the hytale-downloader executable (Linux version for Docker)
    DOWNLOADER_EXEC=$(find "$DOWNLOADER_DIR" -name "hytale-downloader-linux-*" -type f | head -1)
    if [ -z "$DOWNLOADER_EXEC" ]; then
      LogError "Could not find hytale-downloader executable in downloaded archive"
      ls -laR "$DOWNLOADER_DIR"
      return 1
    fi
    
    chmod +x "$DOWNLOADER_EXEC"
    rm "$DOWNLOADER_ZIP"
    
    LogInfo "Downloading server files (this may take a while)..."
    cd "$(dirname "$DOWNLOADER_EXEC")" || exit 1
    ./$(basename "$DOWNLOADER_EXEC") -download-path "$SERVER_FILES/game.zip" || {
      LogError "Failed to download server files"
      return 1
    }
    
    # Check if authentication was successful by looking for credentials file
    if [ -f "$DOWNLOADER_DIR/.hytale-downloader-credentials.json" ]; then
      LogSuccess "Hytale Authentication Successful"
    fi
    
    # Extract the files
    LogInfo "Extracting server files..."
    cd "$SERVER_FILES" || exit 1
    unzip -o -q game.zip || {
      LogError "Failed to extract server files"
      return 1
    }
    rm game.zip
    
    LogSuccess "Server files downloaded and extracted successfully"
  fi
  
  # Verify files exist
  if [ ! -f "$SERVER_FILES/Server/HytaleServer.jar" ]; then
    LogError "HytaleServer.jar not found after download"
    return 1
  fi
  
  if [ ! -f "$SERVER_FILES/Assets.zip" ]; then
    LogError "Assets.zip not found after download"
    return 1
  fi
  
  LogSuccess "Server download completed"
}

# Attempt to shutdown the server gracefully
# Returns 0 if it is shutdown
# Returns 1 if it is not able to be shutdown
shutdown_server() {
    local return_val=0
    LogAction "Attempting graceful server shutdown"
    
    # Find the process ID
    local pid=$(pgrep -f HytaleServer.jar)
    
    if [ -n "$pid" ]; then
        # Send SIGTERM to allow graceful shutdown
        kill -SIGTERM "$pid"
        
        # Wait up to 30 seconds for process to exit
        local count=0
        while [ $count -lt 30 ] && kill -0 "$pid" 2>/dev/null; do
            sleep 1
            count=$((count + 1))
        done
        
        # Check if process is still running
        if kill -0 "$pid" 2>/dev/null; then
            LogWarn "Server did not shutdown gracefully, forcing shutdown"
            return_val=1
        else
            LogSuccess "Server shutdown gracefully"
        fi
    else
        LogWarn "Server process not found"
        return_val=1
    fi
    
    return "$return_val"
}
