#!/bin/bash
set -e

# Cleanup function
cleanup() {
    if [ ! -z "$MONITOR_PID" ]; then
        kill $MONITOR_PID 2>/dev/null || true
    fi
    if [ -f "$LICENSE_EXPIRED_FLAG" ]; then
        rm -f "$LICENSE_EXPIRED_FLAG"
    fi
}

# Set up trap for cleanup on exit
trap cleanup EXIT

# Monitor process PID (global for cleanup)
MONITOR_PID=""
# Lucenia version defaults to 0.7.0 unless specified by environment variable
LUCENIA_VERSION="${LUCENIA_VERSION:-0.7.0}"
LUCENIA_HOME="$HOME/.lucenia"
LUCENIA_INITIAL_ADMIN_PASSWORD="myStrongPassword@123"
LUCENIA_SEC_TOOLS="$LUCENIA_HOME/lucenia-$LUCENIA_VERSION/plugins/lucenia-security/tools"
LUCENIA_CONF="$LUCENIA_HOME/lucenia-$LUCENIA_VERSION/config"
LUCENIA_SEC_CONF="$LUCENIA_CONF/lucenia-security"

# Detect platform and architecture
UNAME=$(uname)
ARCH=$(uname -m)
case $UNAME in
"Darwin")
    PLATFORM="darwin"
    case $ARCH in
    "arm64")
        ARCH="arm64"
        ;;
    "x86_64")
        ARCH="x64"
        ;;
    esac
    ;;
"Linux")
    PLATFORM="linux"
    case $ARCH in
    "aarch64")
        ARCH="arm64"
        ;;
    "x86_64")
        ARCH="x64"
        ;;
    "armv6l"|"armv7l")
        ARCH="armhf"
        ;;
    esac
    ;;
esac
FILENAME="lucenia-$LUCENIA_VERSION-linux-$ARCH.tar.gz"
DOWNLOAD_URL="https://s3.us-east-2.amazonaws.com/artifacts.lucenia.io/releases/lucenia/$LUCENIA_VERSION/$FILENAME"
CHECKSUM_URL="https://s3.us-east-2.amazonaws.com/artifacts.lucenia.io/releases/lucenia/$LUCENIA_VERSION/$FILENAME.sig"
LICENSE_API="https://cloud.lucenia.io/check/v1/license/developer/cli"
TEMP_DIR="$LUCENIA_HOME/tmp_lucenia"
LICENSE_EXPIRED_FLAG="$TEMP_DIR/license_expired"
# OpenSearch Dashboards variables
DASHBOARDS_VERSION="2.14.0"
DASHBOARDS_FILENAME="opensearch-dashboards-$DASHBOARDS_VERSION-$PLATFORM-x64.tar.gz"
DASHBOARDS_ARM64_FILENAME="opensearch-dashboards-$DASHBOARDS_VERSION-$PLATFORM-arm64.tar.gz"
DASHBOARDS_DOWNLOAD_URL="https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/$DASHBOARDS_VERSION/$DASHBOARDS_FILENAME"
DASHBOARDS_ARM64_DOWNLOAD_URL="https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/$DASHBOARDS_VERSION/$DASHBOARDS_ARM64_FILENAME"
DASHBOARDS_HOME="$LUCENIA_HOME/opensearch-dashboards-$DASHBOARDS_VERSION"
DASHBOARDS_CONF="$DASHBOARDS_HOME/config"
# ENV Vars default if not set
# User's email
# INPUT_EMAIL="${INPUT_EMAIL:-}"
# INPUT_FULLNAME="${INPUT_FULLNAME:-}"
# Cluster and admin configuration
CLUSTER_NAME="${CLUSTER_NAME:-}"
ADMIN_USERNAME="${ADMIN_USERNAME:-}"
DASHBOARDS_PORT="5601"

# Setup logging
log() {
    echo "[LUCENIA INSTALL] $1"
}

