// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"
import createTimeline, { updateTimelineSegments } from "./timeline"
import "flowbite/dist/flowbite.phoenix"
import Hls from "hls.js"

const MANIFEST_LOAD_TIMEOUT = 60_000

let Hooks = {
    Timeline: {
        mounted() {
            createTimeline(this.el)
            window.TimelineHook = this
        },
        updated() {
            updateTimelineSegments(this.el)
        },
    },
    DateWithTimeZone: {
        mounted() {
            let dt = new Date(this.el.textContent.trim());
            this.el.textContent = 
            dt.toLocaleString("UTC", {
                timeZone: this.el.dataset.timezone, 
                year: "numeric",
                month: "short",
                day: "2-digit",
                hour: "2-digit",
                minute: "2-digit",
                second: "numeric",
                fractionalSecondDigits: 3,
                hourCycle: "h23"
            });
            this.el.classList.remove("invisible")
        }
    }
}

let csrfToken = document
    .querySelector("meta[name='csrf-token']")
    .getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
    params: { _csrf_token: csrfToken },
    hooks: Hooks,
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300))
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

function initDarkMode() {
    document.documentElement.classList.add("dark")
}

downloadRecording = (recording_file, device_id) => {
    var url = "http://"+window.location.host+"/api/devices/"+device_id+"/recordings/"+recording_file+"/blob"
    var headers = new Headers();
    headers.append("Content-Type", "video/mp4");

    var reqOptions = {
        method: 'GET',
        headers: headers
    }

    fetch(url, reqOptions)
    .then(res => res.blob()).then(file => {
        let tempUrl = URL.createObjectURL(file);
        const aTag = document.createElement("a");
        aTag.href = tempUrl;
        aTag.download = recording_file;
        document.body.appendChild(aTag);
        aTag.click();
        URL.revokeObjectURL(tempUrl);
        aTag.remove();
    }).catch(() => {
        alert("Failed to download file!");
    });
    
}

startStreaming = (src, poster_url) => {
    var video = document.getElementById("live-video")
    if (video != null && Hls.isSupported()) {
        if (window.hls) {
            window.hls.destroy()
        }

        if (poster_url != null) {
            video.poster = poster_url
        }

        window.hls = new Hls({
            manifestLoadingTimeOut: MANIFEST_LOAD_TIMEOUT,
        })
        window.hls.loadSource(src)
        window.hls.attachMedia(video)

        window.hls.on(Hls.Events.BUFFER_CREATED, (_) => {
            let loader = document.getElementById("loader")
            loader.classList.add("invisible")
        })
    }
}

window.addEventListener("phx:stream", (e) => {
    startStreaming(e.detail.src, e.detail.poster)
})

window.addEventListener("phx:js-exec", ({ detail }) => {
    document.querySelectorAll(detail.to).forEach((el) => {
        liveSocket.execJS(el, el.getAttribute(detail.attr))
    })
})

window.addEventListener("phx:download-recording", (e) => {
    downloadRecording(e.detail.recording_file, e.detail.device_id)
})

initDarkMode()
