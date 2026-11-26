# Production stack

Runs the whole product on one host with Docker Compose.

| Service               | Purpose                                                             | Memory limit |
| --------------------- | ------------------------------------------------------------------- | ------------ |
| `elasticsearch`       | search index, security enabled                                      | 1200 MB      |
| `elasticsearch-setup` | one-shot job that creates the users and roles below                 |              |
| `kibana`              | Kibana for Elasticsearch                                            | 1100 MB      |
| `api`                 | [wortlaut-api](https://github.com/wortlauts/wortlaut-api)           | 256 MB       |
| `frontend`            | [wortlaut-frontend](https://github.com/wortlauts/wortlaut-frontend) | 256 MB       |

Elasticsearch speaks plain HTTP inside the Compose network, which is not reachable from outside. The ports published on the host are bound to `127.0.0.1`.

## How configuration works

- `versions.env` holds everything that is not secret: image versions and tags. A change here is the way to roll out a new version.
- `secrets/prod.enc.env` holds all secrets. The values are encrypted with SOPS and age, the names stay readable. `secrets/prod.env.example` lists the names.
- `deploy.sh` pulls this repository, decrypts the secrets into a file in memory (`$XDG_RUNTIME_DIR`), runs `docker compose pull` and `up`, and removes the file again. The host needs Docker, Git and the private age key, nothing else.

## First setup

1. Create an age key for every person or machine that has to read the secrets: `age-keygen -o keys.txt`. Keep the private key out of the repository. Only the public key (`age1...`) goes into `.sops.yaml` at the repository root.
2. Create the encrypted file from the example, for instance by writing the values to a temporary file and running `sops encrypt --input-type dotenv --output-type dotenv <file> > compose/prod/secrets/prod.enc.env`. Use generated values (`openssl rand -hex 24`), letters and digits only.
3. On the host, put the private age key at `~/.config/sops/age/keys.txt` (mode 600), clone this repository and run `compose/prod/deploy.sh`.

## Deploying a new version

1. In the API, frontend or indexer repository run the workflow **Deploy to PROD** (Actions tab, "Run workflow"). It runs the CI of that repository, builds a `linux/arm64` image, publishes it to ghcr.io as `sha-<short commit>` and then commits the new tag to `compose/prod/versions.env` of this repository. The packages have to be public, because the host pulls them without a login.
2. The host runs `compose/prod/deploy.sh` for every new commit of `main` in this repository, which also rolls out changed secrets. The script does nothing when the revision is already deployed (`--force` deploys anyway). It waits until every service is healthy.
3. When the script is done it pushes an info commit with the result (`status.env`) to the branch `prod-status`. The workflow **Report PROD deploy** turns it into a commit status `deploy/prod` on the deployed commit and fails when the deployment failed, so a broken deployment shows up as a red check and in the notification mails. **Deploy to PROD** of the application repository waits for this result and fails with it.

Rolling back means running **Deploy to PROD** again from the older commit, or changing the tag in `versions.env` through a pull request.

`main` of this repository is protected: changes need a pull request with a green CI run. Only the deploy workflows, which push through a deploy key, commit directly.

## Everyday use

Edit secrets (decrypts into the editor and encrypts again when you save):

```bash
sops compose/prod/secrets/prod.enc.env
```

Roll out a change: commit the new version or secret, then run `compose/prod/deploy.sh` on the host.

## Loading the speeches

The `indexer` service is a job, not a long-running service. It logs in with the indexer user and keeps the downloaded protocols in the `indexer-data` volume:

```bash
docker compose run --rm indexer download --legislative-period 21 --target /data
docker compose run --rm indexer import --source /data --elasticsearch http://elasticsearch:9200
```

Run both for each legislative period. The imports are idempotent, so they can be repeated. When the speeches are in Elasticsearch the downloaded files are not needed any more: `docker volume rm wortlaut_indexer-data` removes them.

(Run these with the same `--env-file` options as `deploy.sh` uses, or through a shell that has the decrypted secrets in its environment.)

## Ports on the host

All bound to `127.0.0.1`, so they are only reachable from the host itself.

| Setting         | Default | Service       |
| --------------- | ------- | ------------- |
| `FRONTEND_PORT` | 3000    | frontend      |
| `API_PORT`      | 5080    | API           |
| `KIBANA_PORT`   | 5601    | Kibana        |
| `ES_PORT`       | 9200    | Elasticsearch |

They can be changed in the secrets file, which is read after `versions.env`.
