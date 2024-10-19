#!/bin/bash

# ============================================
# Script for installing and managing the Story node
# Support: support@stake-take.com
# ============================================

# Exit immediately if a command exits with a non-zero status
set -e

# Colors for output messages
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Determine the user's home directory, even when using sudo
if [[ -n "$SUDO_USER" ]]; then
    USER_HOME=$(eval echo "~$SUDO_USER")
    USER_NAME="$SUDO_USER"
else
    USER_HOME="$HOME"
    USER_NAME=$(whoami)
fi

# Variables
GO_VERSION="1.22.8"
GO_TARBALL="go${GO_VERSION}.linux-amd64.tar.gz"
COSMOVISOR_DIR="$USER_HOME/.story/story/cosmovisor"
GO_BIN_DIR="$USER_HOME/go/bin"
SERVICE_DIR="/etc/systemd/system"
PORTS=(26656 26657 1317 8545 8546)
SERVICES=("story-geth.service" "story.service")
BINARY_URLS=(
    "https://github.com/piplabs/story-geth/releases/download/v0.9.4/geth-linux-amd64"
    "https://story-geth-binaries.s3.us-west-1.amazonaws.com/story-public/story-linux-amd64-0.11.0-aac4bfe.tar.gz"
)
ADDRBOOK_URL="https://story.snapshot.stake-take.com/addrbook.json"
STATE_SYNC_RPC="https://story-testnet-rpc.stake-take.com:443"

# Function to print informational messages
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Function to print warning messages
warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Function to print error messages and exit
error_exit() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Function to check if script is run as root
check_sudo() {
    if [[ "$EUID" -ne 0 ]]; then
        error_exit "This script must be run with sudo or as root."
    fi
}

# Function to check if ports are in use
check_ports() {
    info "Checking if required ports are available..."
    for PORT in "${PORTS[@]}"; do
        if lsof -iTCP -sTCP:LISTEN -P | grep -q ":$PORT "; then
            warning "Port $PORT is already in use."
        else
            info "Port $PORT is available."
        fi
    done
}

# Function to check and stop existing services
stop_existing_services() {
    for SERVICE in "${SERVICES[@]}"; do
        if systemctl is-active --quiet "$SERVICE"; then
            warning "Service $SERVICE is already running."
            read -p "Do you want to stop the service $SERVICE? (y/n): " choice
            case "$choice" in
                y|Y )
                    systemctl stop "$SERVICE"
                    info "Service $SERVICE has been stopped."
                    ;;
                * )
                    error_exit "Service $SERVICE must be stopped to proceed."
                    ;;
            esac
        fi
    done
}

# Function to install necessary packages
install_dependencies() {
    info "Installing necessary packages..."
    apt update -qq && apt-get update -qq
    apt install -y -qq curl git make jq build-essential gcc unzip wget lz4 aria2 || error_exit "Failed to install necessary packages."
}

# Function to install Go
install_go() {
    # Check if Go is already installed
    if command -v go &>/dev/null; then
        INSTALLED_GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
        if [[ "$INSTALLED_GO_VERSION" == "$GO_VERSION" ]]; then
            info "Go version $GO_VERSION is already installed."
            return
        else
            warning "Go version $INSTALLED_GO_VERSION is installed. Required version is $GO_VERSION."
            read -p "Do you want to install Go version $GO_VERSION? (y/n): " choice
            case "$choice" in
                y|Y )
                    info "Removing existing Go installation..."
                    rm -rf /usr/local/go
                    rm -rf "$USER_HOME/go"
                    ;;
                * )
                    error_exit "Go version $GO_VERSION is required. Exiting."
                    ;;
            esac
        fi
    fi

    # Download and install Go
    info "Downloading Go version $GO_VERSION..."
    wget -q "https://golang.org/dl/${GO_TARBALL}" -O "/tmp/${GO_TARBALL}" || error_exit "Failed to download Go."

    info "Installing Go version $GO_VERSION..."
    tar -C /usr/local -xzf "/tmp/${GO_TARBALL}" || error_exit "Failed to extract Go."
    rm "/tmp/${GO_TARBALL}"

    # Set up environment variables
    BASH_PROFILE="$USER_HOME/.bash_profile"
    if [[ ! -f "$BASH_PROFILE" ]]; then
        touch "$BASH_PROFILE"
    fi

    if ! grep -q "export PATH=\$PATH:/usr/local/go/bin:$GO_BIN_DIR" "$BASH_PROFILE"; then
        echo "export PATH=\$PATH:/usr/local/go/bin:$GO_BIN_DIR" >> "$BASH_PROFILE"
        # Update current session
        export PATH="$PATH:/usr/local/go/bin:$GO_BIN_DIR"
        info "Updated PATH in $BASH_PROFILE."
    else
        info "PATH is already set in $BASH_PROFILE."
    fi

    # Verify Go installation
    if ! command -v go &>/dev/null; then
        error_exit "Go installation failed. Please check manually."
    fi

    GO_INSTALLED_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
    info "Go version $GO_INSTALLED_VERSION installed successfully."
}

