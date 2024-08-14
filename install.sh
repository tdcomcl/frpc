#!/usr/bin/env bash

# Set the version of FRP, but you can override this with -v or --version
FRPC_VERSION="0.59.0"  # https://github.com/fatedier/frp/releases/

# Exit on error
set -e

# Function to display the banner
banner() {
    echo "############################################################"
    echo "#                                                          #"
    echo "#                      IGROMI Installer                    #"
    echo "#                                                          #"
    echo "############################################################"
    echo
}

# Install Packages
install_packages() {
    # if we received packages to install, install them
    if [ $# -eq 0 ]; then 
        echo "* No packages requested to install"
    else
        # Local variable to hold our packages
        local packages
        # Loop through our passed packages
        while [ $# -gt 0 ]; do
            # Check if the command exists, if not flag it for installation
            if [ -x "$(command -v "${1}")" ]; then
                echo "* ${1} is already installed"
            else
                echo "* ${1} will be installed"
                packages="${packages} ${1}"
            fi
            # Shift to the next package
            shift
        done
        # Check if we have any packages to install
        if [ -z "${packages}" ]; then
            echo "* All requested packages are already installed"
            return 0
        else
            echo "* Installing ${packages:1}"
            apt update
            apt install -y ${packages}
        fi
    fi
}

# Functions
frpc_system() {
    # Link to our hosted frpc.service (since it was removed from the release)
    FRPC_SERVICE_URL="https://raw.githubusercontent.com/tdcomcl/frpc/main/frpc.service"

    # Install our required packages
    install_packages curl

    # Download our specified FRP Version
    FRPC_FILENAME=frp_${FRPC_VERSION}_linux_${FRPC_ARCH}.tar.gz
    FRPC_DIRECTORY=frp_${FRPC_VERSION}_linux_${FRPC_ARCH}
    FRPC_URL=https://github.com/fatedier/frp/releases/download/v${FRPC_VERSION}/${FRPC_FILENAME}
    echo "* FRPC INSTALL"
    echo "* Version: ${FRPC_VERSION}"
    echo "* Filename: ${FRPC_FILENAME}"
    echo "* Install Directory: ${FRPC_DIRECTORY}"
    echo "* Download URL: ${FRPC_URL}"

    # Set /tmp as active directory and do our tasks
    pushd /tmp
    curl -L "${FRPC_URL}" -o "${FRPC_FILENAME}"
    tar xfz "${FRPC_FILENAME}"

    # Install FRPC Config
    frpc_config

    # If frpc is not already installed, install it
    if [ ! -f /usr/bin/frpc ]; then
        cp "${FRPC_DIRECTORY}"/frpc /usr/bin/frpc
        chmod +x /usr/bin/frpc
    fi

    # If the frpc service is not active, install it and start it, otherwise restart it
    if [ "$(systemctl show -p ActiveState frpc | sed 's/ActiveState=//g')" != "active" ]; then
        echo "* Installing, enabling and starting frpc service"
        curl -L "${FRPC_SERVICE_URL}" -o /etc/systemd/system/frpc.service
        systemctl daemon-reload
        systemctl enable frpc
        systemctl start frpc
    else
        echo "* Wrote new config; restarting frpc"
        systemctl restart frpc
    fi

    # Cleanup and pop out of /tmp
    rm -rf "${FRPC_DIRECTORY}" "${FRPC_FILENAME}"
    popd
}

frpc_docker() {
    # Check if docker is installed, if not install it
    if [ -x "$(command -v docker)" ]; then
        echo "* Docker is already installed"
    else
        echo "* Installing Docker"

        # Install our required packages
        install_packages curl

        # Pull docker install script and run it
        curl -fsSL https://get.docker.com | sh
    fi
    
    # Start our docker container for FRPC
    docker run --restart=always --network host -d \
      -e FRPC_IP="${FRP_SERVER}" \
      -e FRPC_PORT="${FRP_PORT}" \
      -e FRPC_TOKEN="${FRP_TOKEN}" \
      -e FRPC_SERVICES='http,tcp,80 https,tcp,443' \
      --name frpc privaterouterllc/frpc
}

frpc_config() {
    if [ ! -d /etc/frp ]; then
        mkdir -p /etc/frp
    fi

    cat > /etc/frp/frpc.ini <<-EOF
    [common]
    server_addr = ${FRP_SERVER}
    server_port = 12000
    token = ${FRP_TOKEN}

    [http]
    type = tcp
    local_ip = 127.0.0.1
    local_port = 80
    remote_port = 80

    [https]
    type = tcp
    local_ip = 127.0.0.1
    local_port = 443
    remote_port = 443
EOF
}

# Check if we are root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Read our script name
SCRIPT_NAME="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

# Helper Sub
show_help() {    
    echo "== ${SCRIPT_NAME} Flags (* Indicates Required) =="
    echo "* [-s 123.456.789.012]* sets the FRP Server Address"
    echo "* [-p 7000] sets the FRP Server Port"
    echo "* [-t abcd12345]* sets the FRP Server Token"
    echo "* [-v ${FRPC_VERSION} ] sets the FRP Version Manually"
    echo "* [-d] Flags this as docker container install"
    echo "* [-c] Cleans the history after install"
    echo "* Example: ${SCRIPT_NAME} -s 123.456.789.012 -t abcd12345"
}

# Check if we have passed any arguments
if [ $# -eq 0 ]; then
    show_help
    exit 1
fi

# Iterate over arguments and process them
while (( "${#}" )); do
    case "${1}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -s|--server)
            if [[ ${2} != -* && ! -z ${2} ]]; then
                FRP_SERVER="${2}"
                echo "Using FRP Server: ${2}"
            else
                ERRORS+=("Invalid FRP Server passed to -s")
            fi
            shift
            ;;
        -p|--port)
            if [[ ${2} != -* && ! -z ${2} ]]; then
                FRP_PORT="${2}"
                echo "Using FRP Port: ${2}"
            else
                ERRORS+=("Invalid FRP Port passed to -p")
            fi
            shift
            ;;
        -t|--token)
            if [[ ${2} != -* && ! -z ${2} ]]; then
                FRP_TOKEN="${2}"
                echo "Using FRP Token: ${2}"
            else
                ERRORS+=("Invalid FRP Token passed to -t")
            fi
            shift
            ;;
        -v|--version)
            if [[ ${2} != -* && ! -z ${2} ]]; then
                FRPC_VERSION="${2}"
                echo "Using FRP Version: ${2}"
            else
                ERRORS+=("Invalid FRP Version passed to -v")
            fi
            shift
            ;;
        -f|--force)
            echo "Force Install Enabled"
            FORCE=1
            ;;
        -d|--docker)
            echo "Docker Install Flag Detected"
            DOCKER=1
            ;;
        -c|--clean)
            echo "Clean History Flag Detected"
            CLEAN=1
            ;;
        *)
            ERRORS+=("${1} is not a valid argument for ${SCRIPT_NAME}")
            ;;
    esac
    shift
done

# If we are running docker install, skip this
if [ -z "${DOCKER}" ]; then 
    # If force is not set and FRPC is already installed, exit
    if [[ -z "${FORCE}" && "$(systemctl show -p ActiveState frpc | sed 's/ActiveState=//g')" == "active" ]]; then 
        echo "* FRPC is already installed (use -f to override this)"
        exit 1
    fi
fi

# Check if our required arguments are set
if [ -z "${FRP_SERVER}" ]; then 
    ERRORS+=("FRP Server is required")
fi

if [ -z "${FRP_PORT}" ]; then 
    FRP_PORT=7000
fi

if [ -z "${FRP_TOKEN}" ]; then 
    ERRORS+=("FRP Token is required")
fi

# Print out our errors if we have any
if [ ! -z "${ERRORS}" ]; then
    printf "\n== The following Errors Were Found ==\n"
    for error in "${ERRORS[@]}"; do
        printf "\n= ${error}\n"
    done
    exit 
