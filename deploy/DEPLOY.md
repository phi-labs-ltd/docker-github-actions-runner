# Building & Deploying the Runner Image

How we build the self-hosted GitHub runner image and distribute it across hosts.

- **mainnet-api-5** — where we build the image (and run it)
- **mainnet-api-4** (`10.0.1.4`) — also runs the image

The runner image is used on **both** hosts. We build once on `mainnet-api-5` and ship the result directly to `mainnet-api-4` over SSH — no registry involved.

## 1. Build the image

On **mainnet-api-5**, from the repo root:

```bash
./build-local.sh -r noble
```

> The build and deploy scripts live in `deploy/`. `build-local.sh` is at the
> repo root; run it from there (or `../build-local.sh` from inside `deploy/`).

This builds both the base and runner images for the host architecture and loads them into the local Docker daemon (no push). The resulting runner image is tagged:

```
phi-labs-ltd/github-runner:ubuntu-noble
```

`-r noble` selects Ubuntu 24.04. See `./build-local.sh -h` for other options (`-r jammy` for 22.04, `-s base|runner` to build only one stage, `--push` to push to Docker Hub instead).

After this step the image is already available on `mainnet-api-5`.

## 2. Ship the image to mainnet-api-4

Use the `deploy-image.sh` script. It streams the image to the remote host
gzip-compressed (`docker save | gzip | ssh 'gunzip | docker load'`) — no
registry, no intermediate tarball — and pre-checks that the image and SSH key
both exist before starting.

```bash
cd deploy
./deploy-image.sh
```

The defaults match this setup:

| Option         | Env var | Default                                     |
| -------------- | ------- | ------------------------------------------- |
| `-i, --image`  | `IMAGE` | `phi-labs-ltd/github-runner:ubuntu-noble`   |
| `-d, --dest`   | `DEST`  | `junaid@10.0.1.4`                           |
| `-k, --key`    | `KEY`   | `~/.ssh/bolt-deploy.key`                    |

Override any of them as needed:

```bash
./deploy-image.sh -i phi-labs-ltd/github-runner:ubuntu-jammy   # different image
./deploy-image.sh -d junaid@10.0.1.7 -k ~/.ssh/other.key       # different host/key
```

Run `./deploy-image.sh -h` for full usage.

## 3. Verify on mainnet-api-4

```bash
docker images | grep github-runner
```

You should see `phi-labs-ltd/github-runner:ubuntu-noble`.

## Notes

- The transfer can be large; `deploy-image.sh` pipes the gzip-compressed stream straight over SSH, so nothing is written to disk on either side.
- If you'd rather run it by hand, the equivalent one-liner is:
  ```bash
  docker save phi-labs-ltd/github-runner:ubuntu-noble \
    | gzip \
    | ssh -i ~/.ssh/bolt-deploy.key junaid@10.0.1.4 'gunzip | docker load'
  ```
- Rebuilding only the runner (when the base image is unchanged): `./build-local.sh -r noble -s runner`.
