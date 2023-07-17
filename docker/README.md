# Deploy `ex_nvr` using docker compose

In this guide, we'll deploy `ex_nvr` using `docker compose`. We provide a `docker-compose.yml` and `.env` environment variables files.

Copy the two provided files to your target host and update the files to fit your needs.

## Quick deploy

We provide a script to quickly deploy `ex_nvr` using `docker compose`. It'll try to install `docker` if it's not installed on the target machine (currently only `ubuntu` is supported).

Before running the script, make sure that a `cert` folder with `certificate.key` and `certificate.crt` files exists in the folder where you'll run the following command (For `Evercam` we already have certificates on `zoho vault`).

```bash
bash <(wget -qO- https://evercam-public-assets.s3.eu-west-1.amazonaws.com/ex_nvr/docker-deploy.sh)
```

The script will prompt you for some configuration with default values.

In the following steps, we'll explain in details what the script does

## Dependencies

Make sure that `docker` and `docker compose plugin` are installed on your target machine.

See how to install docker [here](https://docs.docker.com/engine/install/)

## Pulling docker image

The docker images are saved in Github container registry `ghcr.io` and publicly available.

```bash
docker pull ghcr.io/evercam/ex_nvr:latest
```

## Which image to use

Currently there's two different tags available for `ex_nvr` images, `v*` and `v*-armv7` where `*` represent a version number (e.g. `0.1.1`), the first is for `arm64/v8` and `amd64` machines and the latter for `arm/v7`.

Update `docker-compose.yml` file to use the appropriate image.

## HTTPS

If `https` is enabled and it should be, we'll need a private key and a certificate. Generating this files is out of the scope of this guide. However, there's many ways to generate this certificates, like self signed certificates (not recommended for production) or using a tool like [`let's encrypt`](https://letsencrypt.org/).

In this guide, we assume the files are called `certificate.key` for the key, and `certficate.crt` for the certificate.

## Prepare volumes

By default any data written to a docker container will be lost when the container is stopped, to preserve the data you need volumes. In this guide we suppose that we have a hard drive mounted at `/data`.

* Create the needed folders
  ```bash
  sudo mkdir /data/ex_nvr
  cd /data/ex_nvr
  sudo mkdir database recordings cert
  ```

* Copy the certificates (needed for https) to the `cert` folder
  ```bash
  sudo cp <path-to-certificate> cert/
  ```
  If you don't plan to use `https`, you can skip this step

* Make the `ex_nvr` user the owner of the *ex_nvr* folder
  ```bash
  sudo chown -R nobody:nogroup /data/ex_nvr
  ```

## Environment variables

The `.env` contains an example of environment variables, you should update those to fit your  needs. Check the description of all the available environment variables in the repo `README.md`

## Run

Run the following command from the folder where the `docker-compose.yml` is located
```bash
docker compose up -d
```

To check if the container is running
```bash
docker compose ps
```

To check the logs run:
```bash
docker compose logs -f --tail 1000
```