# Function to install Cosmovisor
install_cosmovisor() {
    # Check if Cosmovisor is already installed
    if command -v cosmovisor &>/dev/null; then
        info "Cosmovisor is already installed."
        return
    fi

    info "Installing Cosmovisor..."
    go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@latest || error_exit "Failed to install Cosmovisor."

    # Verify Cosmovisor installation
    if [[ -f "$GO_BIN_DIR/cosmovisor" ]]; then
        chmod +x "$GO_BIN_DIR/cosmovisor"
        info "Cosmovisor installed at $GO_BIN_DIR/cosmovisor."
    else
        error_exit "Cosmovisor not found in $GO_BIN_DIR."
    fi

    # Ensure $GO_BIN_DIR is in PATH
    BASH_PROFILE="$USER_HOME/.bash_profile"
    if ! grep -q "export PATH=\$PATH:$GO_BIN_DIR" "$BASH_PROFILE"; then
        echo "export PATH=\$PATH:$GO_BIN_DIR" >> "$BASH_PROFILE"
        # Update current session
        export PATH="$PATH:$GO_BIN_DIR"
        info "Added $GO_BIN_DIR to PATH in $BASH_PROFILE."
    else
        info "$GO_BIN_DIR is already in PATH."
    fi
}

# Function to download and install binaries
download_and_install_binaries() {
    info "Downloading and installing binaries..."

    # Download and install story-geth
    geth_url="${BINARY_URLS[0]}"
    geth_filename=$(basename "$geth_url")
    info "Downloading story-geth from $geth_url..."
    wget -q --show-progress "$geth_url" -O "/tmp/$geth_filename" || error_exit "Failed to download story-geth."
    chmod +x "/tmp/$geth_filename"
    mv "/tmp/$geth_filename" "$GO_BIN_DIR/story-geth" || error_exit "Failed to move story-geth binary."
    info "story-geth installed successfully."

    # Download and extract story
    story_url="${BINARY_URLS[1]}"
    story_tarball=$(basename "$story_url")
    info "Downloading story from $story_url..."
    wget -q --show-progress "$story_url" -O "/tmp/$story_tarball" || error_exit "Failed to download story."
    info "Extracting $story_tarball..."
    tar -xzvf "/tmp/$story_tarball" -C "/tmp/" || error_exit "Failed to extract $story_tarball."
    story_binary_path=$(find /tmp -type f -name "story" | head -n 1)
    if [[ -z "$story_binary_path" ]]; then
        error_exit "story binary not found after extraction."
    fi
    chmod +x "$story_binary_path"
    mv "$story_binary_path" "$GO_BIN_DIR/story" || error_exit "Failed to move story binary."
    rm "/tmp/$story_tarball"
    rm -rf "/tmp/$(basename "$story_tarball" .tar.gz)"
    info "story installed successfully."
}

