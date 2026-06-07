# Tailscale ACLs

Kanidm regional nodes should authenticate with `tag:kanidm`.

The tailnet policy must allow `tag:kanidm` to reach `tag:kanidm` on:

- `8444` for Kanidm replication.
- `3636` if using LDAPS through Tailscale.

Admin users or admin-tagged devices should be allowed to reach `tag:kanidm:9080` for the ops API. Do not allow `tag:kanidm` to reach `tag:kanidm:9080`; Kanidm nodes do not need peer-to-peer ops API access.

The ops API is tailnet-only and must never be exposed through Bunny public HTTP/CDN endpoints. `OPS_ADMIN_TOKEN` is defense-in-depth in addition to Tailscale grants.

Earlier failures can look like DNS failures because policy can prevent peer visibility. MagicDNS over SOCKS worked once grants allowed the traffic.

MagicDNS names should look like:

```text
kanidm-sg.nessie-monster.ts.net
kanidm-ams.nessie-monster.ts.net
```

## Example Grants

Adapt this to the real tailnet policy:

```json
{
  "tagOwners": {
    "tag:kanidm": ["autogroup:admin"]
  },
  "grants": [
    {
      "src": ["tag:kanidm"],
      "dst": ["tag:kanidm"],
      "ip": ["8444"]
    },
    {
      "src": ["autogroup:admin"],
      "dst": ["tag:kanidm"],
      "ip": ["9080"]
    },
    {
      "src": ["tag:kanidm"],
      "dst": ["tag:kanidm"],
      "ip": ["3636"]
    }
  ]
}
```

For temporary transport tests:

```json
{
  "grants": [
    {
      "src": ["tag:kanidm"],
      "dst": ["tag:kanidm"],
      "ip": ["9090"]
    }
  ]
}
```

## Example Tests

Tailscale policy tests are optional but useful:

```json
{
  "tests": [
    {
      "src": "tag:kanidm",
      "accept": ["tag:kanidm:8444", "tag:kanidm:3636"]
    },
    {
      "src": "autogroup:admin",
      "accept": ["tag:kanidm:9080"]
    },
    {
      "src": "tag:kanidm",
      "deny": ["tag:kanidm:9080"]
    }
  ]
}
```
