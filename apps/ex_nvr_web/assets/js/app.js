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
import "flowbite/dist/flowbite.phoenix"
import Hls from "hls.js"

import Timeline from "../vue/Timeline.vue"
import vueWrapper from "./vueWrapper"

const MANIFEST_LOAD_TIMEOUT = 60_000

let Hooks = {
    DownloadSnapshot: {
        mounted() {
            this.el.addEventListener("click", this.downloadSnapshot);
        },
        downloadSnapshot(event) {
            const player = document.getElementById("live-video");
            var canvas = document.createElement("canvas");

            canvas.width = player.videoWidth;
            canvas.height = player.videoHeight;
            canvas.getContext('2d').drawImage(player, 0, 0, canvas.width, canvas.height);
            
            const dataUri = canvas.toDataURL('image/png');

            const link = document.createElement("a");
            link.style.display = "none";
            link.download = "snapshot.png";
            link.href = dataUri;

            document.body.appendChild(link);
            link.click();

            document.body.removeChild(link);
            canvas.getContext('2d').clearRect(0, 0, canvas.width, canvas.height);
        }

    },
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
    vueTimeLine: {
        mounted() {
            window.TimelineHook = this
            vueWrapper({
                el: this.el,
                component: Timeline,
            })
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

function downloadFile(url) {
    const anchor = document.createElement("a");
    anchor.style.display = "none";
    anchor.href = url;

    document.body.appendChild(anchor);
    anchor.click();

    document.body.removeChild(anchor);
}

window.addEventListener("phx:download-footage", (e) => {
    downloadFile(e.detail.url)
})

initDarkMode()