# Function to create systemd service files
create_service_files() {
    info "Creating systemd service files..."

    # Story-Geth Service
    sudo tee "$SERVICE_DIR/story-geth.service" > /dev/null <<EOF
[Unit]
Description=Story Geth Client
After=network.target

[Service]
User=$USER_NAME
ExecStart=$GO_BIN_DIR/story-geth --iliad --syncmode full --http --http.api eth,net,web3,engine --http.vhosts '*' --http.addr 0.0.0.0 --http.port 8545 --ws --ws.api eth,web3,net,txpool --ws.addr 0.0.0.0 --ws.port 8546
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

    info "Created service file story-geth.service."

    # Story Service
    sudo tee "$SERVICE_DIR/story.service" > /dev/null <<EOF
[Unit]
Description=Story Consensus Client
After=network.target

[Service]
User=$USER_NAME
Environment="DAEMON_NAME=story"
Environment="DAEMON_HOME=$USER_HOME/.story/story"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=false"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"
Environment="DAEMON_DATA_BACKUP_DIR=$USER_HOME/.story/story/data"
Environment="UNSAFE_SKIP_BACKUP=true"
ExecStart=$GO_BIN_DIR/cosmovisor run run
Restart=always
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

    info "Created service file story.service."
}

# Function to initialize the node
initialize_node() {
    read -p "Enter your node name (MONIKER): " MONIKER

    # Check if DAEMON_HOME exists
    if [[ -d "$USER_HOME/.story/story" ]]; then
        warning "Node is already initialized at $USER_HOME/.story/story."
        read -p "Do you want to re-initialize the node? This will delete existing configurations. (y/n): " choice
        case "$choice" in
            y|Y )
                rm -rf "$USER_HOME/.story/story"
                info "Existing node configurations removed."
                ;;
            * )
                error_exit "Node re-initialization is required to proceed."
                ;;
        esac
    fi

    info "Initializing node with moniker: $MONIKER..."
    sudo -u "$USER_NAME" "$GO_BIN_DIR/story" init --network iliad --moniker "$MONIKER" || error_exit "Failed to initialize the node."

    # Set up Cosmovisor directories and copy binary
    info "Setting up Cosmovisor directories..."
    mkdir -p "$COSMOVISOR_DIR/genesis/bin" || error_exit "Failed to create Cosmovisor directories."
    cp "$GO_BIN_DIR/story" "$COSMOVISOR_DIR/genesis/bin/story" || error_exit "Failed to copy story binary to Cosmovisor."
    chmod +x "$COSMOVISOR_DIR/genesis/bin/story"
    info "Cosmovisor directories set up successfully."
}

# Function to start and enable services
start_services() {
    info "Reloading systemd daemon..."
    systemctl daemon-reload || error_exit "Failed to reload systemd."

    for SERVICE in "${SERVICES[@]}"; do
        info "Starting and enabling service $SERVICE..."
        systemctl start "$SERVICE" || error_exit "Failed to start service $SERVICE."
        systemctl enable "$SERVICE" || error_exit "Failed to enable service $SERVICE."
        if systemctl is-active --quiet "$SERVICE"; then
            info "Service $SERVICE is running."
        else
            error_exit "Service $SERVICE failed to start."
        fi
    done
}

# Function to check node status
check_status() {
    info "Checking node synchronization status..."
    if ! systemctl is-active --quiet "story.service"; then
        warning "Story service is not running."
        read -p "Do you want to start the story service? (y/n): " choice
        case "$choice" in
            y|Y )
                systemctl start story.service
                ;;
            * )
                error_exit "Cannot check status without the service running."
                ;;
        esac
    fi

    STATUS=$(curl -s localhost:26657/status | jq '.result.sync_info' || true)
    if [[ -z "$STATUS" ]]; then
        warning "Failed to retrieve node status. The node might not be fully operational yet."
        info "Please ensure the services are running and try again later."
    else
        echo "$STATUS"
        CATCHING_UP=$(echo "$STATUS" | jq -r '.catching_up')
        if [[ "$CATCHING_UP" == "false" ]]; then
            info "Your node is fully synchronized."
        else
            info "Your node is still synchronizing."
        fi
    fi
}

# Function to download the latest addrbook.json
download_addrbook() {
    info "Downloading the latest addrbook.json..."
    if [[ ! -d "$USER_HOME/.story/story/config" ]]; then
        error_exit "Node configuration directory not found. Please initialize the node first."
    fi

    curl -Ls "$ADDRBOOK_URL" -o "$USER_HOME/.story/story/config/addrbook.json" || error_exit "Failed to download addrbook.json."
    info "addrbook.json has been updated."
}

