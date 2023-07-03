# ExNVR

NVR (Network Video Recorder) for Elixir using [Membrane Framework](https://github.com/membraneframework)

## Installation

To get started with `ex_nvr` it's preferrable and easy to run a docker image:
```bash
docker run --rm -it -p 4000:4000 --env-file .env ghcr.io/evercam/ex_nvr:latest
```

Or create a new image using the Dockerfile. Run the following command from the root folder of the project
```bash
docker build --build-arg BASE_IMAGE="base_image" -t ex_nvr:custom .
```
on jetson replace base_image with "hexpm/elixir:1.14.3-erlang-25.2.3-alpine-3.17.0"
on raspberry pi replace the base_image with "arm32v7/elixir:1.14-otp-25-alpine as build"

This will create an image `ex_nvr` with `custom` tag. To run it, issue this command:
```bash
docker run --rm -it -p 4000:4000 --env-file .env ex_nvr:custom
```

Note that this command needs some environment variables defined in the `.env` file. The list of environment 
variables needed to configure `ex_nvr` are:

| **Env variable** | **descritpion** |
|------------------|-----------------|
| DATABASE_PATH    | The path where Sqlite database will be created. |
| EXNVR_RECORDING_DIRECTORY | The directory where video footages will be stored |
| EXNVR_HLS_DIRECTORY | The directory where hls playlists will be stored. Defaults to: `./data/hls`. <br/><br/>It is not necessary to expose this folder via volumes since the playlists are deleted each time the user stop streaming.
| EXNVR_ADMIN_USERNAME | The username(email) of the admin user to create on first startup. Defaults to: `admin@localhost`. |
| EXNVR_ADMIN_PASSWORD | The password of the admin user to create on first startup. Defaults to: `P@ssw0rd`. |
| SECRET_KEY_BASE  | A 64 byte key that's used by **Pheonix** to encrypt cookies |
| EXNVR_URL | The `url` to use for generating URLs and as a default value for `check_origins` of the websocket. Defaults to: `http://localhost:4000` |
| EXNVR_HTTP_PORT | Http `port`, defaults to: `4000` |
| EXNVR_CORS_ALLOWED_ORIGINS | A space separated allowed origins for `CORS` requests. defaults to: `*` |
| EXNVR_ENABLE_HTTPS | Enable `https`, default: `false` |
| EXNVR_HTTPS_PORT | Https `port`, defaults to: `443` |
| EXNVR_SSL_KEY_PATH | The path to the SSL key. |
| EXNVR_SSL_CERT_PATH | The path to the SSL certificate. |

## Features

The main feature of this project is to store video streams retrieved from `devices` to local file system and allow users to stream back those recorded videos.  

 * **Devices**: read video streams from
   - [x] IP Cameras
   - [ ] USB / Webcams
   - [ ] Raspberry Cameras
   - [x] Plain RTSP stream

* **Camera Streams**: save and playback
   - [x] Main stream
   - [ ] Sub-stream

* **Device Discovery**: discover devices
   - [ ] Onvif discovery

* **Video Codecs**: allow storing and streaming videos with following codecs
   - [x] H264
   - [ ] H265

* **Streaming**: live view and playback
   - [x] HLS
   - [ ] WebRTC
   - [ ] Webm

* **Other**: other interesting features
   - [ ] Support audio
   - [x] Support multiple devices in same instance
   - [ ] Get snapshot from live/recorded stream
   - [ ] Download videos of arbitrary durations
   - [ ] Add stats/info about streams (for devs)
   - [x] API / API documentation
   - [ ] Gather metrics
   - [ ] Run machine learning models on video streams (live video / stored footages)
   - [ ] Sync recorded videos to cloud storage
   - [ ] Notify external services of new recorded videos
   - [ ] Application for management of multiple NVRs
   - [x] Support HTTPS