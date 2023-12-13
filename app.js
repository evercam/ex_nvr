const { Socket } = require('phoenix')
const { WebRTCEndpoint } = require('@jellyfish-dev/membrane-webrtc-js')

let webrtc = new WebRTCEndpoint()
// let socket = new Socket("wss://wg4.evercam.io:20931/socket", {params: {access_token: "huxWQ0iprWAWrPaalS5tTasZW_tSZGFo-3e98BNXpE0="}})
let socket = new Socket("ws://localhost:4000/socket", {params: {access_token: "huxWQ0iprWAWrPaalS5tTasZW_tSZGFo-3e98BNXpE0="}})
let channel = socket.channel("device:36f25d24-93f4-424e-860b-1e8e14d13d65", {})

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
            console.log("Track is ready: ", track_context)
            // let video = document.createElement("video")

            let video = document.getElementById("live-view")
            console.log(video)
            video.srcObject = track_context.stream
        })

        webrtc.connect({displayName: "Dahmane"})
    })
    .receive("error", resp => {console.log("Unable to join: ", resp)})

socket.connect()
