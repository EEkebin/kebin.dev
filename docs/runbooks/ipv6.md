# Runbook: IPv6

Outbound only. The servers use IPv6 to reach the internet; nothing is published over IPv6 (no AAAA records), because the provider's delegated prefix can change and DNS is updated by hand.

## How it is wired

| Layer | What |
|---|---|
| Provider | delegates a /56 to OPNsense (WAN DHCPv6 client: prefix delegation size 56, "send prefix hint" on). With the default /64 only one network can have IPv6 |
| OPNsense | each network tracks WAN with its own prefix ID: LAN 0, VM LAN (VLAN 10) 10, WLAN (VLAN 20) 20, and sends router advertisements. Managed by the owner, not from this repo |
| VMs | get an address by SLAAC from the advertisement (`2603:8001:8f00:d010::/64` at the time of writing) |
| media VM | netplan `accept-ra: true` on `ens18`. Podman turns on IPv6 forwarding for the container network, and with forwarding on the VM would otherwise stop accepting advertisements and lose its address |
| containers | compose network `media_default` is dual-stack: `10.89.0.0/24` + `2001:db8:89::/64`, NAT66 behind the VM's address |

## Why the container subnet is 2001:db8:89::/64 and not a private fd.. range

Address selection (RFC 6724) ranks a private ULA source below IPv4 when the destination is a normal global address. With a ULA subnet, FlareSolverr's Chromium kept using IPv4 while Prowlarr (musl) used IPv6. Cloudflare clearance cookies are bound to the address that solved the challenge, so every FlareSolverr-routed indexer failed with "blocked by CloudFlare Protection". `2001:db8::/32` is the documentation range: never routed on the internet, and it sorts like ordinary global IPv6, so every container prefers IPv6 consistently. It only exists inside the bridge; traffic leaves with the VM's real address.

## Checks

```
# router advertisement and address on a VM
ip -6 addr show scope global; ip -6 route show default
curl -6 https://api64.ipify.org

# from inside a container (must print the VM's 2603:... address)
podman exec prowlarr curl -s -6 https://api64.ipify.org
podman network inspect media_default --format '{{.IPv6Enabled}} {{range .Subnets}}{{.Subnet}} {{end}}'
```

If the VMs lose IPv6: look at OPNsense Interfaces → Overview. The VM LAN row must show a global `/64` route, not only `fe80`. If it shows only `fe80`, the WAN is holding a /64 lease again: reload WAN, or generate a new DHCP unique identifier and reboot OPNsense.

Changing the container network (subnet, IPv6 on/off) needs `podman-compose down`, `podman network rm media_default`, `podman-compose up -d`: every container is recreated, about two minutes of downtime.

## Known side effect on trunk ports

A machine plugged into a switch port that carries the VLANs tagged, with a NIC driver that strips VLAN tags (Intel "Packet Priority & VLAN: Enabled" on Windows), receives the advertisements of **all** VLANs and configures an address from each prefix. Replies to the wrong-prefix addresses never arrive, so IPv6 on that machine times out. Fix on the switch (make the port untagged-only) or set the NIC property to priority-only / disabled.
