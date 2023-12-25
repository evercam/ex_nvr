import { Socket } from "phoenix"
import { WebRTCEndpoint } from "@jellyfish-dev/membrane-webrtc-js"

function getWebSocketEndpoint() {
    const protocol = window.location.protocol === 'https:' ? 'wss://' : 'ws://'
    const hostname = window.location.hostname
    const port = window.location.port ? `:${window.location.port}` : ''
    
    return `${protocol}${hostname}${port}`
}

window.onload = function (_event) {
    const player = document.getElementById("webRtcPlayer")
    const deviceId = player.dataset.device
    const webrtc = new WebRTCEndpoint()
    
    const socket = new Socket(getWebSocketEndpoint() + "/socket", {params: {}})
    const channel = socket.channel(`device:${deviceId}`)

    channel.on("media_event", ({ data }) => {
        console.log("Received event from channel: ", data)
        webrtc.receiveMediaEvent(data)
    })

    channel.join()
        .receive("ok", resp => {
            console.log("Joined successfully: ", resp)

            // WebRTC
            webrtc.on("connected", (endpoint_id) => {
                console.log("Peer connected successfully: ", endpoint_id)
            })

            webrtc.on("connectionError", (message) => {
                console.log("Unable to connect peer: ", message)
            })
            
            webrtc.on("sendMediaEvent", event => {
                console.log("Peer will send media event: ", event)
                channel.push("media_event", event)
            })

            webrtc.on("trackReady", (track_context) => {
                console.log("Track is ready: ", track_context.stream)
                // let video = document.createElement("video")
                player.srcObject = track_context.stream
            })

            webrtc.connect({displayName: "webrtc"})
        })
        .receive("error", resp => {console.log("Unable to join: ", resp)})

    socket.connect()
}