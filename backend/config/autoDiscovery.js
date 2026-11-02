const dgram = require("dgram");
const os = require("os");

const DISCOVERY_PORT = 38888;
let udpServer = null;

function getActiveLocalIp() {
    const ifaces = os.networkInterfaces();
    // Prioritize Wi-Fi or primary non-virtual adapters
    for (const name in ifaces) {
        for (const iface of ifaces[name]) {
            if (iface.family === "IPv4" && !iface.internal) {
                const lowerName = name.toLowerCase();
                if (
                    !lowerName.includes("virtual") &&
                    !lowerName.includes("vbox") &&
                    !lowerName.includes("wsl") &&
                    !iface.address.startsWith("192.168.56.")
                ) {
                    return iface.address;
                }
            }
        }
    }
    // Fallback to any external IPv4
    for (const name in ifaces) {
        for (const iface of ifaces[name]) {
            if (iface.family === "IPv4" && !iface.internal) {
                return iface.address;
            }
        }
    }
    return "127.0.0.1";
}

function startAutoDiscoveryServer(httpPort = 3000) {
    if (udpServer) return;

    udpServer = dgram.createSocket("udp4");

    udpServer.on("message", (msg, rinfo) => {
        const text = msg.toString().trim();
        if (text === "REBYTE_DISCOVERY_PING" || text.includes("REBYTE")) {
            const currentIp = getActiveLocalIp();
            const responsePayload = JSON.stringify({
                app: "ReByte",
                ip: currentIp,
                port: httpPort,
                url: `http://${currentIp}:${httpPort}`
            });

            udpServer.send(responsePayload, rinfo.port, rinfo.address, err => {
                if (err) console.error("Error sending discovery response:", err);
            });
        }
    });

    udpServer.on("error", err => {
        console.warn("Discovery server error:", err.message);
    });

    try {
        udpServer.bind(DISCOVERY_PORT, "0.0.0.0", () => {
            const activeIp = getActiveLocalIp();
            console.log(`📡 Auto-Discovery Service running on UDP ${DISCOVERY_PORT} (Serving IP: ${activeIp}:${httpPort})`);
        });
    } catch (e) {
        console.warn("Could not bind UDP discovery port:", e.message);
    }
}

module.exports = { startAutoDiscoveryServer, getActiveLocalIp };

