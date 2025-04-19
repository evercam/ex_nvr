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
  - [HEVC (H265) Support](#hevc-h265-support)
  - [Features](#features)
  - [Project Structure](#project-structure)

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
| EXNVR_DOWNLOAD_DIR | The directory where to save temporary downloaded footages. Defaults to: `/tmp/ex_nvr_downloads` (`/data/ex_nvr/downloads` in nerves image) <br/><br/> Due to the underlying libraries, the created footages may accumulate over time, it's safe to clean this directory from time to time. |
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
| ENABLE_REVERSE_PROXY | Enable reverse proxy. All endpoint calls to a path that starts with `/service/{ipv4}` will be proxied to `http://{ipv4}`. `ipv4` is a valid private ip address. Defaults to: `false` |
| EXNVR_REMOTE_SERVER_URI | The remote server where to send system status. It should be a websocket uri `ws://` or `wss://` |
| EXNVR_REMOTE_SERVER_TOKEN | A token that will be used for authentication for the websocket connection, it'll be send as a query params with `token` name |

## WebRTC

### WebRTC Configuration

| **Env variable** | **description** |
|------------------|-----------------|
| EXNVR_ICE_SERVERS | Ice and turn servers to use as a json object. Default to: `[{\"urls\":\"stun:stun.l.google.com:19302\"}]` |

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

## HEVC (H265) Support

H265 is a an efficient video encoding that promises 50% bitrate gain with the same quality as in H264. This makes it ideal for video storage. Many modern IP cameras support H265 by default. However due to licensing and patents, adoption by browsers is still minimal or not available at all.

When using `ex_nvr` to record H265, no transcoding is done, so streaming from `ex_nvr` (e.g. `hls` or `webrtc`) will give h265 stream, so viewing it depends on the browser support (browser support for `hevc` in `hls` is lacking and it's more in the case of `webrtc`).

## Features

The main feature of this project is to store video streams retrieved from `devices` to local file system and allow users to stream back those recorded videos.  

* **Devices**: read video streams from
   - [x] IP Cameras
   - [ ] USB / Webcams
   - [ ] Raspberry Pi Cameras
   - [x] Plain RTSP stream
   - [x] File Upload

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
   - [x] WebRTC
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


## Project Structure

The project is in a `poncho` style, it consists of the following (sub)projects:

   * `rtsp` - Contains the code needed to connect to cameras via `RTSP` and parsing `RTP` packets.
   * `ui` - Contains the core logic of `ex_nvr` and a live view app.
   * `nerves_fw` - Contains nerves firmware image. Check [here](/nerves_fw/README.md)
