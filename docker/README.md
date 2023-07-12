# Deploy `ex_nvr` using docker compose

In this guide, we'll deploy `ex_nvr` using `docker compose`. We provide a `docker-compose.yml` and `.env` environment variables files.

Copy the two provided files to your target host and update the files to fit your needs.

## Dependencies

Make sure that `docker` and `docker compose plugin` are installed on your target machine.

## Pulling docker image

The docker images are saved in Github container registry `ghcr.io`. To pull this images you need a personal access token (`PAT`) with `read:packages` scope. Check [this](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens#creating-a-personal-access-token-classic) for details on how to create one.

Once you get your `PAT`, you can login to `ghcr.io`
```bash
docker login ghcr.io
```

Provide your github username and the `PAT` to login. Once this step is finished the host will be able to pull docker images from `ghcr.io`.

## Which image to use

Currently there's two different tags available for `ex_nvr` images, `v*` and `v*-armv7` where `*` represent a version number (e.g. `0.1.1`), the first is for `arm64/v8` and `amd64` machines and the latter for `arm/v7`.

Update `docker-compose.yml` file to use the appropriate image.

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