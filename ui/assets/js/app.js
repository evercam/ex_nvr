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
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { getHooks } from "live_vue"
import liveVueApp from "../vue"
import topbar from "topbar"
import "flowbite/dist/flowbite.phoenix"
import "../css/app.css"

let Hooks = {
    SwitchDarkMode: {
        mounted() {
            this.el.addEventListener("change", this.switchDarkMode);
        },
        switchDarkMode(event) {
            const lightSwitch = document.getElementById("light-switch")
            if (lightSwitch.checked) {
                document.documentElement.classList.add('dark');
                localStorage.setItem('dark-mode', true);
            } else {
                document.documentElement.classList.remove('dark');
                localStorage.setItem('dark-mode', false);
            }
        }
    },
    ...getHooks(liveVueApp)
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

// Listen for reload-popovers events and re-init the popovers
// phx-loading-xxx events are not triggered by push_patch
// so this is why we listen for this custom event instead
window.addEventListener('phx:reload-popovers', (e) => initPopovers())

window.addEventListener("phx:js-exec", ({ detail }) => {
    document.querySelectorAll(detail.to).forEach((el) => {
        liveSocket.execJS(el, el.getAttribute(detail.attr))
    })
})

window.addEventListener("phx:download-footage", (e) => downloadFile(e.detail.url))

function downloadFile(url) {
    const anchor = document.createElement("a");
    anchor.style.display = "none";
    anchor.href = url;
    anchor.target="_blank"

    document.body.appendChild(anchor);
    anchor.click();

    document.body.removeChild(anchor);
}

(function() {
    const lightSwitch = document.getElementById("light-switch")
    if (localStorage.getItem('dark-mode') === 'true' || (!('dark-mode' in localStorage) && window.matchMedia('(prefers-color-scheme: dark)').matches)) {
        lightSwitch.checked = true;
    } else {
        lightSwitch.checked = false;
    }
})()