# Welcome message and user input collection
welcome_and_collect_info() {
    echo "=========================================="
    echo "Welcome to Lucenia - The easiest search and retrieval engine to onboard"
    echo "=========================================="
    echo
    
    # Skip email/name collection if trial license already exists
    if [ -f "$LUCENIA_HOME/trial.crt" ]; then
        log "Trial license found. Skipping email and name collection."
    else
        # Collect email
        if [ -z "$INPUT_EMAIL" ]; then
            echo "Please enter your email address for the trial license:"
            read -r INPUT_EMAIL < /dev/tty
        fi
        
        # Collect full name
        if [ -z "$INPUT_FULLNAME" ]; then
            echo "Please enter your full name:"
            read -r INPUT_FULLNAME < /dev/tty
        fi
    fi
    
    # Collect cluster name
    if [ -z "$CLUSTER_NAME" ]; then
        echo "Please enter a cluster name (default: lucenia-cluster):"
        read -r cluster_input < /dev/tty
        CLUSTER_NAME="${cluster_input:-lucenia-cluster}"
    fi
    
    # Collect admin username
    if [ -z "$ADMIN_USERNAME" ]; then
        echo "Please enter admin username (default: admin):"
        read -r admin_input < /dev/tty
        ADMIN_USERNAME="${admin_input:-admin}"
    fi
    
    echo
    log "Configuration:"
    log "  Email: $INPUT_EMAIL"
    log "  Name: $INPUT_FULLNAME"
    log "  Cluster: $CLUSTER_NAME"
    log "  Admin: $ADMIN_USERNAME"
    echo
}

check_if_java_installed() {
    log "Checking if Java is installed..."
    if ! command -v java &> /dev/null; then
        log "Java is not installed. Please install Java 11 or later."
        exit 1
    fi
}

check_if_node_installed() {
    log "Checking if Node.js is installed..."
    if ! command -v node &> /dev/null; then
        log "Node.js is not installed. Please install node to use OpenSearch Dashboards."
        exit 1
    fi
}


# Create Lucenia home directory
setup_directories() {
    # default is ~/.lucenia
    log "Creating Lucenia home directory..."
    mkdir -p "$LUCENIA_HOME"
}

check_port_9200_is_used() {
    log "Checking if port 9200 is used..."
    if nc -z localhost 9200; then
        log "Port 9200 is used. Please stop the service using port 9200 and try again."
        log "Or run \`sudo lsof -i :9200\` to find the process using port 9200"
        exit 1
    fi
}

# Download and verify
download_and_verify() {

    # make temp directory if it doesn't exist
    if [ ! -d "$TEMP_DIR" ]; then
        mkdir -p "$TEMP_DIR"
    fi

    # Check if lucenia.tar.gz already exists
    if [ -f "$TEMP_DIR/$FILENAME" ]; then
        log "Lucenia already downloaded to $TEMP_DIR. Skipping download..."
        return
    else
      log "Downloading $DOWNLOAD_URL Lucenia..."
      log "into $TEMP_DIR"
      curl --progress-bar -L "$DOWNLOAD_URL" --output "$TEMP_DIR/$FILENAME"
      ls "$TEMP_DIR"
      curl --progress-bar -L "$CHECKSUM_URL" --output "$TEMP_DIR/$FILENAME.sig"

    #   log "Verifying checksum..."
    #   cd "$TEMP_DIR"
    #   sha256sum -c "$FILENAME.sig"
    #   cd ..

      log "Extracting files..."
      tar xzf "$TEMP_DIR/$FILENAME" -C "$LUCENIA_HOME"
    fi
    log "Lucenia downloaded and verified!"
}

extract_files() {
    # Check if folder $LUCENIA_HOME/lucenia-$LUCENIA_VERSION already exists
    if [ -d "$LUCENIA_HOME/lucenia-$LUCENIA_VERSION" ]; then
        log "Lucenia already extracted to $LUCENIA_HOME. Skipping extraction..."
        return
    else # Extract files
        log "Extracting $TEMP_DIR/$FILENAME to $LUCENIA_HOME..."
        tar xzf "$TEMP_DIR/$FILENAME" -C "$LUCENIA_HOME"
    fi
    log "Lucenia $LUCENIA_VERSION extracted to $LUCENIA_HOME!"

}

