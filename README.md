# ExNVR

NVR (Network Video Recorder) for Elixir using [Membrane Framework](https://github.com/membraneframework)

## Installation

To get started with `ex_nvr` it's preferrable and easy to create a docker image (we don't have built images available right now, but we'll do soon).

Run the following command from the root folder of the project
```bash
docker build -t ex_nvr:0.1.0 .
```

This will create an image `ex_nvr` with `0.1.0` tag. To run it, issue this command:
```bash
docker run --rm -it -p 4000:4000 --env-file .env ex_nvr:0.1.0
```

Note that this command needs some environment variables defined in the `.env` file. The list of environment 
variables needed to configure `ex_nvr` are:

| **Env variable** | **descritpion** |
|------------------|-----------------|
| DATABASE_PATH    | The path where Sqlite database will be created. |
| EXNVR_RECORDING_DIRECTORY | The directory where video footages will be stored |
| EXNVR_HLS_DIRECTORY | The directory where hls playlists will be stored. Default to: `./data/hls`. <br/><br/>It is not necessary to expose this folder via volumes since the playlists are deleted each time the user stop streaming.
| EXNVR_ADMIN_USERNAME | The username(email) of the admin user to create on first startup. Default to: `admin@localhost`. |
| EXNVR_ADMIN_PASSWORD | The password of the admin user to create on first startup. Default to: `P@ssw0rd`. |
| SECRET_KEY_BASE  | A 64 byte key that's used by **Pheonix** to encrypt cookies |
| EXNVR_URL | The `url` to use for generating URLs and as a default value for `check_origins` of the websocket. Default to: `http://localhost:4000` |

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