import { Socket } from "phoenix"

window.onload = function (_event) {
    const player = document.getElementById("webRtcPlayer")
    const logsComponent = document.getElementById("webRtcLogs")
    const deviceId = player.dataset.device
    const stream = player.dataset.stream
    const pc = new RTCPeerConnection({ iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] });
    
    const socket = new Socket("/socket", {params: {token: window.token}})
    const channel = socket.channel(`device:${deviceId}`, {stream: stream})

    function log(message) {
        if (!logsComponent) {
            return
        }

        logsComponent.innerHTML += "\n\n" + message
        logsComponent.scrollTop = logsComponent.scrollHeight
    }

    channel.join()
        .receive("ok", resp => {log("Joined channel successfully")})
        .receive("error", reason => { 
            log("Unable to join channel: " + format_join_error(reason))
            alert("could not join channel: " + format_join_error(reason))
            channel.leave()
        })

    channel.on("offer", ({ data }) => {
        log("Received offer: " + data)

        pc.setRemoteDescription(JSON.parse(data))
        pc.createAnswer().then(answer => {
            pc.setLocalDescription(answer)
            channel.push("answer", JSON.stringify(answer))
        })
    })
    
    channel.on("ice_candidate", ({ data }) => {
        log("received new ice candidate: " + data)
        pc.addIceCandidate(JSON.parse(data))
    })

    pc.onicecandidate = (event) => {
        log("new local ice candidate: " + JSON.stringify(event.candidate))
        if (event.candidate) {
            channel.push("ice_candidate", JSON.stringify(event.candidate))
        }
    }
    
    pc.ontrack = (track) => {
        log("received new track: " + JSON.stringify(track))
        player.srcObject = track.streams[0]
    }

    pc.onconnectionstatechange = (event) => {
        if (pc.connectionState == "disconnected") {
            alert("connection closed, refresh browser to retry")
            pc.close()
        }
    }

    socket.connect()
}

function format_join_error(error) {
    switch (error) {
        case "unsupported_codec":
            return "Unsupported Codec"
        case "offline":
            return "Camera Offline"
        case "stream_unavailable":
            return "Unavailable Stream"
        default:
            return "Unknown Error"
    }
}