# Download and extract OpenSearch Dashboards
download_and_extract_dashboards() {
    # OpenSearch Dashboards uses linux builds for all platforms (including macOS)
    if [ "$ARCH" = "arm64" ]; then
        DASHBOARDS_ACTUAL_FILENAME="opensearch-dashboards-$DASHBOARDS_VERSION-linux-arm64.tar.gz"
        DASHBOARDS_ACTUAL_URL="https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/$DASHBOARDS_VERSION/$DASHBOARDS_ACTUAL_FILENAME"
    else
        DASHBOARDS_ACTUAL_FILENAME="opensearch-dashboards-$DASHBOARDS_VERSION-linux-x64.tar.gz"
        DASHBOARDS_ACTUAL_URL="https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/$DASHBOARDS_VERSION/$DASHBOARDS_ACTUAL_FILENAME"
    fi
    
    # Check if dashboards already downloaded
    if [ -f "$TEMP_DIR/$DASHBOARDS_ACTUAL_FILENAME" ]; then
        log "OpenSearch Dashboards already downloaded. Skipping download..."
    else
        log "Downloading OpenSearch Dashboards $DASHBOARDS_VERSION..."
        curl --progress-bar -L "$DASHBOARDS_ACTUAL_URL" --output "$TEMP_DIR/$DASHBOARDS_ACTUAL_FILENAME"
    fi
    
    # Check if dashboards already extracted
    if [ -d "$DASHBOARDS_HOME" ]; then
        log "OpenSearch Dashboards already extracted. Skipping extraction..."
    else
        log "Extracting OpenSearch Dashboards..."
        tar xzf "$TEMP_DIR/$DASHBOARDS_ACTUAL_FILENAME" -C "$LUCENIA_HOME"
    fi
    
    log "OpenSearch Dashboards $DASHBOARDS_VERSION ready!"
}

# Get trial license
get_trial_license() {
    # check if trial license already exists in config
    if [ -f "$LUCENIA_HOME/trial.crt" ]; then
        log "Trial license already exists. Skipping license request."
        return
    fi

    log "Requesting trial license for $INPUT_EMAIL..."
    license_response=$(curl -sSL -X POST \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$INPUT_EMAIL\",\"licensee\":\"$INPUT_FULLNAME\"}" \
        "$LICENSE_API")

    # Check if license response contains "License already exists"
    if [[ "$license_response" == *"License already exists"* ]]; then
        log "License already exists for $INPUT_EMAIL. Skipping license request."
        log "Please check your email for the license and put it in $LUCENIA_HOME/trial.crt and then run again."
        # Exit script
        exit 1
    fi
    
    echo "$license_response" > "$LUCENIA_HOME/trial.crt"
    log "License saved to $LUCENIA_HOME/trial.crt"
}

setup_demo_config() {
    log "Setting up demo configuration..."
    export LUCENIA_INITIAL_ADMIN_PASSWORD="$LUCENIA_INITIAL_ADMIN_PASSWORD"
    bash $LUCENIA_HOME/lucenia-$LUCENIA_VERSION/plugins/lucenia-security/tools/install_demo_configuration.sh -y
    chmod a+x "$LUCENIA_HOME/lucenia-$LUCENIA_VERSION/config/securityadmin_demo.sh"
    chmod a+x "$LUCENIA_HOME/lucenia-$LUCENIA_VERSION/plugins/lucenia-security/tools/securityadmin.sh"
}

