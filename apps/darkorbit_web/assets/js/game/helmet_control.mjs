import QRCode from "qrcode"
import {chooseHelmetOrigin} from "./helmet_network.mjs"

// The Atlas owns enrollment; the cockpit owns the headset's operating mode.
export class HelmetControl {
  constructor({root, socket, playerId, combatActive}) {
    this.root = root
    this.socket = socket
    this.playerId = playerId
    this.combatActive = combatActive
    this.panel = root.querySelector("#helmet-panel")
    this.status = {paired: false, connected: false, rendering: false}
    this.code = null
    this.open = false
    this.hostEdited = false
  }

  start() {
    if (!this.panel) return this
    this.root.querySelector("#nav-helmet-open")?.addEventListener("click", () => this.openPanel())
    this.root.querySelector("#nav-helmet-close")?.addEventListener("click", () => this.closePanel())
    this.root.querySelector("#helmet-forget")?.addEventListener("click", () => this.forget())
    const host = this.root.querySelector("#helmet-host")
    host?.addEventListener("input", () => { this.hostEdited = true })
    host?.addEventListener("change", () => this.drawQR())
    // Do not offer localhost as a QR destination: a phone cannot reach it.
    if (host) host.value = chooseHelmetOrigin(window.location.origin)

    this.channel = this.socket.channel("helmet:control:" + this.playerId, {})
    this.channel.on("helmet_status", data => this.updateStatus(data))
    this.channel.onError(() => this.message("Helmet link interrupted. Reconnecting…"))
    this.channel.join()
      .receive("ok", reply => {
        this.suggestNetworkHosts(reply.network_hosts || [])
        this.updateStatus(reply.status)
        this.setCombat(this.combatActive)
        if (this.open && !reply.status.paired) this.requestPairing()
      })
      .receive("error", () => this.message("Helmet control channel unavailable."))
    return this
  }

  suggestNetworkHosts(hosts) {
    const address = chooseHelmetOrigin(window.location.origin, hosts)
    const input = this.root.querySelector("#helmet-host")
    if (input && !this.hostEdited) input.value = address
    const options = this.root.querySelector("#helmet-host-candidates")
    if (options) {
      options.replaceChildren()
      for (const hostname of hosts) {
        const origin = chooseHelmetOrigin("http://localhost:4000", [hostname])
        if (!origin) continue
        const candidate = new URL(window.location.origin)
        candidate.hostname = hostname
        const item = document.createElement("option")
        item.value = candidate.origin
        options.appendChild(item)
      }
    }
    if (this.open && this.code) this.drawQR()
  }

  setCombat(active) {
    this.combatActive = Boolean(active)
    if (this.channel?.state === "joined") {
      this.channel.push("set_mode", {mode: active ? "combat" : "standby"})
    }
  }

  openPanel() {
    this.open = true
    this.panel.hidden = false
    this.updateStatus(this.status)
    if (!this.status.paired) this.requestPairing()
  }

  closePanel() {
    if (!this.open) return
    this.open = false
    this.panel.hidden = true
    this.code = null
    this.clearQR()
    if (this.channel?.state === "joined") this.channel.push("cancel_pairing", {})
  }

  requestPairing() {
    if (this.channel?.state !== "joined") {
      this.message("Waiting for the ship connection. Reopen this panel after it connects.")
      return
    }
    this.message("Preparing helmet pairing QR code…")
    this.channel.push("open_pairing", {})
      .receive("ok", ({code}) => {
        if (!this.open) {
          this.channel.push("cancel_pairing", {})
          return
        }
        this.code = code
        this.drawQR()
      })
      .receive("error", ({reason}) => this.message(reason || "Could not open pairing."))
  }

  async drawQR() {
    if (!this.code || !this.open) return
    const host = this.root.querySelector("#helmet-host")?.value.trim().replace(/\/+$/, "")
    const canvas = this.root.querySelector("#helmet-qr")
    if (!/^https?:\/\/[^/]+$/i.test(host)) {
      this.message("No LAN address detected. Enter the laptop IP and port (find it with: hostname -I).")
      return
    }
    try {
      const url = new URL("/helmet", host)
      url.searchParams.set("pair", this.code)
      await QRCode.toCanvas(canvas, url.toString(), {width: 220, margin: 2, errorCorrectionLevel: "M"})
      this.message("Scan with your phone. Pairing stays open until this panel closes.")
    } catch (_error) {
      this.message("Unable to draw QR code. Check the laptop address.")
    }
  }

  clearQR() {
    const canvas = this.root.querySelector("#helmet-qr")
    canvas?.getContext("2d")?.clearRect(0, 0, canvas.width, canvas.height)
  }

  updateStatus(status = {}) {
    this.status = status
    const label = status.rendering ? "SBS ACTIVE" :
      status.connected && status.mode === "combat" ? "CONNECTED / STARTING SBS" :
      status.connected ? "CONNECTED / STANDBY" :
      status.paired ? "PAIRED / OFFLINE" : "NOT PAIRED"
    const cockpit = this.root.querySelector("#cockpit-helmet-status")
    if (cockpit) cockpit.textContent = status.rendering ? "HMD SBS LIVE" :
      status.connected ? "HMD CONNECTED" : status.paired ? "HMD PAIRED" : "HMD UNPAIRED"
    const indicator = this.root.querySelector("#nav-helmet-status")
    if (indicator) indicator.textContent = label
    const current = this.root.querySelector("#helmet-device-status")
    if (current) current.textContent = status.paired ?
      (status.device_name || "Phone headset") + " · " + label : "No helmet paired"
    const paired = this.root.querySelector("#helmet-paired")
    if (paired) paired.hidden = !status.paired
    const unpaired = this.root.querySelector("#helmet-unpaired")
    if (unpaired) unpaired.hidden = Boolean(status.paired)
    if (status.paired) {
      this.code = null
      this.clearQR()
    }
  }

  forget() {
    if (!window.confirm("Forget this helmet? You will need to scan a new QR code to pair again.")) return
    this.channel?.push("forget", {}).receive("ok", () => {
      if (this.open) this.requestPairing()
    })
  }

  message(value) {
    const node = this.root.querySelector("#helmet-pairing-message")
    if (node) node.textContent = value
  }
}
