#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
INSTALL_CADDY=true
INSTALL_HEADSCALE=true
INSTALL_ADMIN=true
EXPOSE_ADMIN=false
ADMIN_PANELS=("headscale-ui" "headscale-admin" "headplane")

# Show help
show_help() {
    echo -e "${BLUE}Headscale Setup Script${NC}"
    echo ""
    echo "Usage:"
    echo "  ./setup.sh [options]        Run the setup wizard"
    echo "  ./setup.sh headscale        Shorthand for 'docker exec headscale headscale'"
    echo "  ./setup.sh apikey           Generate a new API key"
    echo "  ./setup.sh hash [password]  Generate password hash for Caddyfile"
    echo "  ./setup.sh help             Show this help message"
    echo ""
    echo "Options:"
    echo "  --skip-caddy                Skip Caddy installation"
    echo "  --skip-admin                Skip all admin panels installation"
    echo "  --admin=PANELS              Choose admin panels (comma-separated)"
    echo "                              Available: headscale-ui,headscale-admin,headplane"
    echo "  --expose-admin              Expose admin panels on localhost"
    echo "                              headscale-ui:4020, headscale-admin:4021, headplane:4022"
    echo ""
    echo "Examples:"
    echo "  ./setup.sh                                    # Install everything"
    echo "  ./setup.sh --skip-caddy                       # Skip Caddy"
    echo "  ./setup.sh --skip-admin                       # Skip admin panels"
    echo "  ./setup.sh --admin=headplane                  # Only install Headplane"
    echo "  ./setup.sh --admin=headscale-ui,headplane     # Install specific panels"
    echo ""
    echo "  ./setup.sh headscale users list"
    echo "  ./setup.sh headscale nodes list"
    echo "  ./setup.sh headscale preauthkeys create --user default"
    echo "  ./setup.sh apikey"
    echo "  ./setup.sh hash mypassword"
    exit 0
}

# Check if running as headscale shorthand
if [[ "$1" == "headscale" ]]; then
    shift
    docker exec headscale headscale "$@"
    exit 0
fi

# Check if running as apikey shorthand
if [[ "$1" == "apikey" ]]; then
    docker exec headscale headscale apikeys create
    exit 0
fi

# Check if running as hash shorthand
if [[ "$1" == "hash" ]]; then
    if [[ -z "$2" ]]; then
        read -s -p "Enter password to hash: " PASSWORD
        echo ""
    else
        PASSWORD="$2"
    fi
    mkpasswd -m bcrypt "$PASSWORD"
    exit 0
fi

# Show help
if [[ "$1" == "help" || "$1" == "--help" || "$1" == "-h" ]]; then
    show_help
fi

# Parse arguments
for arg in "$@"; do
    case $arg in
        --skip-caddy)
            INSTALL_CADDY=false
            shift
            ;;
        --skip-admin)
            INSTALL_ADMIN=false
            shift
            ;;
        --admin=*)
            IFS=',' read -ra ADMIN_PANELS <<< "${arg#*=}"
            shift
            ;;
        --expose-admin)
            EXPOSE_ADMIN=true
            shift
            ;;
        *)
            ;;
    esac
done

echo -e "${BLUE}=== Headscale Setup Script ===${NC}\n"

# Show installation plan
echo -e "${YELLOW}Installation Plan:${NC}"
echo -e "  Caddy:        $([ "$INSTALL_CADDY" = true ] && echo "${GREEN}Yes${NC}" || echo "${RED}No${NC}")"
echo -e "  Headscale:    ${GREEN}Yes${NC}"
if [[ "$INSTALL_ADMIN" = true ]]; then
    echo -e "  Admin UIs:    ${GREEN}${ADMIN_PANELS[*]}${NC}"
    echo -e "  Expose Admin: $([ "$EXPOSE_ADMIN" = true ] && echo "${GREEN}Yes (localhost:4020-4022)${NC}" || echo "${RED}No${NC}")"
else
    echo -e "  Admin UIs:    ${RED}None${NC}"
fi
echo ""

