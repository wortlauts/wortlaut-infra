# Production stack

Runs the whole product on one host with Docker Compose.

| Service               | Purpose                                                             | Memory limit |
| --------------------- | ------------------------------------------------------------------- | ------------ |
| `elasticsearch`       | search index, security enabled                                      | 1200 MB      |
| `elasticsearch-setup` | one-shot job that creates the users, roles and the log template     |              |
| `kibana`              | Kibana for Elasticsearch                                            | 1100 MB      |
| `api`                 | [wortlaut-api](https://github.com/wortlauts/wortlaut-api)           | 256 MB       |
| `frontend`            | [wortlaut-frontend](https://github.com/wortlauts/wortlaut-frontend) | 256 MB       |
| `indexer`             | job (profile `jobs`): the daily sync, see below                     | 512 MB       |
| `kibana-setup`        | job (profile `jobs`): imports the Kibana dashboards                 | 128 MB       |

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
2. The host runs `compose/prod/deploy.sh` for every new commit of `main` in this repository, which also rolls out changed secrets. The script does nothing when the revision is already deployed (`--force` deploys anyway). It waits until every service is healthy. Afterwards it removes every image that is not part of this stack, which includes the older versions of the application images. Docker refuses to remove an image that a container still uses, so nothing that runs is affected.
3. When the script is done it pushes an info commit with the result (`status.env`) to the branch `prod-status`. The workflow **Report PROD deploy** (it lives on the branch `prod-status` itself, because GitHub runs a push workflow from the branch that was pushed) turns it into a commit status `deploy/prod` on the deployed commit and fails when the deployment failed, so a broken deployment shows up as a red check and in the notification mails. **Deploy to PROD** of the application repository waits for this result and fails with it.

Rolling back means running **Deploy to PROD** again from the older commit, or changing the tag in `versions.env` through a pull request.

`main` of this repository is protected: changes need a pull request with a green CI run. Only the deploy workflows, which push through a deploy key, commit directly.

## Everyday use

Edit secrets (decrypts into the editor and encrypts again when you save):

```bash
sops compose/prod/secrets/prod.enc.env
```

Roll out a change: commit the new version or secret, then run `compose/prod/deploy.sh` on the host.

## Keeping the index current

A daily job imports the protocols that are new or were corrected since the last run. It is the `indexer` service run with the command `sync` (profile `jobs`, memory limit 512 MB, no volume), started by `sync.sh`. The script decrypts the secrets like `deploy.sh`, pulls the pinned indexer image, runs the job and records the result. By default it fetches the new protocols and checks the newest ten again, which is about a dozen requests a day. See the [indexer README](https://github.com/wortlauts/wortlaut-indexer#sync) for what a run does and [ADR 0007](https://github.com/wortlauts/wortlaut/blob/main/docs/adr/0007-scheduled-sync-of-new-protocols.md) for the reasoning.

The schedule is a systemd user timer (`host/systemd/wortlaut-sync.timer`, every day around 06:30 with a random delay of up to ten minutes, caught up after downtime). `deploy.sh` installs and enables the units through `host/install-sync-timer.sh` after every successful deployment, so nothing has to be set up by hand. The script can also be run on its own as the user of the stack.

Everything the job writes on the host stays in the state directory of that user (`$XDG_STATE_HOME/wortlaut`, default `~/.local/state/wortlaut`):

| File | Content |
| --- | --- |
| `sync.log` | output of every run, appended |
| `sync-status.env` | time, result (`success` or `failure`) and summary line of the last run |

The results are also written to the central log in Elasticsearch, see below.

Useful commands, run as the user of the stack:

```bash
systemctl --user list-timers wortlaut-sync.timer   # when the next run is due
systemctl --user start wortlaut-sync.service       # run it now
tail -n 30 ~/.local/state/wortlaut/sync.log
cat ~/.local/state/wortlaut/sync-status.env
```

To repair or backfill a period, run the indexer with a date range (needs the decrypted secrets in the environment, like `deploy.sh` provides):

```bash
docker compose --profile jobs run --rm --no-deps indexer sync --legislative-period 20 --from 2024-01-01
```

`sync --all` checks every protocol of a period (about 100 MB for period 21). Use it rarely: the Bundestag page has a bot protection that answers many quick requests with a challenge page, and then the sync fails (it never works around the protection).

## Central log and dashboards

Elasticsearch holds one central log, the data stream `wortlaut-logs`. `elasticsearch-setup` creates its template (`elasticsearch/logs-template.json`, one year of retention) on every deployment. The indexer user may only add documents to it. The sync writes one event per protocol (`event.action: sync.protocol`) and one per run (`sync.run`), with the counts of speeches added, updated and removed, failures, and the duration. Every event has `@timestamp`, `service.name`, `log.level`, `event.action`, `event.outcome` and `message`. The sync fields are listed in the template.

The API and the frontend do not write to it yet. They need a log shipper first, which is a separate step. The template is the place to add their fields.

`kibana-setup` imports two dashboards after every deployment (`kibana/dashboards.ndjson`, a failed import is reported but does not fail the deployment):

- **Wortlaut: speeches**: how many speeches the index holds, per legislative period, per year and per faction, and the date of the latest speech.
- **Wortlaut: sync and log**: runs, failed runs and failed protocol imports, speeches added, updated and removed per day, run duration, the failed imports as a list, and all log events.

To change a dashboard, edit it in Kibana, then export both dashboards with their related objects (Stack Management, Saved objects) and replace `kibana/dashboards.ndjson`. The next deployment overwrites what is in Kibana with this file.

## Loading a period from scratch

On an empty index `sync` loads a whole period without keeping files, because every session counts as new. Run it with the same `--env-file` options as `deploy.sh` uses, or through a shell that has the decrypted secrets in its environment:

```bash
docker compose --profile jobs run --rm --no-deps indexer sync --legislative-period 20
```

This downloads about 100 MB per period. Do it one period at a time: the Bundestag page has a bot protection that answers many quick requests with a challenge page.

To load protocols from local files instead, mount a directory with the XML files when running the `import` command:

```bash
docker compose --profile jobs run --rm --no-deps -v "$PWD/protocols:/data:ro" indexer import --source /data
```

The imports are idempotent, so they can be repeated.

## Ports on the host

All bound to `127.0.0.1`, so they are only reachable from the host itself.

| Setting         | Default | Service       |
| --------------- | ------- | ------------- |
| `FRONTEND_PORT` | 3000    | frontend      |
| `API_PORT`      | 5080    | API           |
| `KIBANA_PORT`   | 5601    | Kibana        |
| `ES_PORT`       | 9200    | Elasticsearch |

They can be changed in the secrets file, which is read after `versions.env`.
