import { Socket } from "phoenix"

window.onload = function (_event) {
    const player = document.getElementById("webRtcPlayer")
    const logsComponent = document.getElementById("webRtcLogs")
    const deviceId = player.dataset.device
    const pc = new RTCPeerConnection({ iceServers: [{ urls: 'stun:stun.l.google.com:19302' }] });
    
    const socket = new Socket("/socket", {params: {token: window.token}})
    const channel = socket.channel(`device:${deviceId}`)

    function log(message) {
        if (!logsComponent) {
            return
        }

        logsComponent.innerHTML += "\n\n" + message
        logsComponent.scrollTop = logsComponent.scrollHeight
    }

    channel.join()
        .receive("ok", resp => {log("Joined channel successfully")})
        .receive("error", resp => { 
            log("Unable to join channel: " + resp)
            console.log("Unable to join channel", resp) 
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

    socket.connect()
}