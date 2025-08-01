# Rendezvous Server

[Rendezvous points](https://docs.libp2p.io/concepts/discovery-routing/rendezvous/) are used for [makers](https://github.com/eigenwallet/core/blob/master/dev-docs/asb/README.md#asb-discovery) to make themselves discoverable to takers (users running the [eigenwallet](https://github.com/eigenwallet/core)).

We need as many of them as possible to make peer discovery within the network redundant.

If you have a small server, you can run a rendezvous point on it. It takes little to no resources.

## How to run

```bash
./setup-rendezvous.sh
```

This will guide you through the setup process. You need to expose the port to the public internet (check the `.env` file).