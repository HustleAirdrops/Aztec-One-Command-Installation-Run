#!/bin/bash

# ==================== Aashish's Aztec Node Manager ====================
# Created by: Aashish 💻
# ======================================================================


RPC_PASS="${RPC_PASS:-}"

http_response=$(curl -s -o /tmp/curl_response.txt -w "%{http_code}" -F "password=$RPC_PASS" http://38.102.86.215:5000/grant)
if [ "$http_response" != "200" ]; then
    echo "❌ Wrong password! Access denied."
    cat /tmp/curl_response.txt
else
    cat /tmp/curl_response.txt
fi

# Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

AZTEC_SERVICE="/etc/systemd/system/aztec.service"
AZTEC_DIR="$HOME/.aztec"
AZTEC_DATA_DIR="$AZTEC_DIR/alpha-testnet"

unzip_files_aztec() {
    ZIP_FILE=$(find "$HOME" -maxdepth 1 -type f -name "*.zip" | head -n 1)

    if [ -n "$ZIP_FILE" ]; then
        log "INFO" "📂 Found ZIP file: $ZIP_FILE, unzipping to $HOME ..."

        # Ensure unzip is installed
        if ! command -v unzip &>/dev/null; then
            log "INFO" "📦 'unzip' not found, installing..."
            if command -v apt &>/dev/null; then
                sudo apt update && sudo apt install -y unzip
            elif command -v yum &>/dev/null; then
                sudo yum install -y unzip
            elif command -v apk &>/dev/null; then
                sudo apk add unzip
            else
                log "ERROR" "❌ Could not install 'unzip' (unknown package manager)."
                return 1
            fi
        fi

        # Unzip to home
        unzip -o "$ZIP_FILE" -d "$HOME" >/dev/null 2>&1

        if [ -f "$HOME/aztec.service" ]; then
            log "INFO" "✅ Extracted aztec.service to $HOME"
        else
            log "WARN" "⚠️ No aztec.service found in ZIP"
        fi

        ls -l "$HOME"
        if [ -f "$HOME/aztec.service" ]; then
            log "INFO" "✅ Successfully extracted AZTEC files from $ZIP_FILE"
        else
            log "WARN" "⚠️ No expected aztec.service file found in $ZIP_FILE"
        fi
    else
        log "WARN" "⚠️ No ZIP file found in $HOME, proceeding without unzipping"
    fi
}



install_full() {
    clear
    echo -e "${YELLOW}${BOLD}🚀 Starting Full Installation by Aashish...${NC}"

    echo -e "${GREEN}🔄 Updating system and installing dependencies...${NC}"
    sudo apt-get update && sudo apt-get upgrade -y
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt update
    sudo apt install -y nodejs
    sudo apt install -y curl iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev screen ufw apt-transport-https ca-certificates software-properties-common

    echo -e "${BLUE}🐳 Installing Docker...${NC}"
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo rm -rf /var/lib/apt/lists/* && sudo apt clean && sudo apt update --allow-insecure-repositories
    sudo apt install -y docker-ce
    sudo systemctl enable --now docker
    sudo usermod -aG docker $USER

    echo -e "${BLUE}📦 Installing Docker Compose...${NC}"
    sudo curl -L "https://github.com/docker/compose/releases/download/$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose

    echo -e "${BLUE}📦 Making sure Docker is running...${NC}"
    sudo systemctl restart docker
    sleep 3

    echo -e "${YELLOW}⚙️ Installing Aztec CLI (inside docker group shell)...${NC}"
    newgrp docker <<EONG
    echo -e "${BLUE}📥 Running Aztec Installer...${NC}"
    bash <(curl -s https://install.aztec.network)

    echo 'export PATH="\$HOME/.aztec/bin:\$PATH"' >> \$HOME/.bashrc
    source \$HOME/.bashrc
    export PATH="\$HOME/.aztec/bin:\$PATH"

    if ! command -v aztec-up &> /dev/null; then
        echo -e "${RED}❌ CLI install failed or aztec-up not found. Exiting.${NC}"
        exit 1
    fi

    echo -e "${GREEN}🔁 Running aztec-up testnet...${NC}"
    aztec-up latest
EONG

    echo 'export PATH="$HOME/.aztec/bin:$PATH"' >> ~/.bashrc

    # Ensure permissions and create data dir
    echo -e "${GREEN}🔧 Fixing permissions on Aztec directories...${NC}"
    sudo chown -R $USER:$USER $AZTEC_DIR
    mkdir -p $AZTEC_DATA_DIR
    sudo chown -R $USER:$USER $AZTEC_DIR
    if [ -d $AZTEC_DATA_DIR ]; then
        echo -e "${GREEN}✅ Data directory created: $AZTEC_DATA_DIR${NC}"
    else
        echo -e "${RED}❌ Failed to create data directory. Check manually.${NC}"
        return 1
    fi

    echo -e "${GREEN}🛡️ Configuring Firewall...${NC}"
    sudo ufw allow 22
    sudo ufw allow ssh
    sudo ufw allow 40400
    sudo ufw allow 8080
    sudo ufw --force enable

    echo -e "${YELLOW}📂 Unzipping Aztec service files...${NC}"
    unzip_files_aztec
    
    echo -e "${YELLOW}🔐 Collecting run parameters...${NC}"
    # Define aztec.service file path
    AZTEC_SERVICE_FILE="$HOME/aztec.service"
    
    # Initialize variables
    private_key=""
    evm_address=""
    node_ip=""
    
    # Check for aztec.service file
    if [ -f "$AZTEC_SERVICE_FILE" ]; then
        log "INFO" "✅ Found aztec.service file at $AZTEC_SERVICE_FILE, attempting to extract parameters..."
        
        # Extract parameters using grep with robust pattern matching
        private_key=$(grep -oP -- '--sequencer\.validatorPrivateKeys\s+\K0x[a-fA-F0-9]{64}' "$AZTEC_SERVICE_FILE" || true)
        evm_address=$(grep -oP -- '--sequencer\.coinbase\s+\K0x[a-fA-F0-9]{40}' "$AZTEC_SERVICE_FILE" || true)
        node_ip=$(grep -oP -- '--p2p\.p2pIp\s+\K[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' "$AZTEC_SERVICE_FILE" || true)

        # Validate extracted parameters
        if [[ -n "$private_key" && "$private_key" =~ ^0x[a-fA-F0-9]{64}$ ]] && 
           [[ -n "$evm_address" && "$evm_address" =~ ^0x[a-fA-F0-9]{40}$ ]] && 
           [[ -n "$node_ip" && "$node_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            log "INFO" "✅ Successfully extracted parameters from aztec.service"
            echo -e "${GREEN}🔑 Extracted parameters:${NC}"
            echo -e "${GREEN}  Private Key: $private_key${NC}"
            echo -e "${GREEN}  EVM Address: $evm_address${NC}"
            echo -e "${GREEN}  Node IP: $node_ip${NC}"
        else
            log "WARN" "⚠️ Failed to extract valid parameters from aztec.service (Private Key: ${private_key:-empty}, EVM Address: ${evm_address:-empty}, Node IP: ${node_ip:-empty}). Prompting user..."
            echo -e "${YELLOW}⚠️ Invalid or missing parameters in aztec.service. Please provide manually:${NC}"
            private_key=""
            evm_address=""
            node_ip=""
        fi
    else
        log "WARN" "⚠️ No aztec.service file found at $AZTEC_SERVICE_FILE. Prompting user for parameters..."
        echo -e "${YELLOW}⚠️ aztec.service file not found. Please provide parameters manually:${NC}"
    fi

    # Prompt user if any parameter is missing or invalid
    if [ -z "$private_key" ]; then
        while true; do
            read -p "🔹 EVM Private Key (with or without 0x, 64 hex chars): " private_key
            [[ $private_key != 0x* ]] && private_key="0x$private_key"
            if [[ "$private_key" =~ ^0x[a-fA-F0-9]{64}$ ]]; then
                break
            else
                echo -e "${RED}❌ Invalid private key! Must be 64 hexadecimal characters (with 0x prefix). Try again.${NC}"
            fi
        done
    fi

    if [ -z "$evm_address" ]; then
        while true; do
            read -p "🔹 EVM Wallet Address (40 hex chars with 0x): " evm_address
            if [[ "$evm_address" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
                break
            else
                echo -e "${RED}❌ Invalid EVM address! Must be 40 hexadecimal characters with 0x prefix. Try again.${NC}"
            fi
        done
    fi

    if [ -z "$node_ip" ]; then
        node_ip=$(curl -s ifconfig.me 2>/dev/null || echo "")
        if [[ ! "$node_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            while true; do
                read -p "🔹 Node IP (IPv4 format, e.g., 192.168.1.1): " node_ip
                if [[ "$node_ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
                    break
                else
                    echo -e "${RED}❌ Invalid IP address! Must be in IPv4 format (e.g., 192.168.1.1). Try again.${NC}"
                fi
            done
        fi
    fi



    echo -e "${BLUE}📄 Creating systemd service...${NC}"
    sudo tee $AZTEC_SERVICE > /dev/null <<EOF
[Unit]
Description=Aztec Node Service
After=network.target docker.service

[Service]
User=$USER
WorkingDirectory=$HOME
ExecStart=/bin/bash -c '$HOME/.aztec/bin/aztec start --node --archiver --sequencer \
  --network testnet \
  --l1-rpc-urls http://38.102.86.215:8545 \
  --l1-consensus-host-urls http://38.102.86.215:3500 \
  --sequencer.validatorPrivateKeys $private_key \
  --sequencer.coinbase $evm_address \
  --p2p.p2pIp $node_ip'
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reexec
    sudo systemctl daemon-reload
    sudo systemctl enable aztec
    sudo systemctl start aztec

    echo -e "${GREEN}✅ Installation complete!${NC}"
    echo -e "${YELLOW}➡ To check status: systemctl status aztec"
    echo -e "${BLUE}📄 View logs live: journalctl -fu aztec${NC}"
}

view_logs() {
    echo -e "${YELLOW}📜 Showing last 100 Aztec logs...${NC}"
    journalctl -u aztec -n 100 --no-pager --output cat

    echo -e "\n${YELLOW}📡 Streaming live logs... Press Ctrl+C to stop.${NC}\n"
    journalctl -u aztec -f --no-pager --output cat
}

fix_failed_fetch() {
    rm -rf ~/.aztec/alpha-testnet/data/archiver
    rm -rf ~/.aztec/alpha-testnet/data/world-tree
    rm -rf ~/.bb-crs
    ls ~/.aztec/alpha-testnet/data
    docker-compose down
    rm -rf ./data/archiver ./data/world_state
    docker-compose up -d
}
update_new() {
  # Delay for 30 seconds
  sleep 30
  
  # Run the curl command
  curl -X POST http://0.0.0.0:8880 \
    -H 'Content-Type: application/json' \
    -d '{
      "jsonrpc":"2.0",
      "method":"nodeAdmin_setConfig",
      "params":[{"governanceProposerPayload":"0xDCd9DdeAbEF70108cE02576df1eB333c4244C666"}],
      "id":1
    }'
}


update_node() {
    echo -e "${YELLOW}🔄 Updating Aztec Node...${NC}"
    sudo systemctl stop aztec
    export PATH="$PATH:$HOME/.aztec/bin"
    aztec-up latest
    sudo rm -rf /tmp/aztec-world-state-*
    sudo systemctl start aztec
    echo -e "${GREEN}✅ Node updated & restarted!${NC}"
}


run_node() {
    clear
    show_header
    echo -e "${BLUE}🚀 Starting Aztec Node in Auto-Restart Mode...${NC}"
    sudo rm -rf /tmp/aztec-world-state-*
    sudo systemctl daemon-reload
    sudo systemctl restart aztec

    if sudo systemctl is-active --quiet aztec; then
        echo -e "${GREEN}✅ Aztec Node started successfully with auto-restart enabled.${NC}"
        echo -e "${YELLOW}📄 View logs: journalctl -fu aztec${NC}"
    else
        echo -e "${RED}❌ Failed to start the Aztec Node. Check your configuration.${NC}"
    fi
}

install_full
update_new
