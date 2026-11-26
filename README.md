# wortlaut-infra

Infrastructure for [Wortlaut](https://github.com/wortlauts/wortlaut): the local development stack today, deployment setups (Compose on a server, later Terraform, Helm and GitOps) as the project grows.

## Local development stack

`compose/dev` starts a single-node Elasticsearch and Kibana with pinned versions and health checks.

Requirements: Docker with Compose v2, about 2 GB of free memory.

```powershell
docker compose -f compose/dev/compose.yaml up -d --wait
```

| Service       | URL                   |
| ------------- | --------------------- |
| Elasticsearch | http://localhost:9200 |
| Kibana        | http://localhost:5601 |

Check that it is healthy:

```powershell
curl http://localhost:9200/_cluster/health
```

Stop the stack (data is kept in the `es-data` volume):

```powershell
docker compose -f compose/dev/compose.yaml down
```

Remove the stack including all indexed data:

```powershell
docker compose -f compose/dev/compose.yaml down -v
```

Versions and ports can be overridden with a `.env` file next to `compose.yaml`; see `compose/dev/.env.example`.

### Notes

- Security is disabled and all ports are bound to `127.0.0.1`. This stack is for local use only.
- Elasticsearch and Kibana must run the same version. Bump `ELASTIC_VERSION` in one place.
- The German analyzer used for the speech text is built into Elasticsearch, so no plugins are needed.

## Production stack

`compose/prod` runs the whole product on a single host: Elasticsearch with security, Kibana, the API and the frontend. Secrets are kept encrypted in this repository with [SOPS](https://github.com/getsops/sops) and [age](https://github.com/FiloSottile/age). See [compose/prod/README.md](compose/prod/README.md).

## Layout

```text
compose/
  dev/        local stack (Elasticsearch, Kibana)
  prod/       production stack, versions and encrypted secrets
host/         one-time preparation of a Debian host for rootless Docker
```