# Step 1: Create Docker network
echo -e "${YELLOW}Step 1: Creating Docker network...${NC}"
if docker network ls | grep -q "reverseproxy-nw"; then
    echo -e "${GREEN}Network 'reverseproxy-nw' already exists.${NC}"
else
    docker network create reverseproxy-nw
    echo -e "${GREEN}Network 'reverseproxy-nw' created.${NC}"
fi

# Step 2: Ask for domain
echo -e "\n${YELLOW}Step 2: Domain Configuration${NC}"
read -p "Enter your domain (e.g., headscale.example.com): " DOMAIN

if [[ -z "$DOMAIN" ]]; then
    echo -e "${RED}Error: Domain cannot be empty.${NC}"
    exit 1
fi

# Step 3: Ask for username and password for basic auth (only if caddy or admin is installed)
if [[ "$INSTALL_CADDY" = true && "$INSTALL_ADMIN" = true ]]; then
    echo -e "\n${YELLOW}Step 3: Basic Auth Configuration${NC}"
    read -p "Enter username for web UI basic auth: " USERNAME

    if [[ -z "$USERNAME" ]]; then
        echo -e "${RED}Error: Username cannot be empty.${NC}"
        exit 1
    fi

    read -s -p "Enter password for basic auth: " PASSWORD
    echo ""

    if [[ -z "$PASSWORD" ]]; then
        echo -e "${RED}Error: Password cannot be empty.${NC}"
        exit 1
    fi

    # Generate password hash using mkpasswd
    echo -e "\n${YELLOW}Generating password hash...${NC}"
    PASSWORD_HASH=$(mkpasswd -m bcrypt "$PASSWORD")
    echo -e "${GREEN}Password hash generated.${NC}"
fi

# Generate cookie secret for headplane (32 characters)
COOKIE_SECRET=$(openssl rand -hex 16)

# Step 4: Update Caddyfile (only if caddy is installed)
if [[ "$INSTALL_CADDY" = true ]]; then
    echo -e "\n${YELLOW}Step 4: Configuring Caddyfile...${NC}"

    # Start building Caddyfile
    CADDYFILE="https://${DOMAIN} {\n"

    # Add routes for selected admin panels
    if [[ "$INSTALL_ADMIN" = true ]]; then
        for panel in "${ADMIN_PANELS[@]}"; do
            case $panel in
                headscale-ui)
                    CADDYFILE+="\n    basicauth /web* {\n        ${USERNAME} ${PASSWORD_HASH}\n    }\n"
                    CADDYFILE+="\n    reverse_proxy /web* https://headscale-ui:8443 {\n        transport http {\n            tls_insecure_skip_verify\n        }\n    }\n"
                    ;;
                headscale-admin)
                    CADDYFILE+="\n    basicauth /admin* {\n        ${USERNAME} ${PASSWORD_HASH}\n    }\n"
                    CADDYFILE+="\n    reverse_proxy /admin* headscale-admin:80\n"
                    ;;
                headplane)
                    CADDYFILE+="\n    basicauth /headplane* {\n        ${USERNAME} ${PASSWORD_HASH}\n    }\n"
                    CADDYFILE+="\n    reverse_proxy /headplane* http://headplane:3000\n"
                    ;;
            esac
        done
    fi

    CADDYFILE+="\n    reverse_proxy * http://headscale:8080\n}"

    echo -e "$CADDYFILE" > "$SCRIPT_DIR/caddy/container-config/Caddyfile"
    echo -e "${GREEN}Caddyfile configured.${NC}"
fi

# Step 5: Update Headscale config
echo -e "\n${YELLOW}Step 5: Configuring Headscale...${NC}"
sed -i "s|^server_url:.*|server_url: https://${DOMAIN}|" "$SCRIPT_DIR/headscale/container-config/config.yaml"
echo -e "${GREEN}Headscale config updated.${NC}"

# Step 6: Configure Headplane (only if headplane is selected)
if [[ "$INSTALL_ADMIN" = true && " ${ADMIN_PANELS[*]} " =~ " headplane " ]]; then
    echo -e "\n${YELLOW}Step 6: Configuring Headplane...${NC}"
    cat > "$SCRIPT_DIR/admin-panel/container-config/headplane.yaml" << EOF
