# Headscale Setup

This repository provides a comprehensive setup for configuring **Headscale** with **Caddy** for reverse proxy and multiple admin web UIs for efficient management. The setup is based on the detailed guide available [here](https://blog.gurucomputing.com.au/Smart%20VPNS%20with%20Headscale/Introduction/).

## Features

- **Automated Setup Script**: Run a single script to configure everything
- **Docker Network Configuration**: Easily set up a Docker network for seamless communication between containers
- **Caddy Integration**: Secure and configure your Headscale instance with Caddy as the reverse proxy, including Basic Auth for additional security
- **Headscale Configuration**: Customize your Headscale setup with a simple configuration file
- **Multiple Admin UIs**: Three admin UI options for managing your Headscale instance

## Admin UIs

| UI | Path | Repository |
|----|------|------------|
| Headscale UI | `/web` | [gurucomputing/headscale-ui](https://github.com/gurucomputing/headscale-ui) |
| Headscale Admin | `/hs-admin` | [GoodiesHQ/headscale-admin](https://github.com/GoodiesHQ/headscale-admin) |
| Headplane | `/admin` | [tale/headplane](https://github.com/tale/headplane) |

## Project Structure

```
headscale-setup/
├── setup.sh                   # Automated setup script
├── compose.yaml               # Main compose (includes all services)
├── compose.expose-localhost.yaml  # Override to expose services on localhost
├── README.md
├── caddy/
│   ├── compose.yaml
│   └── container-config/
│       └── Caddyfile
├── headscale/
│   ├── compose.yaml
│   └── container-config/
│       └── config.yaml
└── admin-panel/
    ├── compose.yaml
    └── container-config/
        └── headplane.yaml
```

## Quick Start

Run the setup script:

```bash
./setup.sh
```

The script will:
1. Create Docker network `reverseproxy-nw`
2. Ask for your domain
3. Ask for username and password (for Basic Auth)
4. Generate password hash and configure Caddyfile
5. Configure Headscale and Headplane
6. Start all containers
7. Generate and display an API key

## Setup Options

```bash
# Install everything (default)
./setup.sh

# Skip Caddy installation (if you have your own reverse proxy)
./setup.sh --skip-caddy

# Skip all admin panels
./setup.sh --skip-admin

# Install only specific admin panels
./setup.sh --admin=headplane
./setup.sh --admin=headscale-ui,headplane

# Expose services on localhost (for SSH tunneling, etc.)
./setup.sh --expose-localhost

# Combine options
./setup.sh --skip-caddy --admin=headplane --expose-localhost
```

Available admin panels: `headscale-ui`, `headscale-admin`, `headplane`

### Localhost Ports (with --expose-localhost)

| Service | Port |
|---------|------|
| headscale | 4000 |
| headscale-ui | 4020 |
| headscale-admin | 4021 |
| headplane | 4022 |

### Using Docker Compose Directly

You can also use docker compose directly:

```bash
# Set DOCKER_GID for headplane docker socket access
export DOCKER_GID=$(getent group docker | cut -d: -f3)

# Start all services
docker compose up -d

# Start with localhost ports exposed
docker compose -f compose.yaml -f compose.expose-localhost.yaml up -d

# Start specific services
docker compose up -d caddy headscale headplane
```

## CLI Shortcuts

The setup script provides shortcuts for common headscale commands:

```bash
# Run any headscale command
./setup.sh headscale <command>

# Generate a new API key
./setup.sh apikey

# Generate password hash for Caddyfile
./setup.sh hash [password]

# Show help
./setup.sh help
```

Examples:

```bash
# List users
./setup.sh headscale users list

# List nodes
./setup.sh headscale nodes list

# Create a pre-auth key
./setup.sh headscale preauthkeys create --user default

# Create a new user
./setup.sh headscale users create myuser

# Generate password hash
./setup.sh hash mypassword
```

## Cloudflare DNS Configuration

If you're using Cloudflare for DNS, make sure to:

1. Create an **A record** pointing your domain to your server IP
2. **Disable the proxy** (orange cloud off / DNS only)

| Type | Name | Content | Proxy status |
|------|------|---------|--------------|
| A | headscale | your.server.ip | DNS only (grey cloud) |

> **Important**: Cloudflare proxy must be disabled because Headscale uses custom protocols that don't work through Cloudflare's proxy.

## Manual Setup

If you prefer manual configuration:

1. **Create Docker Network**:
   ```bash
   docker network create reverseproxy-nw
   ```

2. **Caddy Setup**:
   - Replace `domain` with your actual domain in `caddy/container-config/Caddyfile`
   - Generate password hash:
     ```bash
     docker run --rm caddy:latest caddy hash-password --plaintext <password>
     ```
   - Add your username and hashed password to the `Caddyfile`

3. **Headscale Setup**:
   - Update `headscale/container-config/config.yaml` with your domain

4. **Headplane Setup**:
   - Update `admin-panel/container-config/headplane.yaml` with your domain
   - Generate a 32-character cookie secret

5. **Start Containers**:
   ```bash
   docker compose -f caddy/compose.yaml up -d
   docker compose -f headscale/compose.yaml up -d
   docker compose -f admin-panel/compose.yaml up -d
   ```

6. **Generate API Key**:
   ```bash
   docker exec headscale headscale apikeys create
   ```
   Use this API key to authenticate in the admin UIs.

## License

This project is licensed under the MIT License.