# Function to install snapshot
install_snapshot() {
    # Check if node is initialized
    if [[ ! -d "$USER_HOME/.story/story" ]]; then
        error_exit "Node is not initialized. Please perform a new installation first."
    fi

    # Install necessary tools
    apt install -y -qq curl tar lz4 || error_exit "Failed to install snapshot dependencies."

    # Stop services before installing snapshot
    info "Stopping node services..."
    systemctl stop story.service || true
    systemctl stop story-geth.service || true

    # Backup priv_validator_state.json
    info "Backing up priv_validator_state.json..."
    cp "$USER_HOME/.story/story/data/priv_validator_state.json" "$USER_HOME/.story/story/priv_validator_state.json.backup" || error_exit "Failed to backup priv_validator_state.json."

    # Remove old data
    info "Removing old node data..."
    rm -rf "$USER_HOME/.story/story/data"
    rm -rf "$USER_HOME/.story/geth/iliad/geth/chaindata"

    # Download and extract snapshots
    info "Downloading and extracting geth snapshot..."
    curl -L https://story.snapshot.stake-take.com/snapshot_geth.tar.lz4 | tar -Ilz4 -xf - -C "$USER_HOME/.story/geth" || error_exit "Failed to extract geth snapshot."

    info "Downloading and extracting consensus snapshot..."
    curl -L https://story.snapshot.stake-take.com/snapshot_consensus.tar.lz4 | tar -Ilz4 -xf - -C "$USER_HOME/.story/story" || error_exit "Failed to extract consensus snapshot."

    # Restore priv_validator_state.json from backup
    info "Restoring priv_validator_state.json from backup..."
    mv "$USER_HOME/.story/story/priv_validator_state.json.backup" "$USER_HOME/.story/story/data/priv_validator_state.json" || error_exit "Failed to restore priv_validator_state.json."

    # Download latest addrbook.json
    download_addrbook

    # Start services
    start_services

    # Check node status
    check_status

    info "Snapshot installation completed successfully."
}

# Function to perform state sync
perform_state_sync() {
    # Check if node is initialized
    if [[ ! -d "$USER_HOME/.story/story" ]]; then
        error_exit "Node is not initialized. Please perform a new installation first."
    fi

    # Stop the service and reset data
    info "Stopping the story service..."
    systemctl stop story.service || true

    info "Backing up priv_validator_state.json..."
    cp "$USER_HOME/.story/story/data/priv_validator_state.json" "$USER_HOME/.story/story/priv_validator_state.json.backup" || error_exit "Failed to backup priv_validator_state.json."

    info "Resetting node data..."
    rm -rf "$USER_HOME/.story/story/data"
    mkdir -p "$USER_HOME/.story/story/data"

    # Get and configure state sync information
    info "Configuring state sync..."

    LATEST_HEIGHT=$(curl -s "$STATE_SYNC_RPC/block" | jq -r .result.block.header.height)
    SYNC_BLOCK_HEIGHT=$(( (LATEST_HEIGHT / 1000) * 1000 ))
    SYNC_BLOCK_HASH=$(curl -s "$STATE_SYNC_RPC/block?height=$SYNC_BLOCK_HEIGHT" | jq -r .result.block_id.hash)

    echo "Latest Height: $LATEST_HEIGHT"
    echo "Sync Block Height: $SYNC_BLOCK_HEIGHT"
    echo "Sync Block Hash: $SYNC_BLOCK_HASH"

    CONFIG_TOML="$USER_HOME/.story/story/config/config.toml"

    sed -i.bak -e "s|^enable *=.*|enable = true|" \
        -e "s|^rpc_servers *=.*|rpc_servers = \"$STATE_SYNC_RPC,$STATE_SYNC_RPC\"|" \
        -e "s|^trust_height *=.*|trust_height = $SYNC_BLOCK_HEIGHT|" \
        -e "s|^trust_hash *=.*|trust_hash = \"$SYNC_BLOCK_HASH\"|" \
        -e "s|^persistent_peers *=.*|persistent_peers = \"\"|" \
        "$CONFIG_TOML"

    # Restore priv_validator_state.json from backup
    info "Restoring priv_validator_state.json from backup..."
    mv "$USER_HOME/.story/story/priv_validator_state.json.backup" "$USER_HOME/.story/story/data/priv_validator_state.json" || error_exit "Failed to restore priv_validator_state.json."

    # Download latest addrbook.json
    download_addrbook

    # Start the service
    info "Starting the story service..."
    systemctl start story.service

    # Monitor the logs
    info "You can monitor the node logs using:"
    echo "sudo journalctl -fu story.service -o cat"

    info "State sync initiated. It may take some time to complete."
}

