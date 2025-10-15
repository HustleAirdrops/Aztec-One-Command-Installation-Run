#!/bin/bash

# ==================== Aashish's Aztec Node Manager ====================
# Created by: Aashish 💻
# Updated for Aztec 2.0.2: Changed --network alpha-testnet to --network testnet
# Fixes: Added chown for permissions on ~/.aztec/testnet/data; Removed outdated fix_failed_fetch
# ======================================================================

# Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

AZTEC_SERVICE="/etc/systemd/system/aztec.service"
AZTEC_DIR="$HOME/.aztec"
AZTEC_DATA_DIR="$AZTEC_DIR/testnet"

sanitize_input() {
    local input="$1"
    echo "$input" | tr -d '"'\''\\'
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
    sudo apt install -y docker.io
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

    # FIX: Ensure proper ownership and create data dir to avoid EACCES errors
    echo -e "${GREEN}🔧 Fixing permissions on Aztec directories...${NC}"
    sudo chown -R $USER:$USER $AZTEC_DIR
    mkdir -p $AZTEC_DATA_DIR
    chown -R $USER:$USER $AZTEC_DIR
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
    sudo ufw allow 8880
    sudo ufw --force enable

    echo -e "${YELLOW}🔐 Collecting run parameters...${NC}"
    read -p "🔹 Sepolia L1 RPC URL: " l1_rpc
    read -p "🔹 Beacon Consensus RPC URL: " beacon_rpc
    read -p "🔹 EVM Private Key (with or without 0x): " private_key
    [[ $private_key != 0x* ]] && private_key="0x$private_key"
    read -p "🔹 EVM Wallet Address: " evm_address
    node_ip=$(curl -s ifconfig.me)
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
  --l1-rpc-urls $l1_rpc \
  --l1-consensus-host-urls $beacon_rpc \
  --sequencer.validatorPrivateKeys $private_key \
  --sequencer.coinbase $evm_address \
  --p2p.p2pIp $node_ip \
  --admin-port 8880'
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

    # COMMENTED OUT: fix_failed_fetch is outdated for testnet (auto-syncs snapshots via HTTP; no docker-compose needed)
    # fix_failed_fetch
}

view_logs() {
    echo -e "${YELLOW}📜 Showing last 100 Aztec logs...${NC}"
    journalctl -u aztec -n 100 --no-pager --output cat

    echo -e "\n${YELLOW}📡 Streaming live logs... Press Ctrl+C to stop.${NC}\n"
    journalctl -u aztec -f --no-pager --output cat
}

reconfigure() {
    echo -e "${YELLOW}🔧 Reconfiguring RPC URLs...${NC}"

    if [ ! -f "$AZTEC_SERVICE" ]; then
        echo -e "${RED}❌ Service file not found at $AZTEC_SERVICE${NC}"
        return
    fi

    echo -e "${BLUE}📄 Reading current RPCs from service file...${NC}"
    
    old_l1_rpc=$(grep -oP '(?<=--l1-rpc-urls\s)[^\s\\]+' "$AZTEC_SERVICE")
    old_beacon_rpc=$(grep -oP '(?<=--l1-consensus-host-urls\s)[^\s\\]+' "$AZTEC_SERVICE")

    echo -e "${GREEN}🔎 Current RPCs:"
    echo -e "   🛰️ Sepolia L1 RPC       : ${YELLOW}$old_l1_rpc${NC}"
    echo -e "   🌐 Beacon Consensus RPC : ${YELLOW}$old_beacon_rpc${NC}"

    echo ""
    read -p "🔹 Enter NEW Sepolia L1 RPC: " new_l1_rpc
    read -p "🔹 Enter NEW Beacon RPC: " new_beacon_rpc

    echo -e "\n${BLUE}⛔ Stopping Aztec service...${NC}"
    sudo systemctl stop aztec

    echo -e "${YELLOW}🛠️ Replacing values in service file...${NC}"
    sudo perl -i -pe "s|--l1-rpc-urls\s+\S+|--l1-rpc-urls $new_l1_rpc|g" "$AZTEC_SERVICE"
    sudo perl -i -pe "s|--l1-consensus-host-urls\s+\S+|--l1-consensus-host-urls $new_beacon_rpc|g" "$AZTEC_SERVICE"

    echo -e "${BLUE}🔄 Reloading systemd and restarting service...${NC}"
    sudo systemctl daemon-reload
    sudo systemctl start aztec

    echo -e "${GREEN}✅ RPCs updated successfully!"
    echo -e "   🆕 New Sepolia RPC       : ${YELLOW}$new_l1_rpc${NC}"
    echo -e "   🆕 New Beacon RPC        : ${YELLOW}$new_beacon_rpc${NC}"
}

