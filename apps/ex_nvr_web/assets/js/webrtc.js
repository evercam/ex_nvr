import { Socket } from "phoenix"
import { WebRTCEndpoint } from "@jellyfish-dev/membrane-webrtc-js"

window.onload = function (_event) {
    const player = document.getElementById("webRtcPlayer")
    const logsComponent = document.getElementById("webRtcLogs")
    const deviceId = player.dataset.device
    const webrtc = new WebRTCEndpoint()
    
    const socket = new Socket("/socket", {params: {}})
    const channel = socket.channel(`device:${deviceId}`)

    function log(message) {
        if (!logsComponent) {
            return
        }

        logsComponent.innerHTML += "\n" + message
        logsComponent.scrollTop = logsComponent.scrollHeight
    }

    channel.on("media_event", ({ data }) => {
        log("Received event from channel: \n", data)
        webrtc.receiveMediaEvent(data)
    })

    channel.join()
        .receive("ok", resp => {
            log("Joined successfully: ", resp)

            // WebRTC
            webrtc.on("connected", (endpoint_id) => {
                log("Peer connected successfully: \n" + endpoint_id)
            })

            webrtc.on("connectionError", (message) => {
                log("Unable to connect peer: \n" + message)
            })
            
            webrtc.on("sendMediaEvent", event => {
                log("Peer will send media event: \n" + event)
                channel.push("media_event", event)
            })

            webrtc.on("trackReady", (track_context) => {
                log("Track is ready: \n" + track_context.stream)
                player.srcObject = track_context.stream
            })

            webrtc.connect({displayName: "webrtc"})
        })
        .receive("error", resp => {log("Unable to join: \n" + resp)})

    socket.connect()
}