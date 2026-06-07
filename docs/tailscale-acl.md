# Tailscale ACLs

Kanidm regional nodes should authenticate with `tag:kanidm`.

The tailnet policy must allow `tag:kanidm` to reach `tag:kanidm` on:

- `8444` for Kanidm replication.
- `9090` only while running transport tests.
- `3636` if using LDAPS through Tailscale.

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
    }
  ]
}
```
