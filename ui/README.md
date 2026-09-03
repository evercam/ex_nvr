# ExNVR UI

ExNVR UI is the public-facing web app + REST API for the ExNVR project.

<div>
<img src="https://github.com/user-attachments/assets/efd39cea-e922-4e05-a293-ffe2da00fb1c" width="550">
</div>

## Components

* A web UI made with **[Phoenix](https://www.phoenixframework.org/)** **[LiveView](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html)**
* An **[SQLite](https://www.sqlite.org/)** Database.
* A REST API.

## Features

* Live video streaming via **[HLS](https://en.wikipedia.org/wiki/HTTP_Live_Streaming)** and **[WebRTC](https://en.wikipedia.org/wiki/WebRTC)** protocols.
* Recordings management (scheduling, download, playback)
* Camera discovery via the **[ONVIF](https://en.wikipedia.org/wiki/ONVIF)** protocol + management (adding, configuring, and monitoring IP cameras).
* Remote storage configuration for cloud backup of recordings
* **[REST API](https://evercam.github.io/ex_nvr/)** providing access to recordings; HLS streaming; devices: system status...etc
* Gathering metrics about solar charger controller (victron mppt) / CPU / Memory
* Tracking AI Events like License Plate Recognition (LPR)

---

# Development

To run the dev server for ExNVR UI, there are two options

## With Docker

TODO

---

## Without Docker

### Prerequisites

* Elixir v1.17.x (specified in .tool-versions)
* Erlang v27.x (specified in .tool-versions)
* Node.js v23.x (specified in .tool-versions)
* FFmpeg

### Setup

1. **Run the setup command**

```
cd ui
mix setup
```

This will run the setup command defined in ui/mix.exs and will install the Elixir dependencies then setup and build the frontend using NPM.


2. **Create the database**

```
mix ecto.migrate
```

This will run the SQL migrations defined in ui/priv/repo/migrations/* and create all the needed tables

3. **Start the Phoenix server**

```
mix phx.server
```

This will start the Phoenix server and run the pipeline defined in `ui/lib/ex_nvr_web/application.ex`, using the config defined in `ui/config/runtime.exs`, which will, among other things:
* Create the needed directories
* Create the admin user


4. **Access the web UI and login 🎉**

Now the app can be accessed on **[http://localhost:4000](http://localhost:4000/)** and you can use the default admin user dev logins:
* **Username**: admin@localhost
* **Password**: P@ssw0rd

---

## Connecting a device

### IP Camera

If you have an IP camera connected on your local network, you can either:

**A- Using ONVIF discovery**
1. Go to the web UI -> ONVIF Discovery
2. Click "Discover devices" 
3. Add the device (on the right panel) 
4. Verify the details and submit.

**B- Add it manually**
1. Go to the web UI -> Devices -> Add device
2. Fill the form for your camera and submit

---

### Webcam + RTSP Server

If you don't have an IP camera, but need to debug ex_nvr locally, you can setup an RTSP server locally, and stream the output from your webcam.

There's a few ways to do this:

**A- Using MediaMTX**
1. Download MediaMTX and start the server
2. Use FFmpeg to stream the webcam live video to the RTSP server

> **Tip**: You can use **[this bash script](https://gist.github.com/halimb/171918320492bbb3f0b381f972d56203)** to complete the steps above.
> It will start an RTSP server streaming your first connected webcam on **rtsp://localhost:8554/webcam**

<div>
<img src="https://github.com/user-attachments/assets/f918b0e7-9f30-4e6c-963b-e2a18b710af4" width="550">
<br>
</div>

3. Once the stream is configured, go to **ExNVR UI -> Devices -> Add Device** and fill the form with mock data, while providing the RTSP stream URL created above ( **rtsp://localhost:8554/webcam** ) and leave the username / password fields empty

If you wish to create a **substream** with different configs, you can edit the script and MediaMTX config to start a second or third steam.

<div>
<img src="https://github.com/user-attachments/assets/1a5a365e-96e1-4623-9b24-ffee15e94171" width="550">
<br>
</div>

4. Select a storage partition

> **Note**: Make sure the current user has enough privileges to write to that partition.
> If you don't wish to write to your disk directly, you can always create a virtual hard disk (**[See example](https://smarttech101.com/how-to-create-and-use-virtual-hard-disk-in-linux)**)

<div>
<img src="https://github.com/user-attachments/assets/39fc1e13-d751-45bc-82ff-10b52a53533c" width="550">
<br>
</div>


5. Submit and confirm that the device is recording

<div>
<img src="https://github.com/user-attachments/assets/761f29ef-0fe7-47a2-a29b-59df01a39b01" width="550">
<br>
</div>


6. The dashboard homepage should now show the live video coming from the webcam

<div>
<img src="https://github.com/user-attachments/assets/ef7c441e-76c7-4395-bdbf-470d074e389c" width="550">
<br>
</div>

