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
    VideoPopup: {
        mounted() {
            this.el.addEventListener("click", this.showPopup);
        },
        showPopup(event) {
            event.preventDefault();
            const popupContainer = document.getElementById("popup-container");
            const videoElement = popupContainer.querySelector("video");
            const videoUrl = event.currentTarget.getAttribute("phx-value-url");
            videoElement.src = videoUrl;
            
            // Display the popup container
            popupContainer.classList.remove("hidden");
            videoElement.play();
        },
      },      
    Timeline: {
        mounted() {
            createTimeline(this.el)
            window.TimelineHook = this
        },
        updated() {
            updateTimelineSegments(this.el)
        },
    },
    toggleConfigInputs: {
        mounted() {
            this.toggleInputs();
            this.el.addEventListener("change", this.toggleInputs);
        },
        updated() {
            this.toggleInputs();
        },
        toggleInputs(event) {
            var selectElement = document.getElementById("device_type");
            var ipConfigInputs = document.getElementById("ip_config_inputs");
            var ipStreamUriInput = document.getElementById("config_stream_uri")

            var fileConfigInputs = document.getElementById("file_config_inputs");
            var fileLocationInput = document.getElementById("config_file_location")

            var credentialsInputs = document.getElementById("credentials_inputs")
            
            if (selectElement.value === "IP") {
                ipConfigInputs.classList.remove("hidden");
                credentialsInputs.classList.remove("hidden");

                fileConfigInputs.classList.add("hidden");
                fileLocationInput.required = false
            } else if (selectElement.value === "FILE") {
                ipConfigInputs.classList.add("hidden");
                credentialsInputs.classList.add("hidden");
                
                ipStreamUriInput.required = false

                fileConfigInputs.classList.remove("hidden");
            }
        },
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

initDarkMode()
