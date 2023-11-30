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
import { renderVueComponent } from "./vue-wrapper"
import { ETimeline } from "@evercam/ui"

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
    VueTimeline: {
        vueApp: undefined,

        mounted() {
            const el = this.el.getElementsByClassName("timeline")[0]
            this.vueApp = renderVueComponent({
                el: el,
                component: ETimeline,
                props: {
                    eventsGroups: {
                        Recordings: {
                            label: "Recordings",
                            color: "#FF5733",
                            events: []
                        },
                        Motions: {
                            label: "Motions",
                            color: "#007BFF",
                            events: []
                        }
                    },
                    dark: true
                },
                events: {
                    "date-clicked": (d) => this.dateClicked(d)
                }
            })

            window.VueTimelineHook = this
        },
        dateClicked(d) {
            const selectedDate = new Date(d).getTime()
            const result = this.vueApp?.$children[0].eventsGroups.Recordings.events.reduce(
                (acc, value) => acc || (value.startDate <= selectedDate && selectedDate <= value.endDate),
                false
            )
            if (result) {
                console.log("In")
                this.pushEvent("datetime", {
                    value: selectedDate,
                })
            }
        },
        update(events) {
            if (this.vueApp) {
                this.vueApp.$children[0].eventsGroups = events
            }
        },
        destroyed() {
            this.vueApp?.$destroy()
            this.vueApp = undefined
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

drawRois = (rois) => {
    const video = document.getElementById("live-video")
    const canvas = document.getElementById("video-overlay")
    const ctx = canvas.getContext('2d')
    ctx.clearRect(0, 0, canvas.width, canvas.height)

    rois.forEach(function({dimentions}) {
        ctx.lineWidth = 0.4
        ctx.strokeStyle = "red"
        ctx.strokeRect(
            dimentions.x * canvas.width / video.videoWidth, 
            dimentions.y * canvas.height / video.videoHeight, 
            dimentions.width * canvas.width / video.videoWidth, 
            dimentions.height * canvas.height / video.videoHeight
        )
    })
}

window.addEventListener("phx:stream", (e) => {
    startStreaming(e.detail.src, e.detail.poster)
})

window.addEventListener("phx:motion", (e) => {
    drawRois(e.detail.motions)
})

window.addEventListener("phx:update-timeline", (e) => {
    window.VueTimelineHook?.update(e.detail.events)
})

window.addEventListener("phx:js-exec", ({ detail }) => {
    document.querySelectorAll(detail.to).forEach((el) => {
        liveSocket.execJS(el, el.getAttribute(detail.attr))
    })
})

toggleDeviceConfigInputs = (event) => {
    event.preventDefault()
    var selectElement = document.getElementById("device_type");
    var ipConfigInputs = document.getElementById("ip_config_inputs");
    var ipStreamUriInput = document.getElementById("config_stream_uri")
    var fileConfigInputs = document.getElementById("file_config_inputs");
    var fileLocationInput = document.getElementById("config_file_location")
    
    if (selectElement.value === "ip") {
        ipConfigInputs.classList.remove("hidden");
        ipConfigInputs.required == true

        fileConfigInputs.classList.add("hidden");
        fileLocationInput.required = false
    } else if (selectElement.value === "file") {
        ipConfigInputs.classList.add("hidden");
        
        ipStreamUriInput.required = false

        fileConfigInputs.classList.remove("hidden");
        fileConfigInputs.required = true
    }
}

window.addEventListener("phx:toggle-device-config-inputs", toggleDeviceConfigInputs)

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
