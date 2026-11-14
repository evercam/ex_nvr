# Deploy `ex_nvr` using docker compose

In this guide, we'll deploy `ex_nvr` using `docker compose`. We provide a `docker-compose.yml` and `.env` environment variables files.

Copy the two provided files to your target host and update the files to fit your needs.

## Dependencies

Make sure that `docker` and `docker compose plugin` are installed on your target machine.

See how to install docker [here](https://docs.docker.com/engine/install/)

## Pulling docker image

The docker images are saved in Github container registry `ghcr.io` and publicly available.

```bash
docker pull ghcr.io/evercam/ex_nvr:latest
```

## HTTPS

If `https` is desired, we need to provide an SSL certificate: a public and private key. Generating this files is out of the scope of this guide. However, there's many ways to generate this certificates, like self signed certificates (not recommended for production) or using a tool like [`let's encrypt`](https://letsencrypt.org/).

In this guide, we assume the files are called `certificate.key` for the key, and `certificate.crt` for the certificate.

## Prepare volumes

By default any data written to a docker container will be lost when the container is stopped, to preserve the data you need volumes. We suppose that we have a hard drive mounted at `/media/hdd`.

* Create the database and cert folders
  ```bash
  sudo mkdir /media/hdd
  cd /media/hdd/ex_nvr
  sudo mkdir database cert
  ```

* Copy the certificates (needed for https) to the `cert` folder
  ```bash
  sudo cp <path-to-certificate> cert/
  ```
  If you don't plan to use `https`, you can skip this step

* Make the `ex_nvr` the owner of the */data* folder
  ```bash
  sudo chown -R nobody:nogroup /media/hdd/ex_nvr
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