uninstall() {
    echo -e "${YELLOW}🧹 Uninstalling Aztec Node...${NC}"

    if sudo systemctl is-active --quiet aztec; then
        sudo systemctl stop aztec
    fi

    sudo systemctl disable aztec
    sudo rm -f "$AZTEC_SERVICE"
    sudo systemctl daemon-reload
    sudo rm -rf "$AZTEC_DIR"

    echo -e "${GREEN}✅ Uninstallation complete.${NC}"
}

show_peer_id() {
    clear
    peerid=$(sudo docker logs $(docker ps -q --filter "name=aztec" | head -1) 2>&1 | \
      grep -m 1 -ai 'DiscV5 service started' | grep -o '"peerId":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$peerid" ]; then
      container_id=$(sudo docker ps --filter "ancestor=$(sudo docker images --format '{{.Repository}}:{{.Tag}}' | grep aztec | head -1)" -q | head -1)
      if [ ! -z "$container_id" ]; then
        peerid=$(sudo docker logs $container_id 2>&1 | \
          grep -m 1 -ai 'DiscV5 service started' | grep -o '"peerId":"[^"]*"' | cut -d'"' -f4)
      fi
    fi

    if [ -z "$peerid" ]; then
      peerid=$(sudo docker logs $(docker ps -q --filter "name=aztec" | head -1) 2>&1 | \
        grep -m 1 -ai '"peerId"' | grep -o '"peerId":"[^"]*"' | cut -d'"' -f4)
    fi

    label=" ● PeerID"
    peerline="✓ $peerid"
    width=${#peerline}
    [ ${#label} -gt $width ] && width=${#label}
    line=$(printf '=%.0s' $(seq 1 $width))

    if [ -n "$peerid" ]; then
      echo "$line"
      echo -e "$label"
      echo -e "\e[1;32m$peerline\e[0m"
      echo "$line"
      echo

      echo -e "\e[1;34mFetching stats from Nethermind Aztec Explorer...\e[0m"
      response=$(curl -s "https://aztec.nethermind.io/api/peers?page_size=30000&latest=true")

      stats=$(echo "$response" | jq -r --arg peerid "$peerid" '
        .peers[] | select(.id == $peerid) |
        [
          .last_seen,
          .created_at,
          .multi_addresses[0].ip_info[0].country_name,
          (.multi_addresses[0].ip_info[0].latitude | tostring),
          (.multi_addresses[0].ip_info[0].longitude | tostring)
        ] | @tsv
      ')

      if [ -n "$stats" ]; then
        IFS=$'\t' read -r last first country lat lon <<<"$stats"
        last_local=$(date -d "$last" "+%Y-%m-%d - %H:%M" 2>/dev/null || echo "$last")
        first_local=$(date -d "$first" "+%Y-%m-%d - %H:%M" 2>/dev/null || echo "$first")
        printf "%-12s: %s\n" "Last Seen"   "$last_local"
        printf "%-12s: %s\n" "First Seen"  "$first_local"
        printf "%-12s: %s\n" "Country"     "$country"
        printf "%-12s: %s\n" "Latitude"    "$lat"
        printf "%-12s: %s\n" "Longitude"   "$lon"
      else
        echo -e "\e[1;31mNo stats found for this PeerID on Nethermind Aztec Explorer.\e[0m"
      fi
    else
      echo -e "\e[1;31m❌ No Aztec PeerID found.${NC}"
    fi

    echo -e "\n${YELLOW}🔁 Press Enter to return to menu...${NC}"
    read
}

# COMMENTED OUT: fix_failed_fetch is outdated for testnet (auto-syncs snapshots; no docker-compose)
# fix_failed_fetch() {
#     rm -rf ~/.aztec/testnet/data/archiver
#     rm -rf ~/.aztec/testnet/data/world-tree
#     rm -rf ~/.bb-crs
#     ls ~/.aztec/testnet/data
#     docker-compose down
#     rm -rf ./data/archiver ./data/world_state
#     docker-compose up -d
# }

update_node() {
    echo -e "${YELLOW}🔄 Updating Aztec Node to latest version...${NC}"

    # Stop the Aztec service
    echo -e "${BLUE}⛔ Stopping Aztec service...${NC}"
    if sudo systemctl is-active --quiet aztec; then
        sudo systemctl stop aztec
    fi

    # Ensure PATH includes Aztec CLI
    export PATH="$PATH:$HOME/.aztec/bin"

    # Update Aztec CLI to latest
    echo -e "${GREEN}🔁 Running aztec-up latest...${NC}"
    aztec-up latest
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Failed to run aztec-up. Check network or permissions.${NC}"
        return 1
    fi

    # Verify version
    echo -e "${BLUE}🔍 Checking Aztec CLI version...${NC}"
    aztec_version=$(aztec --version 2>/dev/null || echo "unknown")
    if [ "$aztec_version" != "unknown" ]; then
        echo -e "${GREEN}✅ Aztec CLI updated to version $aztec_version${NC}"
    else
        echo -e "${RED}❌ Failed to get version. Update may have failed.${NC}"
        return 1
    fi

    # Update systemd service file if needed
    echo -e "${YELLOW}🛠️ Checking and updating systemd service file...${NC}"
    if [ -f "$AZTEC_SERVICE" ]; then
        # Extract existing parameters
        l1_rpc=$(grep -oP '(?<=--l1-rpc-urls\s)[^\s\\]+' "$AZTEC_SERVICE" || echo "")
        beacon_rpc=$(grep -oP '(?<=--l1-consensus-host-urls\s)[^\s\\]+' "$AZTEC_SERVICE" || echo "")
        private_key=$(grep -oP '(?<=--sequencer.validatorPrivateKeys\s)[^\s\\]+' "$AZTEC_SERVICE" || echo "")
        evm_address=$(grep -oP '(?<=--sequencer.coinbase\s)[^\s\\]+' "$AZTEC_SERVICE" || echo "")
        node_ip=$(grep -oP '(?<=--p2p.p2pIp\s)[^\s\\]+' "$AZTEC_SERVICE" || echo "")

        # Sanitize extracted parameters
        l1_rpc=$(sanitize_input "$l1_rpc")
        beacon_rpc=$(sanitize_input "$beacon_rpc")
        private_key=$(sanitize_input "$private_key")
        evm_address=$(sanitize_input "$evm_address")
        node_ip=$(sanitize_input "$node_ip")

        # Validate extracted parameters
        if [[ -z "$l1_rpc" || -z "$beacon_rpc" || -z "$private_key" || -z "$evm_address" || -z "$node_ip" ]]; then
            echo -e "${RED}❌ Missing parameters in service file. Run install_full to recreate it.${NC}"
            return 1
        fi

        # Check if service file needs updating
        needs_update=false
        if grep -q -- "--network alpha-testnet" "$AZTEC_SERVICE"; then
            echo -e "${BLUE}🔧 Replacing alpha-testnet with testnet in service file...${NC}"
            needs_update=true
        fi
        if ! grep -q -- "--admin-port 8880" "$AZTEC_SERVICE"; then
            echo -e "${BLUE}🔧 Adding --admin-port 8880 to service file...${NC}"
            needs_update=true
        fi
        # Check for quoting issues or extra spaces
        if grep -q "[[:space:]]\+--" "$AZTEC_SERVICE" || ! grep -q "^ExecStart=/bin/bash -c \".* --admin-port 8880\"" "$AZTEC_SERVICE"; then
            echo -e "${BLUE}🔧 Fixing quoting and spacing in service file...${NC}"
            needs_update=true
        fi

        # If updates are needed, rewrite the service file
        if [ "$needs_update" = true ]; then
            sudo tee $AZTEC_SERVICE > /dev/null <<EOF
[Unit]
Description=Aztec Node Service
After=network.target docker.service

[Service]
User=$USER
WorkingDirectory=$HOME
ExecStart=/bin/bash -c "$HOME/.aztec/bin/aztec start --node --archiver --sequencer --network testnet --l1-rpc-urls $l1_rpc --l1-consensus-host-urls $beacon_rpc --sequencer.validatorPrivateKeys $private_key --sequencer.coinbase $evm_address --p2p.p2pIp $node_ip --admin-port 8880"
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✅ Service file updated successfully${NC}"
            else
                echo -e "${RED}❌ Failed to update service file. Check manually.${NC}"
                return 1
            fi
        else
            echo -e "${GREEN}✅ Service file is up to date${NC}"
        fi

        # Validate systemd service file
        echo -e "${BLUE}🔍 Validating systemd service file...${NC}"
        if ! sudo systemd-analyze verify "$AZTEC_SERVICE" > /dev/null 2>&1; then
            echo -e "${RED}❌ Invalid systemd service file. Contents of $AZTEC_SERVICE:${NC}"
            cat "$AZTEC_SERVICE"
            echo -e "${RED}❌ Check the service file for errors and try again.${NC}"
            return 1
        fi
    else
        echo -e "${RED}❌ Service file not found at $AZTEC_SERVICE. Run install first.${NC}"
        return 1
    fi

    # Clean up old data
    sudo rm -rf $HOME/.aztec/alpha-testnet
    sudo rm -rf /tmp/aztec-world-state-*
    sudo chown -R $USER:$USER $AZTEC_DIR
    mkdir -p $AZTEC_DATA_DIR
    sudo chown -R $USER:$USER $AZTEC_DIR
    if [ -d $AZTEC_DATA_DIR ]; then
        echo -e "${GREEN}✅ Data directory ready: $AZTEC_DATA_DIR${NC}"
    else
        echo -e "${RED}❌ Failed to create data directory. Check manually.${NC}"
        return 1
    fi

    # Reload and restart the service
    echo -e "${BLUE}🔄 Reloading systemd and restarting service...${NC}"
    sudo systemctl daemon-reload
    sudo systemctl start aztec
    if sudo systemctl is-active --quiet aztec; then
        echo -e "${GREEN}✅ Node updated & restarted successfully!"
        echo -e "${YELLOW}📄 Check logs for confirmation: journalctl -fu aztec${NC}"
    else
        echo -e "${RED}❌ Failed to start aztec.service. Check logs with: systemctl status aztec${NC}"
        cat "$AZTEC_SERVICE"
        return 1
    fi
    
    echo -e "${BLUE}Waiting 60 seconds...${NC}"
    # Animated shrinking countdown (replaces sleep 60)
    total=60
    bar_width=30
    tput civis 2>/dev/null || true   # hide cursor if possible
    for ((sec=total; sec>0; sec--)); do
        filled=$(( (sec * bar_width + total - 1) / total ))    # proportionally shrinking
        empty=$(( bar_width - filled ))
        # build bar: filled blocks then dashes for empty
        bar="$(printf '%0.s█' $(seq 1 $filled 2>/dev/null))$(printf '%0.s ' $(seq 1 $empty 2>/dev/null))"
        percent=$(( sec * 100 / total ))
        printf "\r⏳ Remaining: %3ds [%s] %3d%% " "$sec" "$bar" "$percent"
        sleep 1
    done
    printf "\r✅ Done.                                            \n"
    tput cnorm 2>/dev/null || true  # restore cursor
    if sudo systemctl is-active --quiet aztec; then
        payload='{"jsonrpc":"2.0","method":"nodeAdmin_setConfig","params":[{"governanceProposerPayload":"0x9D8869D17Af6B899AFf1d93F23f863FF41ddc4fa"}],"id":1}'

        max_retries=5
        attempt=1
        while [ $attempt -le $max_retries ]; do
            echo -e "${BLUE}📡 Sending JSON-RPC setConfig request to localhost:8880 (attempt $attempt)...${NC}"
            response=$(curl -s -X POST http://127.0.0.1:8880 -H 'Content-Type: application/json' -d "$payload")

            if [ -n "$response" ]; then
                # show the raw response and stop retrying
                echo -e "${GREEN}✅ JSON-RPC response:${NC} $response"
                break
            else
                echo -e "${YELLOW}⚠ No response received, retrying in 5s...${NC}"
                sleep 5
                attempt=$((attempt + 1))
            fi
        done

        if [ $attempt -gt $max_retries ] && [ -z "$response" ]; then
            echo -e "${RED}❌ Failed to contact local admin port after $max_retries attempts.${NC}"
            echo -e "${YELLOW}📄 Check service logs: journalctl -u aztec -n 200 --no-pager${NC}"
            return 1
        fi
    else
        echo -e "${RED}❌ aztec.service is not active; cannot send JSON-RPC request.${NC}"
        return 1
    fi
}

generate_start_command() {
    echo -e "${YELLOW}⚙️ Generating aztec start command from systemd service...${NC}"

    SERVICE_FILE="/etc/systemd/system/aztec.service"

    if [ ! -f "$SERVICE_FILE" ]; then
        echo -e "${RED}❌ Systemd service not found at $SERVICE_FILE. Run install first.${NC}"
        return
    fi

    L1_RPC=$(grep -oP '(?<=--l1-rpc-urls )\S+' "$SERVICE_FILE")
    BEACON_RPC=$(grep -oP '(?<=--l1-consensus-host-urls )\S+' "$SERVICE_FILE")
    PRIVATE_KEY=$(grep -oP '(?<=--sequencer.validatorPrivateKeys )\S+' "$SERVICE_FILE")
    EVM_ADDRESS=$(grep -oP '(?<=--sequencer.coinbase )\S+' "$SERVICE_FILE")
    PUBLIC_IP=$(grep -oP '(?<=--p2p.p2pIp )\S+' "$SERVICE_FILE")

    echo -e "${GREEN}🟢 Use the following command to run manually:${NC}"
    echo ""
    echo -e "${BLUE}aztec start --node --archiver --sequencer \\"
    echo "  --network testnet \\"
    echo "  --l1-rpc-urls $L1_RPC \\"
    echo "  --l1-consensus-host-urls $BEACON_RPC \\"
    echo "  --sequencer.validatorPrivateKeys $PRIVATE_KEY \\"
    echo "  --sequencer.coinbase $EVM_ADDRESS \\"
    echo "  --p2p.p2pIp $PUBLIC_IP \\"
    echo -e "  --admin-port 8880${NC}"
    echo ""
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

show_header() {
    clear
    echo -e "${BLUE}${BOLD}"
    echo "┌───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐"
    echo "│  ██╗░░██╗██╗░░░██╗░██████╗████████╗██╗░░░░░███████╗  ░█████╗░██╗██████╗░██████╗░██████╗░░█████╗░██████╗░░██████╗  │"
    echo "│  ██║░░██║██║░░░██║██╔════╝╚══██╔══╝██║░░░░░██╔════╝  ██╔══██╗██║██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔════╝  │"
    echo "│  ███████║██║░░░██║╚█████╗░░░░██║░░░██║░░░░░█████╗░░  ███████║██║██████╔╝██║░░██║██████╔╝██║░░██║██████╔╝╚█████╗░  │"
    echo "│  ██╔══██║██║░░░██║░╚═══██╗░░░██║░░░██║░░░░░██╔══╝░░  ██╔══██║██║██╔══██╗██║░░██║██╔══██╗██║░░██║██╔═══╝░░╚═══██╗  │"
    echo "│  ██║░░██║╚██████╔╝██████╔╝░░░██║░░░███████╗███████╗  ██║░░██║██║██║░░██║██████╔╝██║░░██║╚█████╔╝██║░░░░░██████╔╝  │"
    echo "│  ╚═╝░░╚═╝░╚═════╝░╚═════╝░░░░╚═╝░░░╚══════╝╚══════╝  ╚═╝░░╚═╝╚═╝╚═╝░░╚═╝╚═════╝░╚═╝░░╚═╝░╚════╝░╚═╝░░░░░╚═════╝░  │"
    echo "└───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘"
    echo -e "${YELLOW}                  🚀 Aztec Node Manager by Aashish 🚀${NC}"
    echo -e "${YELLOW}              GitHub: https://github.com/HustleAirdrops${NC}"
    echo -e "${YELLOW}              Telegram: https://t.me/Hustle_Airdrops${NC}"
    echo -e "${GREEN}===============================================================================${NC}"
}

# ===================== MENU ==========================
while true; do
    clear
    show_header
    echo -e "${BLUE}${BOLD}================ AZTEC NODE MANAGER BY Aashish 💖 =================${NC}"
    echo -e " 1️⃣  Full Install"
    echo -e " 2️⃣  Run Node"
    echo -e " 3️⃣  View Logs"
    echo -e " 4️⃣  Reconfigure RPC"
    echo -e " 5️⃣  Uninstall Node"
    echo -e " 6️⃣  Show Peer ID"
    echo -e " 7️⃣  Update Node"
    echo -e " 8️⃣  Generate Start Command"
    echo -e " 9️⃣  Exit"
    echo -e "${BLUE}============================================================================${NC}"
    read -p "👉 Choose option (1-9): " choice

    case $choice in
        1) install_full ;;
        2) run_node ;;
        3) view_logs ;;
        4) reconfigure ;;
        5) uninstall ;;
        6) show_peer_id ;;
        7) update_node ;;
        8) generate_start_command ;;
        9) echo -e "${GREEN}👋 Exiting... Stay decentralized, Aashish!${NC}"; break ;;
        *) echo -e "${RED}❌ Invalid option. Try again.${NC}"; sleep 1 ;;
    esac

    read -p "🔁 Press Enter to return to menu..."
done
