## Rendezvous

[Rendezvous points](https://docs.libp2p.io/concepts/discovery-routing/rendezvous/) are used for makers to make themselves discoverable to takers. We need as many of them as possible to make the network redundant.

If you have a small server, you can run a rendezvous point on it. It takes little to no resources.

### Setup

```bash
./setup-rendezvous.sh
```

This will guide you through the setup process. You need to expose the port to the public internet (check the `.env` file).