# Monitor Lucenia logs for license expiration
monitor_lucenia_logs() {
    local log_file="$LUCENIA_HOME/lucenia-$LUCENIA_VERSION/logs/lucenia-cluster.log"
    local pid_file="$LUCENIA_HOME/lucenia-$LUCENIA_VERSION/lucenia.pid"
    
    while true; do
        if [ -f "$log_file" ]; then
            if grep -q "License is expired" "$log_file"; then
                # Create flag file to signal license expiration
                touch "$LICENSE_EXPIRED_FLAG"
                log "ERROR: License expired detected. Shutting down Lucenia..."
                if [ -f "$pid_file" ]; then
                    kill -9 $(cat "$pid_file") 2>/dev/null || true
                fi
                return
            fi
        fi
        sleep 5
    done
}

# Start Lucenia
start_lucenia() {
    log "Starting Lucenia in background..."
    # Start Lucenia in background
    $LUCENIA_HOME/lucenia-$LUCENIA_VERSION/bin/lucenia -p \
        $LUCENIA_HOME/lucenia-$LUCENIA_VERSION/lucenia.pid -q &
    
    # Start monitoring logs in background
    monitor_lucenia_logs &
    MONITOR_PID=$!
    
    sleep 10
    # Wait for port 9200 to bind
    log "Checking for lucenia to bind to port 9200"
    while ! nc -z localhost 9200; do
        # Check if license expired flag exists
        if [ -f "$LICENSE_EXPIRED_FLAG" ]; then
            log "Lucenia has been shut down due to expired license."
            log "Please contact Lucenia support to renew your license."
            exit 1
        fi
        log "Waiting for Lucenia to start to 9200..."
        sleep 5
    done
    log "Lucenia started successfully!"
}

check_lucenia_health() {
    log "Checking Lucenia health..."
    # Wait for Lucenia to start catch if it fails
    sleep 5
    while ! curl -k -u admin:$LUCENIA_INITIAL_ADMIN_PASSWORD https://localhost:9200/_cluster/health | grep -q '"status"'; do
        log "Waiting for Lucenia to start..."
        sleep 5
    done
    log "Lucenia is healthy!"
}

run_security_admin() {
   log "Running security admin..."
   bash "$LUCENIA_SEC_TOOLS/securityadmin.sh" \
    -cacert "$LUCENIA_CONF/root-ca.pem" \
    -cert "$LUCENIA_CONF/kirk.pem" \
    -key "$LUCENIA_CONF/kirk-key.pem" \
    -cd "$LUCENIA_SEC_CONF" \
    -nhnv -icl \
    -h 127.0.0.1
   log "Security Admin ran successfully!"
}

write_lucenia_config() {
    log "Writing Lucenia configuration..."
    cat <<EOF > "$LUCENIA_CONF/lucenia.yml"
cluster.name: "$CLUSTER_NAME"
node.name: "$CLUSTER_NAME-node-1"
network.host: "0.0.0.0"
http.port: 9200
discovery.type: single-node
bootstrap.memory_lock: true
plugins.license.certificate_filepath: "$LUCENIA_CONF/trial.crt"
EOF
}

copy_cert_to_config() {
    log "Copying trial license to config..."
    # Copy config if exists to config directory
    if [ -f "$LUCENIA_HOME/trial.crt" ]; then
        cp "$LUCENIA_HOME/trial.crt" "$LUCENIA_CONF/trial.crt"
    fi
}

configure_dashboards() {
    log "Configuring OpenSearch Dashboards..."
    
    # Create dashboards configuration
    cat <<EOF > "$DASHBOARDS_CONF/opensearch_dashboards.yml"
server.port: $DASHBOARDS_PORT
server.host: "0.0.0.0"
opensearch.hosts: ["https://localhost:9200"]
opensearch.ignoreVersionMismatch: true
opensearch.ssl.verificationMode: none
opensearch.username: "$ADMIN_USERNAME"
opensearch.password: "$LUCENIA_INITIAL_ADMIN_PASSWORD"
opensearch.requestHeadersAllowlist: ["securitytenant","Authorization"]
opensearch_security.multitenancy.enabled: true
opensearch_security.multitenancy.tenants.preferred: ["Private", "Global"]
opensearch_security.readonly_mode.roles: ["kibana_read_only"]
opensearch_security.cookie.secure: false
EOF
    
    log "OpenSearch Dashboards configured to connect to Lucenia"
}

