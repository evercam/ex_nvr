# ExNVR

NVR (Network Video Recorder) for Elixir using [Membrane Framework](https://github.com/membraneframework)

## Roadmap
### v1
- [ ] Ingest RTSP stream and save to disk
- [ ] Transcode RTSP stream to WebRTC to play live stream in browser.
- [ ] API to access snapshots from live or recorded
- [ ] API to access recording clips of any length
- [ ] WebUI to play live stream & browse recordings

### v2
- [ ] Architecture to allow for running ML models with local storage of results 
- [ ] Rules for cloud syncing of metadata, thumbnails & clips
- [ ] Application for management of multiple NVRs

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