server:
  host: "0.0.0.0"
  port: 3000
  base_url: "https://${DOMAIN}"
  cookie_secret: "${COOKIE_SECRET}"
  cookie_secure: true
  cookie_max_age: 86400
  data_path: "/var/lib/headplane"

headscale:
  url: "http://headscale:8080"
  config_path: "/etc/headscale/config.yaml"
  config_strict: false

integration:
  docker:
    enabled: true
    container_label: "me.tale.headplane.target=headscale"
    socket: "unix:///var/run/docker.sock"
EOF
    echo -e "${GREEN}Headplane config created.${NC}"
fi

# Step 7: Start containers
echo -e "\n${YELLOW}Step 7: Starting containers...${NC}"

# Build compose command
COMPOSE_FILES="-f $SCRIPT_DIR/compose.yaml"
if [[ "$EXPOSE_ADMIN" = true ]]; then
    COMPOSE_FILES+=" -f $SCRIPT_DIR/compose.expose-admin.yaml"
fi

# Build list of services to start
SERVICES=""

if [[ "$INSTALL_CADDY" = true ]]; then
    SERVICES+="caddy "
fi

SERVICES+="headscale "

if [[ "$INSTALL_ADMIN" = true ]]; then
    for panel in "${ADMIN_PANELS[@]}"; do
        case $panel in
            headscale-ui)
                SERVICES+="headscale-ui "
                ;;
            headscale-admin)
                SERVICES+="headscale-admin "
                ;;
            headplane)
                SERVICES+="headplane "
                ;;
        esac
    done
fi

echo -e "${BLUE}Starting services: ${SERVICES}${NC}"
docker compose $COMPOSE_FILES up -d $SERVICES

# Wait for headscale to be ready
echo -e "\n${YELLOW}Waiting for Headscale to be ready...${NC}"
sleep 5

# Step 8: Generate API key
echo -e "\n${YELLOW}Step 8: Generating API key...${NC}"
API_KEY=$(docker exec headscale headscale apikeys create)
echo -e "${GREEN}API Key generated successfully!${NC}"

# Summary
echo -e "\n${BLUE}=== Setup Complete ===${NC}"
echo -e "\n${GREEN}Configuration Summary:${NC}"
echo -e "  Domain:      https://${DOMAIN}"
if [[ "$INSTALL_CADDY" = true && "$INSTALL_ADMIN" = true ]]; then
    echo -e "  Username:    ${USERNAME}"
fi
echo -e ""

if [[ "$INSTALL_ADMIN" = true ]]; then
    echo -e "${GREEN}Admin UIs (all protected by basic auth):${NC}"
    for panel in "${ADMIN_PANELS[@]}"; do
        case $panel in
            headscale-ui)
                echo -e "  Headscale UI:    https://${DOMAIN}/web"
                ;;
            headscale-admin)
                echo -e "  Headscale Admin: https://${DOMAIN}/admin"
                ;;
            headplane)
                echo -e "  Headplane:       https://${DOMAIN}/headplane"
                ;;
        esac
    done
    if [[ "$EXPOSE_ADMIN" = true ]]; then
        echo -e ""
        echo -e "${GREEN}Localhost ports:${NC}"
        for panel in "${ADMIN_PANELS[@]}"; do
            case $panel in
                headscale-ui)
                    echo -e "  Headscale UI:    http://localhost:4020"
                    ;;
                headscale-admin)
                    echo -e "  Headscale Admin: http://localhost:4021"
                    ;;
                headplane)
                    echo -e "  Headplane:       http://localhost:4022"
                    ;;
            esac
        done
    fi
    echo -e ""
fi

echo -e "${GREEN}API Key (save this somewhere safe):${NC}"
echo -e "${YELLOW}${API_KEY}${NC}"
echo -e ""
echo -e "${YELLOW}Note: Use this API key to log into all admin UIs.${NC}"
echo -e "${YELLOW}Tip: Use './setup.sh headscale <command>' to run headscale CLI commands.${NC}"
