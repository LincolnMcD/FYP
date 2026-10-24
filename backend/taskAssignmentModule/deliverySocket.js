/**
 * Delivery Tracking Socket.IO Handler
 * Real-time peer-to-peer delivery tracking between delivery staff and customer.
 * 
 * Flow:
 * Staff joins `delivery:<orderID>` -> broadcasts live GPS
 * Customer joins `delivery:<orderID>` -> receives live GPS and moves map marker in real time
 * Delivery marked Completed -> emits `delivery-completed` -> both leave room
 */

const db = require("../config/firebase");

// In-memory cache of latest coordinates for active deliveries
// Key: orderID (cleaned) -> { orderID, lat, lng, heading, speed, timestamp }
const activeDeliveryLocations = new Map();

// Canonicalizes any order, trade-in, task, or appointment ID to a single clean room ID
// e.g. "TSK-TR26102400008" -> "TR26102400008", "#TR26102400008" -> "TR26102400008"
function getCanonicalDeliveryRoomId(rawId) {
    if (!rawId) return "";
    return String(rawId)
        .replace(/^#/, "")
        .replace(/^delivery:/, "")
        .replace(/^TSK-/, "")
        .trim();
}

function setupDeliverySocket(io) {
    io.on("connection", (socket) => {
        console.log(`[Socket.IO] New connection established: ${socket.id}`);

        /**
         * Staff or Customer joins a delivery room (Single Canonical Room)
         * @param {Object} payload { orderID: string, role: 'staff' | 'customer', tradeInRequestID?: string, taskID?: string, appointmentID?: string }
         */
        socket.on("join-delivery", async (payload) => {
            if (!payload) return;
            const rawID = payload.orderID || payload.tradeInRequestID || payload.taskID || payload.appointmentID;
            if (!rawID) return;
            const cleanOrderID = getCanonicalDeliveryRoomId(rawID);
            const role = payload.role;
            const roomName = `delivery:${cleanOrderID}`;

            // Leave any old delivery rooms to ensure exactly ONE room per socket
            for (const r of socket.rooms) {
                if (r.startsWith("delivery:") && r !== roomName) {
                    socket.leave(r);
                }
            }

            socket.join(roomName);
            socket.data.room = roomName;
            socket.data.orderID = cleanOrderID;
            socket.data.role = role || "client";
            socket.data.joinedAt = new Date().toISOString();

            console.log(`[Socket.IO] [${role || "User"}] socket ${socket.id} joined room: "${roomName}"`);

            // Helper to probe active cache
            function getCachedLoc(keys) {
                for (const k of keys) {
                    if (!k) continue;
                    const cleanK = getCanonicalDeliveryRoomId(k);
                    if (activeDeliveryLocations.has(cleanK)) return activeDeliveryLocations.get(cleanK);
                    if (activeDeliveryLocations.has(`TSK-${cleanK}`)) return activeDeliveryLocations.get(`TSK-${cleanK}`);
                }
                return null;
            }

            let latestLocation = getCachedLoc([cleanOrderID, payload.tradeInRequestID, payload.taskID, payload.appointmentID]);

            // If not found in memory, query Firestore for aliases & saved live GPS
            if (!latestLocation && db) {
                try {
                    let relatedTaskData = null;
                    let tSnap = await db.collection("task").doc(`TSK-${cleanOrderID}`).get();
                    if (!tSnap.exists) tSnap = await db.collection("task").doc(cleanOrderID).get();
                    if (tSnap.exists) {
                        relatedTaskData = tSnap.data();
                    } else {
                        const qSnap = await db.collection("task").where("tradeInRequestID", "==", cleanOrderID).limit(1).get();
                        if (!qSnap.empty) {
                            relatedTaskData = qSnap.docs[0].data();
                        } else {
                            const oSnap = await db.collection("task").where("orderID", "==", cleanOrderID).limit(1).get();
                            if (!oSnap.empty) {
                                relatedTaskData = oSnap.docs[0].data();
                            }
                        }
                    }

                    if (relatedTaskData) {
                        latestLocation = getCachedLoc([
                            cleanOrderID,
                            relatedTaskData.tradeInRequestID,
                            relatedTaskData.appointmentID
                        ]);

                        if (!latestLocation && relatedTaskData.staffLat && relatedTaskData.staffLng) {
                            latestLocation = {
                                orderID: cleanOrderID,
                                lat: Number(relatedTaskData.staffLat),
                                lng: Number(relatedTaskData.staffLng),
                                heading: Number(relatedTaskData.staffHeading || 0),
                                speed: 0,
                                estimatedDistanceKm: relatedTaskData.estimatedDistance || null,
                                estimatedDurationMinutes: relatedTaskData.estimatedDuration || null,
                                timestamp: Date.now()
                            };
                            activeDeliveryLocations.set(cleanOrderID, latestLocation);
                        }
                    }

                    if (!latestLocation) {
                        const delSnap = await db.collection("delivery").doc(`DEL-${cleanOrderID}`).get();
                        if (delSnap.exists) {
                            const delData = delSnap.data();
                            if (delData.staffLat && delData.staffLng) {
                                latestLocation = {
                                    orderID: cleanOrderID,
                                    lat: Number(delData.staffLat),
                                    lng: Number(delData.staffLng),
                                    heading: Number(delData.staffHeading || 0),
                                    speed: 0,
                                    estimatedDistanceKm: delData.estimatedDistance || null,
                                    estimatedDurationMinutes: delData.estimatedDuration || null,
                                    timestamp: Date.now()
                                };
                                activeDeliveryLocations.set(cleanOrderID, latestLocation);
                            }
                        }
                    }
                } catch (err) {
                    console.error("[Socket.IO] Error looking up Firestore location for room:", err.message);
                }
            }

            if (latestLocation) {
                socket.emit("staff-location-update", latestLocation);
            }
        });

        /**
         * Staff sends real-time GPS location updates to the single canonical room
         * @param {Object} payload { orderID: string, lat: number, lng: number, heading: number, speed: number, tradeInRequestID?: string, taskID?: string }
         */
        socket.on("send-location", (data) => {
            if (!data) return;
            const rawID = data.orderID || data.tradeInRequestID || data.taskID || data.appointmentID;
            if (!rawID) return;
            const cleanOrderID = getCanonicalDeliveryRoomId(rawID);
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

            // Cache in memory under canonical key and TSK- alias
            activeDeliveryLocations.set(cleanOrderID, locationPayload);
            activeDeliveryLocations.set(`TSK-${cleanOrderID}`, locationPayload);

            // Broadcast to the single canonical room
            socket.to(roomName).emit("staff-location-update", locationPayload);
        });

        /**
         * Staff marks delivery as completed
         * @param {Object} payload { orderID: string, taskID?: string, proofOfDeliveryUrl?: string }
         */
        socket.on("delivery-completed", (data) => {
            if (!data || !data.orderID) return;
            const cleanOrderID = getCanonicalDeliveryRoomId(data.orderID);
            const roomName = `delivery:${cleanOrderID}`;

            console.log(`[Socket.IO] Delivery marked COMPLETED for room: "${roomName}"`);

            // Clear active tracking cache
            activeDeliveryLocations.delete(cleanOrderID);
            activeDeliveryLocations.delete(`TSK-${cleanOrderID}`);

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
            const cleanOrderID = getCanonicalDeliveryRoomId(orderID);
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
            // Filter out any duplicate TSK- rooms if they ever exist
            if (roomName.startsWith("delivery:TSK-")) continue;

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
