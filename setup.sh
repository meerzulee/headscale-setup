#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Show help
if [[ "$1" == "help" || "$1" == "--help" || "$1" == "-h" ]]; then
    echo -e "${BLUE}Headscale Setup Script${NC}"
    echo ""
    echo "Usage:"
    echo "  ./setup.sh              Run the setup wizard"
    echo "  ./setup.sh headscale    Shorthand for 'docker exec headscale headscale'"
    echo "  ./setup.sh apikey       Generate a new API key"
    echo "  ./setup.sh help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  ./setup.sh headscale users list"
    echo "  ./setup.sh headscale nodes list"
    echo "  ./setup.sh headscale preauthkeys create --user default"
    echo "  ./setup.sh apikey"
    exit 0
fi

echo -e "${BLUE}=== Headscale Setup Script ===${NC}\n"

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

# Step 3: Ask for username and password for basic auth
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

# Generate password hash using caddy
echo -e "\n${YELLOW}Generating password hash...${NC}"
PASSWORD_HASH=$(docker run --rm caddy:latest caddy hash-password --plaintext "$PASSWORD")
echo -e "${GREEN}Password hash generated.${NC}"

# Generate cookie secret for headplane (32 characters)
COOKIE_SECRET=$(openssl rand -hex 16)

# Step 4: Update Caddyfile
echo -e "\n${YELLOW}Step 4: Configuring Caddyfile...${NC}"
cat > "$SCRIPT_DIR/caddy/container-config/Caddyfile" << EOF
https://${DOMAIN} {

    basicauth /web* {
        ${USERNAME} ${PASSWORD_HASH}
    }

    reverse_proxy /web* https://headscale-ui:8443 {
        transport http {
            tls_insecure_skip_verify
        }
    }

    basicauth /admin* {
        ${USERNAME} ${PASSWORD_HASH}
    }

    reverse_proxy /admin* headscale-admin:80

    basicauth /headplane* {
        ${USERNAME} ${PASSWORD_HASH}
    }

    reverse_proxy /headplane* http://headplane:3000

    reverse_proxy * http://headscale:8080
}
EOF
echo -e "${GREEN}Caddyfile configured.${NC}"

# Step 5: Update Headscale config
echo -e "\n${YELLOW}Step 5: Configuring Headscale...${NC}"
sed -i "s|^server_url:.*|server_url: https://${DOMAIN}|" "$SCRIPT_DIR/headscale/container-config/config.yaml"
echo -e "${GREEN}Headscale config updated.${NC}"

# Step 6: Configure Headplane
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

# Step 7: Start containers
echo -e "\n${YELLOW}Step 7: Starting containers...${NC}"
echo -e "${BLUE}Starting Caddy...${NC}"
docker compose -f "$SCRIPT_DIR/caddy/compose.yaml" up -d

echo -e "${BLUE}Starting Headscale...${NC}"
docker compose -f "$SCRIPT_DIR/headscale/compose.yaml" up -d

echo -e "${BLUE}Starting Admin Panels...${NC}"
docker compose -f "$SCRIPT_DIR/admin-panel/compose.yaml" up -d

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
echo -e "  Username:    ${USERNAME}"
echo -e ""
echo -e "${GREEN}Admin UIs (all protected by basic auth):${NC}"
echo -e "  Headscale UI:    https://${DOMAIN}/web"
echo -e "  Headscale Admin: https://${DOMAIN}/admin"
echo -e "  Headplane:       https://${DOMAIN}/headplane"
echo -e ""
echo -e "${GREEN}API Key (save this somewhere safe):${NC}"
echo -e "${YELLOW}${API_KEY}${NC}"
echo -e ""
echo -e "${YELLOW}Note: Use this API key to log into all admin UIs.${NC}"
echo -e "${YELLOW}Tip: Use './setup.sh headscale <command>' to run headscale CLI commands.${NC}"
