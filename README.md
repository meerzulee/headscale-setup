# Headscale Setup

This repository provides a comprehensive setup for configuring **Headscale** with **Caddy** for reverse proxy and Headscale Admin web-apps for efficient management. The setup is based on the detailed guide available [here](https://blog.gurucomputing.com.au/Smart%20VPNS%20with%20Headscale/Introduction/).

## Features

- **Docker Network Configuration**: Easily set up a Docker network for seamless communication between containers.
- **Caddy Integration**: Secure and configure your Headscale instance with Caddy as the reverse proxy, including optional Basic Auth for additional security.
- **Headscale Configuration**: Customize your Headscale setup with a simple configuration file.
- **Admin UIs**: Two powerful admin UI projects ([headscale-ui](https://github.com/gurucomputing/headscale-ui) and [headscale-admin](https://github.com/GoodiesHQ/headscale-admin)) for managing your Headscale instance efficiently.

## Getting Started

1. **Create Docker Network**: 
   ```bash 
   docker network create reverseproxy-nw
   ``` 
2. **Caddy Setup**:
   - Replace `domain` with your actual domain in the `Caddyfile`.
   - Optionally, secure `/web` and `/admin` paths with Basic Auth:
     ```bash
     caddy hash-password -p <password>
     ```
     Add your username and hashed password to the `Caddyfile`.

3. **Headscale Setup**:
   - Update `config.yaml` with your domain details.

4. **Admin UIs Configuration**:
   - Generate API keys for both admin UI projects:
     ```bash
     docker exec headscale headscale apikeys create
     ```
   - Use the generated API keys in the configurations of [headscale-ui](https://github.com/gurucomputing/headscale-ui) and [headscale-admin](https://github.com/GoodiesHQ/headscale-admin).

## Contribution

Feel free to contribute by opening issues or submitting pull requests. For major changes, please open an issue first to discuss what you would like to change.

## License

This project is licensed under the MIT License.

---

Let me know if you need any more details or further adjustments!