# Function to create validator
create_validator() {
    info "Creating a validator..."

    # Ensure node is fully synchronized
    STATUS=$(curl -s localhost:26657/status | jq '.result.sync_info.catching_up' || true)
    if [[ "$STATUS" != "false" ]]; then
        error_exit "Node is not fully synchronized. Please wait until synchronization is complete."
    fi

    # Export validator account and save data
    info "Exporting validator account..."
    sudo -u "$USER_NAME" "$GO_BIN_DIR/story" validator export || error_exit "Failed to export validator account."

    # Extract private key
    info "Extracting validator private key..."
    PRIV_KEY=$(sudo cat "$USER_HOME/.story/story/config/private_key.txt") || error_exit "Failed to read private_key.txt."
    echo "Your validator private key is:"
    echo "$PRIV_KEY"
    info "Please securely save this private key."

    # Export EVM key
    info "Exporting EVM private key..."
    EVM_PRIV_KEY=$(sudo -u "$USER_NAME" "$GO_BIN_DIR/story" validator export --export-evm-key | grep -oP '0x\K[0-9a-fA-F]+') || error_exit "Failed to export EVM private key."
    echo "Your EVM private key is:"
    echo "$EVM_PRIV_KEY"
    info "Please securely save this EVM private key and import it into your EVM wallet."

    # Request test tokens from faucet
    info "Please request test tokens ($IP) from the faucet using your EVM address."

    # Stake tokens to create validator
    read -p "Enter the amount to stake in wei (e.g., 1000000000000000000 for 1 $IP): " STAKE_AMOUNT
    info "Creating validator with a stake of $STAKE_AMOUNT wei..."

    sudo -u "$USER_NAME" "$GO_BIN_DIR/story" validator create --stake "$STAKE_AMOUNT" --private-key "$EVM_PRIV_KEY" || error_exit "Failed to create validator."

    # Extract priv_validator_key.json
    info "Saving priv_validator_key.json..."
    sudo cat "$USER_HOME/.story/story/config/priv_validator_key.json" > "$USER_HOME/priv_validator_key.json"
    info "Please securely save priv_validator_key.json."

    info "Validator created successfully."
}

# Function to completely remove the node
remove_node() {
    read -p "Are you sure you want to completely remove the Story node? This will delete all data and configurations. (y/n): " choice
    case "$choice" in
        y|Y )
            ;;
        * )
            info "Node removal canceled."
            return
            ;;
    esac

    # Stop and disable services
    for SERVICE in "${SERVICES[@]}"; do
        if systemctl is-active --quiet "$SERVICE"; then
            info "Stopping service $SERVICE..."
            systemctl stop "$SERVICE" || warning "Failed to stop service $SERVICE."
        fi
        if systemctl is-enabled --quiet "$SERVICE"; then
            info "Disabling service $SERVICE..."
            systemctl disable "$SERVICE" || warning "Failed to disable service $SERVICE."
        fi
        # Remove service files
        if [[ -f "$SERVICE_DIR/$SERVICE" ]]; then
            info "Removing service file $SERVICE..."
            rm -f "$SERVICE_DIR/$SERVICE" || warning "Failed to remove $SERVICE."
        fi
    done

    # Reload systemd daemon
    info "Reloading systemd daemon..."
    systemctl daemon-reload || warning "Failed to reload systemd."

    # Remove binaries
    BINARY_PATHS=("$GO_BIN_DIR/story-geth" "$GO_BIN_DIR/story" "$GO_BIN_DIR/cosmovisor")
    for BINARY in "${BINARY_PATHS[@]}"; do
        if [[ -f "$BINARY" ]]; then
            info "Removing binary file $BINARY..."
            rm -f "$BINARY" || warning "Failed to remove $BINARY."
        fi
    done

    # Remove node directories
    info "Removing node directories..."
    rm -rf "$USER_HOME/.story" || warning "Failed to remove $USER_HOME/.story."

    # Optionally remove Go
    read -p "Do you want to remove the Go installation? (y/n): " remove_go
    case "$remove_go" in
        y|Y )
            info "Removing Go..."
            rm -rf /usr/local/go "$USER_HOME/go" || warning "Failed to remove Go."
            ;;
        * )
            info "Go installation preserved."
            ;;
    esac

    info "Story node has been completely removed."
}

