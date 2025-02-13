#!/bin/bash
set -e

# Variables
LUCENIA_VERSION="0.3.0"
LUCENIA_HOME="$HOME/.lucenia"
LUCENIA_INITIAL_ADMIN_PASSWORD="myStrongPassword@123"
LUCENIA_SEC_TOOLS="$LUCENIA_HOME/lucenia-$LUCENIA_VERSION/plugins/lucenia-security/tools"
LUCENIA_CONF="$LUCENIA_HOME/lucenia-$LUCENIA_VERSION/config"
LUCENIA_SEC_CONF="$LUCENIA_CONF/lucenia-security"
PLATFORM="linux"
ARCH="arm64"
FILENAME="lucenia-$LUCENIA_VERSION-$PLATFORM-$ARCH.tar.gz"
DOWNLOAD_URL="https://lucenia-resources.nyc3.cdn.digitaloceanspaces.com/artifact/$FILENAME"
CHECKSUM_URL="https://lucenia-resources.nyc3.cdn.digitaloceanspaces.com/artifact/$FILENAME.sha256"
LICENSE_API="https://cloud.lucenia.io/check/v1/license/developer/cli"

# Setup logging
log() {
    echo "[LUCENIA INSTALL] $1"
}

check_if_java_installed() {
    log "Checking if Java is installed..."
    if ! command -v java &> /dev/null; then
        log "Java is not installed. Please install Java 11 or later."
        exit 1
    fi
}

# Create Lucenia home directory
setup_directories() {
    log "Creating Lucenia home directory..."
    mkdir -p "$LUCENIA_HOME"
}

# Download and verify
download_and_verify() {
    uname=$(uname)
    userid=$(id -u)

    suffix=""
    case $uname in
    "Darwin")
        arch=$(uname -m)
        case $arch in
        "x86_64")
        suffix="-darwin"
        ;;
        esac
        case $arch in
        "arm64")
        suffix="-darwin-arm64"
        ;;
        esac
    ;;

    "Linux")
        arch=$(uname -m)
        echo $arch
        case $arch in
        "aarch64")
        suffix="-arm64"
        ;;
        esac
        case $arch in
        "armv6l" | "armv7l")
        suffix="-armhf"
        ;;
        esac
    ;;
    esac

    # local temp_dir=$(mktemp -d)
    local temp_dir="$LUCENIA_HOME/tmp_lucenia"
    # make temp directory if it doesn't exist
    if [ ! -d "$temp_dir" ]; then
        mkdir -p "$temp_dir"
    fi

    # Check if lucenia.tar.gz already exists
    if [ -f "$temp_dir/$FILENAME" ]; then
        log "Lucenia already downloaded to $temp_dir. Skipping download..."
        return
    else
      log "Downloading $DOWNLOAD_URL Lucenia..."
      log "into $temp_dir"
      curl -sSL "$DOWNLOAD_URL" --output "$temp_dir/$FILENAME"
      ls "$temp_dir"
      curl -sSL "$CHECKSUM_URL" --output "$temp_dir/$FILENAME.sha256"
      
      log "Verifying checksum..."
      cd "$temp_dir"
      sha256sum -c "$FILENAME.sha256"
      cd ..

      log "Extracting files..."
      tar xzf "$temp_dir/$FILENAME" -C "$LUCENIA_HOME"
    fi
    log "Lucenia downloaded and verified!"
}

# Get trial license
get_trial_license() {
    # check if trial license already exists in config
    if [ -f "$LUCENIA_HOME/lucenia-$LUCENIA_VERSION/config/trial.crt" ]; then
        log "Trial license already exists. Skipping license request."
        return
    fi


    log "Please enter your email address for trial license:"
    read -r email < /dev/tty
    log "Please enter your name for your dev license:"
    read -r licensee < /dev/tty
    
    log "Requesting trial license for $email..."
    license_response=$(curl -sSL -X POST \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"$email\",\"licensee\":\"$licensee\"}" \
        "$LICENSE_API")

    # Check if license response contains "License already exists"
    if [[ "$license_response" == *"License already exists"* ]]; then
        log "License already exists for $email. Skipping license request."
        log "Please check your email for the license and put it in $LUCENIA_HOME/lucenia-$LUCENIA_VERSION/config/trial.crt"
        return
    fi
    
    echo "$license_response" > "$LUCENIA_HOME/lucenia-$LUCENIA_VERSION/config/trial.crt"
    log "License saved to $LUCENIA_HOME/lucenia-$LUCENIA_VERSION/config/trial.crt"
}

setup_demo_config() {
    export LUCENIA_INITIAL_ADMIN_PASSWORD="$LUCENIA_INITIAL_ADMIN_PASSWORD"
    bash $LUCENIA_HOME/lucenia-$LUCENIA_VERSION/plugins/lucenia-security/tools/install_demo_configuration.sh -y
    chmod a+x "$LUCENIA_HOME/lucenia-$LUCENIA_VERSION/config/securityadmin_demo.sh"
    chmod a+x "$LUCENIA_HOME/lucenia-$LUCENIA_VERSION/plugins/lucenia-security/tools/securityadmin.sh"
}

# Start Lucenia
start_lucenia() {
    log "Starting Lucenia in background..."
    # Start Lucenia in background
    $LUCENIA_HOME/lucenia-$LUCENIA_VERSION/bin/lucenia -p \
        $LUCENIA_HOME/lucenia-$LUCENIA_VERSION/lucenia.pid -q &
    log "Lucenia started successfully!"
}

check_lucenia_health() {
    log "Checking Lucenia health..."
    sleep 10
    curl -sSL "https://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=50s" -ku "admin:$LUCENIA_INITIAL_ADMIN_PASSWORD"
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
cluster.name: "lucenia-cluster"
node.name: "lucenia-cluster"
network.host: "0.0.0.0"
http.port: 9200
discovery.type: single-node
bootstrap.memory_lock: true
plugins.license.certificate_filepath: "$LUCENIA_HOME/lucenia-$LUCENIA_VERSION/config/trial.crt"
EOF
}

# Main installation flow
main() {
    log "Starting Lucenia installation..."
    setup_directories
    check_if_java_installed
    download_and_verify
    get_trial_license
    write_lucenia_config
    setup_demo_config
    start_lucenia
    check_lucenia_health
    run_security_admin
    log "Installation complete! Lucenia is now running."
    log 'To stop  you can issue the command `kill -9 $(cat '$LUCENIA_HOME'/lucenia-'$LUCENIA_VERSION'/lucenia.pid)`'
    log 'Username: admin Password: '$LUCENIA_INITIAL_ADMIN_PASSWORD
    log 'You can now run `curl -u admin:'$LUCENIA_INITIAL_ADMIN_PASSWORD' -k https://localhost:9200/_cluster/health` to check the health of Lucenia'
}

# Execute main function
main
