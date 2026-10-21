/**
 * Delivery Tracking Socket.IO Handler
 * Real-time peer-to-peer delivery tracking between delivery staff and customer.
 * 
 * Flow:
 * Staff joins `delivery:<orderID>` -> broadcasts live GPS
 * Customer joins `delivery:<orderID>` -> receives live GPS and moves map marker in real time
 * Delivery marked Completed -> emits `delivery-completed` -> both leave room
 */

// In-memory cache of latest coordinates for active deliveries
// Key: orderID (cleaned) -> { orderID, lat, lng, heading, speed, timestamp }
const activeDeliveryLocations = new Map();

function setupDeliverySocket(io) {
    io.on("connection", (socket) => {
        console.log(`[Socket.IO] New connection established: ${socket.id}`);

        /**
         * Staff or Customer joins a delivery room
         * @param {Object} payload { orderID: string, role: 'staff' | 'customer' }
         */
        socket.on("join-delivery", ({ orderID, role }) => {
            if (!orderID) return;
            const cleanOrderID = String(orderID).replace(/^#/, "").trim();
            const roomName = `delivery:${cleanOrderID}`;

            socket.join(roomName);
            socket.data.room = roomName;
            socket.data.orderID = cleanOrderID;
            socket.data.role = role || "client";
            socket.data.joinedAt = new Date().toISOString();

            console.log(`[Socket.IO] [${role || "User"}] socket ${socket.id} joined room: "${roomName}"`);

            // If a customer joins and staff is already en route, immediately send the last known location
            if (activeDeliveryLocations.has(cleanOrderID)) {
                const latestLocation = activeDeliveryLocations.get(cleanOrderID);
                socket.emit("staff-location-update", latestLocation);
            }
        });

        /**
         * Staff sends real-time GPS location updates to the room
         * @param {Object} payload { orderID: string, lat: number, lng: number, heading: number, speed: number }
         */
        socket.on("send-location", (data) => {
            if (!data || !data.orderID) return;
            const cleanOrderID = String(data.orderID).replace(/^#/, "").trim();
            const roomName = `delivery:${cleanOrderID}`;

            const numericLat = Number(data.lat);
            const numericLng = Number(data.lng);
            const numericHeading = Number(data.heading || 0);
            const numericSpeed = Number(data.speed || 0);

            if (isNaN(numericLat) || isNaN(numericLng)) return;

            const locationPayload = {
                orderID: cleanOrderID,
                lat: numericLat,
                lng: numericLng,
                heading: numericHeading,
                speed: numericSpeed,
                estimatedDistanceKm: data.estimatedDistanceKm != null ? Number(data.estimatedDistanceKm) : null,
                estimatedDurationMinutes: data.estimatedDurationMinutes != null ? Number(data.estimatedDurationMinutes) : null,
                timestamp: Date.now()
            };

            // Cache in memory for any newly joining customer or reconnected client
            activeDeliveryLocations.set(cleanOrderID, locationPayload);

            // Broadcast instantly to all other clients in this specific delivery room (the customer)
            socket.to(roomName).emit("staff-location-update", locationPayload);
        });

        /**
         * Staff marks delivery as completed
         * @param {Object} payload { orderID: string, taskID?: string, proofOfDeliveryUrl?: string }
         */
        socket.on("delivery-completed", (data) => {
            if (!data || !data.orderID) return;
            const cleanOrderID = String(data.orderID).replace(/^#/, "").trim();
            const roomName = `delivery:${cleanOrderID}`;

            console.log(`[Socket.IO] Delivery marked COMPLETED for room: "${roomName}"`);

            // Clear active tracking cache
            activeDeliveryLocations.delete(cleanOrderID);

            // Broadcast final completion status to all participants in the room
            io.to(roomName).emit("delivery-completed", {
                orderID: cleanOrderID,
                status: "Delivered",
                message: "Package has been successfully delivered!",
                completedAt: new Date().toISOString(),
                proofOfDeliveryUrl: data.proofOfDeliveryUrl || null
            });
        });

        /**
         * Client leaves the delivery room
         * @param {Object} payload { orderID: string }
         */
        socket.on("leave-delivery", ({ orderID }) => {
            if (!orderID) return;
            const cleanOrderID = String(orderID).replace(/^#/, "").trim();
            const roomName = `delivery:${cleanOrderID}`;
            socket.leave(roomName);
            console.log(`[Socket.IO] Socket ${socket.id} left room: "${roomName}"`);
        });

        socket.on("disconnect", () => {
            console.log(`[Socket.IO] Socket disconnected: ${socket.id}`);
        });
    });
}

/**
 * Inspect active delivery rooms, participants, and real-time location status
 * @param {import("socket.io").Server} io
 */
function getDeliveryRoomsStatus(io) {
    if (!io || !io.sockets || !io.sockets.adapter) {
        return { activeRoomsCount: 0, totalConnectedSockets: 0, rooms: [] };
    }

    const rooms = [];
    const adapterRooms = io.sockets.adapter.rooms;

    for (const [roomName, socketIds] of adapterRooms.entries()) {
        if (roomName.startsWith("delivery:")) {
            const orderID = roomName.replace("delivery:", "");
            const participants = [];

            for (const sId of socketIds) {
                const s = io.sockets.sockets.get(sId);
                participants.push({
                    socketId: sId,
                    role: s?.data?.role || "unknown",
                    joinedAt: s?.data?.joinedAt || null
                });
            }

            const location = activeDeliveryLocations.get(orderID) || null;

            rooms.push({
                room: roomName,
                orderID,
                participantCount: socketIds.size,
                staffCount: participants.filter(p => p.role === "staff").length,
                customerCount: participants.filter(p => p.role === "customer").length,
                participants,
                location: location ? {
                    lat: location.lat,
                    lng: location.lng,
                    heading: location.heading,
                    speed: location.speed,
                    updatedAt: new Date(location.timestamp).toISOString(),
                    ageSeconds: Math.round((Date.now() - location.timestamp) / 1000)
                } : null
            });
        }
    }

    return {
        activeRoomsCount: rooms.length,
        totalConnectedSockets: io.sockets.sockets.size,
        rooms
    };
}

module.exports = {
    setupDeliverySocket,
    activeDeliveryLocations,
    getDeliveryRoomsStatus
};