# Function to view logs
view_logs() {
    echo "Select the service logs you want to view:"
    echo "1) story"
    echo "2) story-geth"
    read -p "Enter your choice [1-2]: " log_choice
    case "$log_choice" in
        1)
            if systemctl is-active --quiet "story.service"; then
                info "Displaying logs for story service. Press Ctrl+C to exit."
                journalctl -u story.service -f -o cat
            else
                warning "story service is not running."
            fi
            ;;
        2)
            if systemctl is-active --quiet "story-geth.service"; then
                info "Displaying logs for story-geth service. Press Ctrl+C to exit."
                journalctl -u story-geth.service -f -o cat
            else
                warning "story-geth service is not running."
            fi
            ;;
        *)
            warning "Invalid choice. Returning to main menu."
            ;;
    esac
}

# Function to display the menu
show_menu() {
    echo "========================================="
    echo "      Story Node Installation and Management Menu      "
    echo "========================================="
    echo "1) New installation of Story node"
    echo "2) Install snapshot"
    echo "3) Perform state sync"
    echo "4) Download latest addrbook"
    echo "5) Check node synchronization status"
    echo "6) Create validator"
    echo "7) View service logs"
    echo "8) Completely remove Story node"
    echo "9) Exit"
}

# Function to execute user's choice
execute_choice() {
    case "$1" in
        1)
            # New installation
            check_ports
            stop_existing_services
            read -p "Do you want to proceed with a new installation? (y/n): " proceed
            case "$proceed" in
                y|Y )
                    install_dependencies
                    install_go
                    install_cosmovisor
                    # Download and install binaries
                    download_and_install_binaries
                    # Initialize node
                    initialize_node
                    # Create service files
                    create_service_files
                    # Download latest addrbook
                    download_addrbook
                    # Start and enable services
                    start_services
                    # Inform user about synchronization options
                    info "New installation of Story node completed successfully."
                    info "To speed up synchronization, consider using the snapshot or state sync options from the menu."
                    ;;
                * )
                    info "New installation canceled."
                    ;;
            esac
            ;;
        2)
            # Install snapshot
            read -p "Do you want to install a snapshot? This can speed up synchronization. (y/n): " proceed
            case "$proceed" in
                y|Y )
                    install_snapshot
                    ;;
                * )
                    info "Snapshot installation canceled."
                    ;;
            esac
            ;;
        3)
            # Perform state sync
            read -p "Do you want to perform state sync? This can speed up synchronization. (y/n): " proceed
            case "$proceed" in
                y|Y )
                    perform_state_sync
                    ;;
                * )
                    info "State sync canceled."
                    ;;
            esac
            ;;
        4)
            # Download latest addrbook
            download_addrbook
            ;;
        5)
            # Check node synchronization status
            check_status
            ;;
        6)
            # Create validator
            create_validator
            ;;
        7)
            # View service logs
            view_logs
            ;;
        8)
            # Completely remove node
            remove_node
            ;;
        9)
            # Exit
            info "Exiting the script. Goodbye!"
            exit 0
            ;;
        *)
            # Invalid choice
            warning "Invalid choice. Please enter a number from 1 to 9."
            ;;
    esac
}

# Main function
main() {
    check_sudo

    while true; do
        show_menu
        read -p "Enter your choice [1-9]: " CHOICE
        execute_choice "$CHOICE"
        echo
    done
}

# Run the main function
main