check_dashboards_needed() {
    log "Checking if OpenSearch Dashboards is needed..."
    # Check if port 5601 is already in use (dashboards running)
    if nc -z localhost $DASHBOARDS_PORT; then
        log "OpenSearch Dashboards already running on port $DASHBOARDS_PORT"
        return 1
    fi
    return 0
}

start_dashboards() {
    if check_dashboards_needed; then
        log "Starting OpenSearch Dashboards..."
        
        # Start dashboards in background using system Node.js
        cd "$DASHBOARDS_HOME"
        # Replace bundled Node.js with system Node.js if on macOS
        if [ "$PLATFORM" = "darwin" ] && [ -f "node/fallback/bin/node" ]; then
            log "Replacing bundled Node.js with system Node.js for macOS compatibility..."
            rm -f node/fallback/bin/node
            ln -s "$(which node)" node/fallback/bin/node
        fi
        # Start OpenSearch Dashboards
        nohup ./bin/opensearch-dashboards > "$LUCENIA_HOME/dashboards.log" 2>&1 &
        
        # Wait for dashboards to start
        log "Waiting for OpenSearch Dashboards to start..."
        sleep 10
        
        # Check if dashboards started successfully
        local timeout=60
        local counter=0
        while ! nc -z localhost $DASHBOARDS_PORT && [ $counter -lt $timeout ]; do
            log "Waiting for OpenSearch Dashboards to bind to port $DASHBOARDS_PORT..."
            sleep 5
            counter=$((counter + 5))
        done
        
        if nc -z localhost $DASHBOARDS_PORT; then
            log "OpenSearch Dashboards started successfully!"
        else
            log "Warning: OpenSearch Dashboards may not have started properly. Check $LUCENIA_HOME/dashboards.log for details."
        fi
    fi
}

get_node_id() {
    # Get the node ID from the cluster stats
    node_id=$(curl -s -k -u $ADMIN_USERNAME:$LUCENIA_INITIAL_ADMIN_PASSWORD \
        "https://localhost:9200/_nodes/_local" | \
        grep -o '"transport_address":"[^"]*"' | \
        head -1 | \
        sed 's/"transport_address":"//;s/"//')
    if [ -z "$node_id" ]; then
        node_id="localhost:9200"
    fi
    echo "$node_id"
}

# Main installation flow
main() {
    welcome_and_collect_info
    setup_directories
    check_if_java_installed
    check_if_node_installed
    download_and_verify
    extract_files
    download_and_extract_dashboards
    get_trial_license
    write_lucenia_config
    copy_cert_to_config
    setup_demo_config
    configure_dashboards
    check_port_9200_is_used
    start_lucenia
    run_security_admin
    check_lucenia_health
    start_dashboards
    
    # Get node information for success message
    node_id=$(get_node_id)
    
    echo
    echo "=========================================="
    echo "SUCCESS! Lucenia is now running!"
    echo "=========================================="
    echo
    echo "Node ($node_id) has joined Cluster ($CLUSTER_NAME)."
    echo
    echo "Access your instances:"
    echo "  • OpenSearch Dashboards: http://localhost:$DASHBOARDS_PORT"
    echo "  • Lucenia API: https://localhost:9200"
    echo
    echo "Credentials:"
    echo "  • Username: $ADMIN_USERNAME"
    echo "  • Password: $LUCENIA_INITIAL_ADMIN_PASSWORD"
    echo
    echo "For API documentation see: https://docs.lucenia.io"
    echo
    echo "To stop Lucenia:"
    echo "  kill -9 \$(cat $LUCENIA_HOME/lucenia-$LUCENIA_VERSION/lucenia.pid)"
}

# Execute main function
main
