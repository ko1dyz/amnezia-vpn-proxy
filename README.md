# Amnezia VPN Proxy

Run a local HTTP proxy through an AmneziaWG VPN tunnel with Docker Compose.
The container builds AmneziaWG and 3proxy from source and publishes the proxy at
`http://127.0.0.1:3128`.

```text
Application -> localhost:3128 -> 3proxy -> AmneziaWG tunnel -> VPN server -> Internet
```

## Features

- HTTP proxy with HTTPS CONNECT support.
- Userspace AmneziaWG implementation; no AmneziaWG kernel module required.
- Host port bound to loopback by default.
- IPv4 outbound firewall rule installed after the tunnel starts.
- Proxy DNS servers configured separately from the host resolver.
- VPN credentials mounted at runtime and excluded from the Docker build context.

## Requirements

- A Linux Docker host with Docker Engine and Docker Compose v2 or later.
- Access to `/dev/net/tun` and permission to grant the container `NET_ADMIN`.
- A working **AmneziaWG** configuration exported from your VPN setup.
- A full-tunnel IPv4 profile with `0.0.0.0/0` in the peer's `AllowedIPs`.

OpenVPN, OpenVPN over Cloak, and Xray profiles are not supported. Native Linux
is the documented deployment environment.

## Quick start

1. Clone or download this repository and open its directory.
2. Copy your exported VPN profile into the project:

   ```bash
   cp /path/to/your/amneziawg.conf ./amnezia.conf
   chmod 600 ./amnezia.conf
   ```

   See [amnezia.conf.example](amnezia.conf.example) for the expected structure.
   Its placeholders must be replaced with values from your actual profile.
   Preserve any additional AmneziaWG parameters supplied by your VPN server.

3. Build and start the container:

   ```bash
   docker compose up -d --build
   docker compose logs -f vpn-proxy
   ```

4. Test the proxy:

   ```bash
   curl --proxy http://127.0.0.1:3128 https://ifconfig.me
   docker compose exec vpn-proxy awg show
   ```

   The returned address should be your VPN exit address. `awg show` should show
   a recent handshake after traffic is sent. `docker compose ps` shows container
   state; the project does not currently define a healthcheck.

## Use the proxy

For applications that honor proxy environment variables:

```bash
export HTTP_PROXY=http://127.0.0.1:3128
export HTTPS_PROXY=http://127.0.0.1:3128
export NO_PROXY=localhost,127.0.0.1
```

For a single command:

```bash
HTTPS_PROXY=http://127.0.0.1:3128 your-command
```

HTTPS destinations use CONNECT through the HTTP proxy, so the proxy URL still
starts with `http://`. Check your application's documentation for proxy support.
Only traffic sent through the proxy uses this container's tunnel.

## How it works

The image builds `amneziawg-go`, `amneziawg-tools`, and `3proxy` in a Go build
stage, then copies the resulting binaries into a Debian runtime image.

At startup, `entrypoint.sh` copies the mounted profile to `awg0.conf`, removes
its `DNS` setting, and starts the tunnel with `awg-quick`. The container does
not install `resolvconf`; 3proxy instead uses the `nserver` entries in its own
configuration. With the required full-tunnel profile, those DNS requests use
the VPN route. VPN endpoint hostname resolution may still use Docker's resolver
while the tunnel is being established.

After tunnel setup, an `iptables` OUTPUT rule rejects IPv4 traffic that does
not use `awg0`, carry the tunnel's firewall mark, target a local address, or
belong to an established or related connection. This rule is IPv4 only; the
project does not provide an IPv6 kill switch. Use an IPv4-only profile for the
documented setup.

Startup also queries `https://ipinfo.io/json` to display the outbound IP. This
is a diagnostic request, not a healthcheck. 3proxy then runs in the foreground.
Its `-a` option suppresses `X-Forwarded-For` and `Via` headers.

## Configuration

| File | Purpose |
| --- | --- |
| `Dockerfile` | Build the VPN and proxy binaries and runtime image. |
| `docker-compose.yml` | Configure capabilities, TUN access, mounts, and host port. |
| `entrypoint.sh` | Start the tunnel, install the IPv4 firewall rule, and run 3proxy. |
| `3proxy.cfg` | Configure DNS servers, client access, logging, and proxy port. |
| `amnezia.conf.example` | Document the VPN profile structure without credentials. |
| `amnezia.conf` | Local VPN profile; ignored by Git and excluded from image builds. |

### Change DNS servers

Edit the `nserver` entries in `3proxy.cfg`, then rebuild:

```bash
docker compose up -d --build
```

### Change the host port

For example, change the Compose port mapping to `127.0.0.1:8080:3128` to use
`http://127.0.0.1:8080`. The internal proxy port remains `3128`.

### Replace the VPN profile

Replace `amnezia.conf`, then recreate the container so the bind mount picks up
the replacement file:

```bash
docker compose up -d --force-recreate
```

### Access policy

The published host port listens on `127.0.0.1`. 3proxy uses source-IP access
rules for private IPv4 ranges and loopback, without username/password
authentication. Containers on a reachable Docker network may also access its
internal port; treat the host and that network as trusted.

If you intentionally enable remote access, configure 3proxy users and
`auth strong`, restrict source addresses, and apply host firewall rules before
changing the published bind address.

## Maintenance

```bash
docker compose logs -f vpn-proxy       # Follow logs.
docker compose restart vpn-proxy       # Restart the service.
docker compose up -d --build           # Apply image or proxy configuration changes.
docker compose down                   # Stop and remove the container and network.
docker compose build --pull --no-cache # Refresh base images and upstream sources.
```

## Troubleshooting

| Symptom | Check or fix |
| --- | --- |
| `Missing VPN configuration` | Ensure `amnezia.conf` is a regular file beside `docker-compose.yml`. |
| `/dev/net/tun` is missing | Enable TUN support on the Docker host. |
| `Operation not permitted` during network setup | Check `NET_ADMIN`, TUN access, and the host's container policy. |
| Errors involving `ip -6` | Use an IPv4-only profile: remove IPv6 addresses and `::/0` routes. |
| Proxy requests time out | Check `docker compose logs vpn-proxy` and `docker compose exec vpn-proxy awg show` for a handshake. |
| Proxy rejects a client | Check its source address against the ACL in `3proxy.cfg`. |
| Entrypoint reports a bad interpreter | Ensure `entrypoint.sh` uses LF line endings and rebuild the image. |

Logs and `awg show` output can contain IP addresses and peer identifiers.
Redact them before sharing. Never share private or preshared keys.

## Checks

To validate the configuration and build the image locally:

```bash
bash -n entrypoint.sh
docker compose config --quiet
docker build --tag amnezia-vpn-proxy:local .
```

This project uses [AmneziaWG Go](https://github.com/amnezia-vpn/amneziawg-go),
[AmneziaWG Tools](https://github.com/amnezia-vpn/amneziawg-tools), and
[3proxy](https://github.com/3proxy/3proxy). It is an independent integration.
