# ExNVR

NVR (Network Video Recorder) for Elixir using [Membrane Framework](https://github.com/membraneframework)

![ExNVR dashboard](/screenshots/ex_nvr.png)

## Contents
- [ExNVR](#exnvr)
  - [Contents](#contents)
  - [Installation](#installation)
    - [Docker](#docker)
      - [Arm/v7](#armv7)
    - [Releases](#releases)
  - [Environment Variables](#environment-variables)
  - [WebRTC](#webrtc)
    - [WebRTC Configuration](#webrtc-configuration)
    - [Page URL](#page-url)
    - [Embedding](#embedding)
  - [Features](#features)

## Installation

### Docker

To get started with `ex_nvr` it's preferable and easy to run a docker image:
```bash
docker run --rm -it -p 4000:4000 --env-file .env ghcr.io/evercam/ex_nvr:latest
```

Or create a new image using the Dockerfile. Run the following command from the root folder of the project
```bash
docker build -t ex_nvr:custom .
```

This will create an image `ex_nvr` with `custom` tag. To run it, issue this command:
```bash
docker run --rm -it -p 4000:4000 --env-file .env ex_nvr:custom
```

#### Arm/v7
There's currently no automated docker build for `arm/v7` since building the image using `buildx` and `Qemu` take ages to complete,
the workaround is to build the image on the target host itself

```bash
docker build -t ex_nvr:0.6.0 -f Dockerfile-armv7 .
```

### Releases

Starting from `v0.6.0`, there are elixir releases for `GNU/Linux` and debian packages available as [release assets](https://github.com/evercam/ex_nvr/releases).

You can download the tar file and uncompress it. cd to the decompressed directory and then run:
```bash
sudo ./run
```

The `sudo` is needed to create the database as the default location is `/var/lib/ex_nvr` which is not accessible to not-root users by default. If you want to run it as the current user, either:
* Update the `DATABASE_PATH` env variable in the `env.sh` file in `releases/<version>` to point to another location.
* Or create the `/var/lib/ex_nvr` folder and make it owned by the current user `sudo chown $UID:$GID /var/lib/ex_nvr`

For debian packages, just download the package and run:
```bash
sudo dpkg -i <package name>
```

This will install `ex_nvr` as a `systemd` service under the name `ex_nvr`. To run it issue the command
```bash
sudo systemctl start ex_nvr.service
```

To start it on boot
```bash
sudo systemctl enable ex_nvr.service
```

To delete the package, first stop the service and then run `dpkg` to delete it
```bash
sudo systemctl stop ex_nvr.service
sudo systemctl disable ex_nvr.service
sudo dpkg -P ex-nvr
```

## Environment Variables

If you want to configure some aspects of `ex_nvr`, you can set the following environment variables:

| **Env variable** | **description** |
|------------------|-----------------|
| DATABASE_PATH    | The path where Sqlite database will be created. Defaults to: `/var/lib/ex_nvr/ex_nvr.db` |
| EXNVR_HLS_DIRECTORY | The directory where hls playlists will be stored. Defaults to: `/tmp/hls`. <br/><br/>It is not necessary to expose this folder via volumes since the playlists are deleted each time the user stop streaming.
| EXNVR_ADMIN_USERNAME | The username(email) of the admin user to create on first startup. Defaults to: `admin@localhost`. |
| EXNVR_ADMIN_PASSWORD | The password of the admin user to create on first startup. Defaults to: `P@ssw0rd`. |
| SECRET_KEY_BASE  | A 64 byte key that's used by **Pheonix** to encrypt cookies |
| EXNVR_URL | The `url` to use for generating URLs. The `host` is used as a default value for `check_origin` of the websocket. Defaults to: `http://localhost:4000` |
| EXNVR_CHECK_ORIGIN | if the transport should check the origin of requests when the origin header is present. May be true, false or a list of hosts that are allowed. Defaults to `true`. |
| EXNVR_HTTP_PORT | Http `port`, defaults to: `4000` |
| EXNVR_CORS_ALLOWED_ORIGINS | A space separated allowed origins for `CORS` requests. defaults to: `*` |
| EXNVR_ENABLE_HTTPS | Enable `https`, default: `false` |
| EXNVR_HTTPS_PORT | Https `port`, defaults to: `443` |
| EXNVR_SSL_KEY_PATH | The path to the SSL key. |
| EXNVR_SSL_CERT_PATH | The path to the SSL certificate. |
| EXNVR_JSON_LOGGER | Enable json logging, defaults to: `true` |

## WebRTC

### WebRTC Configuration

| **Env variable** | **description** |
|------------------|-----------------|
| EXTERNAL_IP | The external IP address to which attach the turn server. Defaults to: `127.0.0.1` |
| VIRTUAL_HOST | The TURN server domain name. Defaults to: `localhost` |
| INTEGRATED_TURN_PORT_RANGE | UDP port range to use for WebRTC communication. The number of ports in the range decides the total number of users that can stream at the same time. Defaults to: `30000-30100` |
| INTEGRATED_TURN_TCP_PORT | TCP port of TURN server. Defaults to: `20000` |
| INTEGRATED_TURN_PKEY | Private key to use for TURN server. If not provided, TURN will not handle TLS connections. Defaults to: `nil` |
| INTEGRATED_TURN_CERT | Certificate to use for TURN server. If not provided, TURN will not handle TLS connections. Defaults to: `nil` |

> *Note*
> 
> Actually even if private and certificate files are provided, TURN server will not handle TLS connections. We'll support this in the near future.

### Page URL
You can access the webrtc page using the following url:

```url
http://localhost:4000/webrtc/{device_id}
```

### Embedding
A webrtc player can be embedded in web page by using `iframe`
```html
<iframe width="640" height="480" src="http://localhost:4000/webrtc/device_id?access_token=token" title="ex_nvr" allowfullscreen></iframe>
```

> The `access_token` will eventually expire and must be updated to ensure the proper functioning of the embedded page. We plan to enhance this by introducing the capability to make the page public or generate non-expiring tokens with view privileges. 

## Features

The main feature of this project is to store video streams retrieved from `devices` to local file system and allow users to stream back those recorded videos.  

* **Devices**: read video streams from
   - [x] IP Cameras
   - [ ] USB / Webcams
   - [ ] Raspberry Pi Cameras
   - [x] Plain RTSP stream
   - [x] File Upload (Helpful for debug, benchmarking & demos)

* **Camera Streams**: save and playback
   - [x] Main stream
   - [x] Sub-stream

* **Device Discovery**: discover devices
   - [x] Onvif discovery

* **Video Codecs**: allow storing and streaming videos with following codecs
   - [x] H264
   - [x] H265

* **Streaming**: live view and playback
   - [x] HLS
   - [x] WebRTC (only mainstream, [disabled for H265]([url](https://github.com/evercam/ex_nvr/wiki/h265-Support)))
   - [ ] Webm
   - [ ] RTSP
   - [ ] RTMP

* **Integration**: Integrate with third party software
   - [ ] Web Hooks: Notify external services of new recorded videos
   - [x] Unix-domain Socket: Send snapshots via unix-domain socket
   - [x] API / API documentation

* **Other**: other interesting features
   - [ ] Support audio
   - [x] Support multiple devices in same instance
   - [x] Get snapshot from live/recorded stream
   - [x] Download videos of arbitrary durations
   - [x] Add stats/info about streams (for devs)
   - [ ] Gather metrics
   - [ ] Run machine learning models on video streams (live video / stored footages)
   - [ ] Sync recorded videos to cloud storage
   - [ ] Application for management of multiple NVRs
   - [x] Support HTTPS
