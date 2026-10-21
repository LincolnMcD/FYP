const express = require("express");
const router = express.Router();
const db = require("../config/firebase");
const { FieldValue } = require("firebase-admin/firestore");
const cloudinary = require("../config/cloudinary");
const multer = require("multer");
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });
const { assignDeliveryTask } = require("./taskAssignmentService");
const { getDeliveryRoomsStatus } = require("./deliverySocket");

// Helper to stream upload buffer to Cloudinary
function uploadBufferToCloudinary(fileBuffer, folder, filename) {
    return new Promise((resolve, reject) => {
        const uploadStream = cloudinary.uploader.upload_stream(
            {
                folder: folder,
                public_id: filename,
                resource_type: "image",
            },
            (error, result) => {
                if (error) return reject(error);
                resolve(result);
            }
        );
        uploadStream.end(fileBuffer);
    });
}

/**
 * Middleware: Check staff or authenticated user
 */
function requireAuth(req, res, next) {
    next();
}

/**
 * POST /api/task-assignment/assign
 * Manually or automatically trigger task assignment for an order
 */
router.post("/assign", requireAuth, async (req, res) => {
    try {
        const { orderID, addressID, requestedDate } = req.body;
        if (!orderID) {
            return res.status(400).json({ success: false, error: "orderID is required" });
        }

        const result = await assignDeliveryTask({
            orderID,
            addressID,
            requestedDate: requestedDate ? new Date(requestedDate) : new Date()
        });

        return res.json(result);
    } catch (err) {
        console.error("Task assignment error:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

/**
 * GET /api/task-assignment/staff-tasks?staffID=...&email=...
 * Fetch assigned, in-progress, and completed tasks for staff
 */
router.get("/staff-tasks", async (req, res) => {
    try {
        const { staffID, email } = req.query;
        let targetStaffID = staffID;

        // If email provided instead of staffID, look up users collection
        if (!targetStaffID && email) {
            const userSnap = await db.collection("users").where("email", "==", String(email).trim().toLowerCase()).limit(1).get();
            if (!userSnap.empty) {
                targetStaffID = userSnap.docs[0].id;
            }
        }

        if (!targetStaffID) {
            return res.status(400).json({ success: false, error: "staffID or email is required" });
        }

        // 1. Resolve staff details (name) from users collection
        let staffName = "";
        const staffUserDoc = await db.collection("users").doc(targetStaffID).get();
        if (staffUserDoc.exists) {
            staffName = staffUserDoc.data().fullName || staffUserDoc.data().name || "";
        }

        // 2. Query schedule collection for this staff (Source of truth for staff schedule)
        const schedSnap = await db.collection("schedule")
            .where("staffID", "==", targetStaffID)
            .get();

        const tasksList = [];

        for (const sDoc of schedSnap.docs) {
            const schedData = sDoc.data();
            const scheduleID = schedData.scheduleID || sDoc.id;

            // 3. Lookup task by scheduleID
            let taskData = {};
            let taskID = "";
            let orderID = "";

            const tSnap = await db.collection("task").where("scheduleID", "==", scheduleID).limit(1).get();
            if (!tSnap.empty) {
                taskData = tSnap.docs[0].data();
                taskID = taskData.taskID || tSnap.docs[0].id;
                orderID = taskData.orderID || "";
            }

            // Fallback: Check if schedule had orderID (legacy records)
            if (!orderID && schedData.orderID) {
                orderID = schedData.orderID;
            }

            // 4. Fetch Order details
            let items = [];
            let address = {};
            let orderData = null;
            if (orderID) {
                const oDoc = await db.collection("order").doc(orderID).get();
                if (oDoc.exists) {
                    orderData = oDoc.data();
                    if (orderData.addressID) {
                        const aDoc = await db.collection("address").doc(orderData.addressID).get();
                        if (aDoc.exists) address = aDoc.data();
                    }

                    // Also retrieve customer email from users collection if available
                    let customerEmail = address.email || orderData.email || orderData.userEmail || "";
                    if (!customerEmail && orderData.customerID) {
                        const uDoc = await db.collection("users").doc(orderData.customerID).get();
                        if (uDoc.exists) {
                            customerEmail = uDoc.data().email || "";
                        }
                    }
                    orderData.customerEmail = customerEmail;

                    const pIds = Array.isArray(orderData.productIDs) ? orderData.productIDs : [];
                    for (const pid of pIds) {
                        const pDoc = await db.collection("product").doc(pid).get();
                        if (pDoc.exists) {
                            const p = pDoc.data();
                            let brand = p.brand || "";
                            let model = p.model || "";
                            let storage = p.storage || "";
                            let color = p.color || "";
                            let condition = "Good";

                            // If product references a deviceID, fetch precise specs from `devices` collection
                            if (p.deviceID) {
                                const devDoc = await db.collection("devices").doc(p.deviceID).get();
                                if (devDoc.exists) {
                                    const devData = devDoc.data();
                                    brand = brand || devData.brand || "";
                                    model = model || devData.model || "";
                                    storage = storage || devData.storage || "";
                                    color = color || devData.color || "";
                                    if (devData.overallConditionScore) {
                                        condition = devData.overallConditionScore >= 90 ? "Excellent" : (devData.overallConditionScore >= 75 ? "Good" : "Fair");
                                    }
                                }
                            }

                            // If brand or model is still empty, parse from p.description
                            if (!model && p.description) {
                                // e.g. "OnePlus OnePlus 12 (256 GB) - Grade A refurbished..."
                                const parenIdx = p.description.indexOf("(");
                                if (parenIdx > -1) {
                                    model = p.description.substring(0, parenIdx).trim();
                                    const inParen = p.description.substring(parenIdx + 1, p.description.indexOf(")", parenIdx));
                                    if (!storage) storage = inParen.trim();
                                }
                            }

                            items.push({
                                productID: pid,
                                brand,
                                model,
                                storage,
                                color,
                                condition,
                                imageUrl: p.imageUrl || "",
                                description: p.description || ""
                            });
                        }
                    }
                }
            }

            // 5. Fetch Delivery record
            let deliveryData = {};
            if (orderID) {
                const delID = `DEL-${orderID}`;
                const dDoc = await db.collection("delivery").doc(delID).get();
                if (dDoc.exists) {
                    deliveryData = dDoc.data();
                }
            }

            // Ensure exact destination coordinates from address if not present or default
            let finalLat = deliveryData.destinationLat;
            let finalLng = deliveryData.destinationLng;
            if (!finalLat && address.lat) finalLat = Number(address.lat);
            if (!finalLng && address.lng) finalLng = Number(address.lng);
            if (!finalLat && address.latitude) finalLat = Number(address.latitude);
            if (!finalLng && address.longitude) finalLng = Number(address.longitude);

            // If coordinates are default (5.3542, 100.3015) or null, geocode from address text
            if ((!finalLat || finalLat === 5.3542) && address.addressLine) {
                try {
                    const fullAddr = [address.addressLine, address.postcode, address.city, address.state].filter(Boolean).join(", ");
                    const geoRes = await fetch(
                        `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(fullAddr)}&countrycodes=my&limit=1`,
                        { headers: { "User-Agent": "ReByte-App/1.0" } }
                    );
                    if (geoRes.ok) {
                        const geo = await geoRes.json();
                        if (Array.isArray(geo) && geo.length > 0) {
                            finalLat = parseFloat(geo[0].lat);
                            finalLng = parseFloat(geo[0].lon);
                            if (orderID) {
                                db.collection("delivery").doc(`DEL-${orderID}`).update({
                                    destinationLat: finalLat,
                                    destinationLng: finalLng
                                }).catch(() => {});
                            }
                        }
                    }
                } catch (_) {}
            }

            const distNum = taskData.estimatedDistanceinKM !== undefined ? taskData.estimatedDistanceinKM : (parseFloat(taskData.estimatedDistance) || 0);
            const durNum = taskData.estimatedDurationinMinutes !== undefined ? taskData.estimatedDurationinMinutes : (parseInt(taskData.estimatedDuration) || 0);

            tasksList.push({
                scheduleID,
                scheduleDate: schedData.scheduleDate || "",
                scheduleStartTime: schedData.scheduleStartTime || taskData.taskStartTime || "",
                scheduleEndTime: schedData.scheduleEndTime || "",
                scheduleStatus: schedData.scheduleStatus || "assigned",
                taskID,
                taskType: taskData.taskType || "deliver",
                taskStatus: taskData.taskStatus || "Packaging",
                estimatedDistanceinKM: distNum,
                estimatedDurationinMinutes: durNum,
                estimatedDuration: `${durNum} mins`,
                estimatedDistance: `${distNum} km`,
                staffID: targetStaffID,
                staffName: staffName || schedData.staffName || "",
                orderID,
                customerName: address.recipentName || address.recipientName || "Customer",
                customerPhone: address.phoneNumber || "",
                customerEmail: (orderData && orderData.customerEmail) || address.email || (orderData && orderData.email) || "",
                deliveryAddress: [address.addressLine, address.postcode, address.city, address.state].filter(Boolean).join(", "),
                deliveryStatus: deliveryData.deliveryStatus || "ongoing",
                completedAt: taskData.completedAt ? (taskData.completedAt.toDate ? taskData.completedAt.toDate().toISOString() : taskData.completedAt) : (deliveryData.completedAt ? (deliveryData.completedAt.toDate ? deliveryData.completedAt.toDate().toISOString() : deliveryData.completedAt) : null),
                proofOfDeliveryUrl: deliveryData.proofOfDeliveryUrl || taskData.proofOfDeliveryUrl || "",
                destinationLat: finalLat || null,
                destinationLng: finalLng || null,
                items
            });
        }

        // Sort: newest schedule date/time first
        tasksList.sort((a, b) => new Date(b.scheduleStartTime).getTime() - new Date(a.scheduleStartTime).getTime());

        return res.json({
            success: true,
            tasks: tasksList
        });
    } catch (err) {
        console.error("Error fetching staff tasks:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

/**
 * PATCH /api/task-assignment/update-status
 * Update status of task, schedule, and delivery
 */
router.patch("/update-status", async (req, res) => {
    try {
        const { taskID, orderID, scheduleID, status, rejectionReason, rejectionNotes, proofOfDeliveryUrl } = req.body;
        // status can be 'Packaging', 'Shipping' (In Progress), 'Delivered' (Completed), 'Rejected'
        const normalized = String(status || "").trim();
        const isCompleted = normalized === "Delivered" || normalized === "Completed" || normalized === "completed";
        const isTerminated = normalized === "Terminated" || normalized === "terminated";
        const isRejected = normalized === "Rejected" || normalized === "rejected";

        const batch = db.batch();

        if (taskID) {
            const taskUpdate = {
                taskStatus: isTerminated ? "Rejected" : normalized,
                updatedAt: new Date()
            };
            if (isCompleted) {
                taskUpdate.completedAt = FieldValue.serverTimestamp();
            }
            if (proofOfDeliveryUrl) taskUpdate.proofOfDeliveryUrl = proofOfDeliveryUrl;
            if (rejectionReason) taskUpdate.rejectionReason = rejectionReason;
            if (rejectionNotes) taskUpdate.rejectionNotes = rejectionNotes;

            batch.set(db.collection("task").doc(taskID), taskUpdate, { merge: true });
        }

        if (scheduleID) {
            let schedStatus = "assigned";
            if (normalized === "Shipping" || normalized === "In Progress" || normalized === "ongoing") schedStatus = "ongoing";
            if (isCompleted) schedStatus = "completed";
            if (isRejected || isTerminated) schedStatus = "rejected";

            const schedUpdate = {
                scheduleStatus: schedStatus,
                updatedAt: new Date()
            };
            if (isCompleted) {
                schedUpdate.completedAt = FieldValue.serverTimestamp();
            }
            if (isRejected || isTerminated) {
                if (rejectionReason) schedUpdate.rejectionReason = rejectionReason;
                if (rejectionNotes) schedUpdate.rejectionNotes = rejectionNotes;
            }

            batch.set(db.collection("schedule").doc(scheduleID), schedUpdate, { merge: true });
        }

        // Delivery status: ongoing, completed, or cancelled
        let deliveryStatus = "ongoing";
        if (isCompleted) {
            deliveryStatus = "completed";
        } else if (isRejected || isTerminated) {
            deliveryStatus = "cancelled";
        } else {
            deliveryStatus = "ongoing";
        }

        const delID = `DEL-${orderID}`;
        const delRef = db.collection("delivery").doc(delID);
        const delSnap = await delRef.get();
        if (delSnap.exists) {
            const delUpdate = { deliveryStatus, updatedAt: new Date() };
            if (isCompleted) {
                delUpdate.completedAt = FieldValue.serverTimestamp();
                if (proofOfDeliveryUrl) delUpdate.proofOfDeliveryUrl = proofOfDeliveryUrl;
            }
            batch.set(delRef, delUpdate, { merge: true });
        }

        if (orderID && isTerminated) {
            batch.set(db.collection("order").doc(orderID), {
                orderStatus: "Self pickup",
                fulfillmentType: "Self Pickup",
                terminationReason: rejectionReason || "Terminated - changed to Self Pickup",
                terminatedAt: new Date(),
                updatedAt: new Date()
            }, { merge: true });
        } else if (orderID && isRejected) {
            batch.set(db.collection("order").doc(orderID), {
                orderStatus: "Unassigned",
                updatedAt: new Date()
            }, { merge: true });
        }

        if (orderID && isCompleted) {
            batch.set(db.collection("order").doc(orderID), {
                orderStatus: "Delivered",
                updatedAt: new Date()
            }, { merge: true });

            // Send notification to customer for delivered order
            try {
                const ordSnap = await db.collection("order").doc(orderID).get();
                if (ordSnap.exists) {
                    const ordData = ordSnap.data() || {};
                    let custEmail = ordData.email || ordData.userEmail || "";
                    let custId = ordData.customerID || ordData.userId || "";

                    // If email missing, lookup from address or users
                    if (!custEmail && ordData.addressID) {
                        const addrSnap = await db.collection("address").doc(ordData.addressID).get();
                        if (addrSnap.exists) {
                            custEmail = addrSnap.data().email || "";
                        }
                    }
                    if (!custEmail && custId) {
                        const userSnap = await db.collection("users").doc(custId).get();
                        if (userSnap.exists) {
                            custEmail = userSnap.data().email || "";
                        }
                    }

                    if (custEmail) {
                        const notifRef = db.collection("notification").doc();
                        batch.set(notifRef, {
                            email: custEmail,
                            userId: custId,
                            type: "order",
                            title: "Order Delivered",
                            message: `Package Delivered: Your order #${orderID} has been successfully delivered. Thank you for choosing ReByte!`,
                            orderID: orderID,
                            isRead: false,
                            createdAt: new Date(),
                            proofOfDeliveryUrl: proofOfDeliveryUrl || null
                        });
                    }
                }
            } catch (notifErr) {
                console.error("Error creating delivery notification:", notifErr);
            }
        }

        await batch.commit();

        return res.json({ success: true, message: `Task status updated to ${normalized}` });
    } catch (err) {
        console.error("Error updating task status:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

/**
 * POST /api/task-assignment/complete-delivery
 * Prompt proof of delivery upload to Cloudinary and record completion timestamp
 */
router.post("/complete-delivery", (req, res, next) => {
    upload.single("proofImage")(req, res, (err) => {
        if (!err) return next();

        console.error("complete-delivery image upload validation error:", err);
        const isTooLarge = err instanceof multer.MulterError && err.code === "LIMIT_FILE_SIZE";
        return res.status(isTooLarge ? 413 : 400).json({
            success: false,
            message: isTooLarge
                ? "The delivery photo must be 10 MB or smaller."
                : "The delivery photo could not be processed. Please take another photo and try again."
        });
    });
}, async (req, res) => {
    try {
        const { taskID, orderID, scheduleID } = req.body;
        let proofOfDeliveryUrl = req.body.proofOfDeliveryUrl || "";

        // If an image file was provided, upload to Cloudinary under folder rebyte/proof_of_delivery
        if (req.file && req.file.buffer) {
            const folder = `rebyte/proof_of_delivery/${orderID || taskID || "deliveries"}`;
            const publicName = `proof_${Date.now()}`;
            const cloudResult = await uploadBufferToCloudinary(req.file.buffer, folder, publicName);
            proofOfDeliveryUrl = cloudResult.secure_url;
        }

        const batch = db.batch();

        if (taskID) {
            const taskUpdate = {
                taskStatus: "Delivered",
                completedAt: FieldValue.serverTimestamp(),
                updatedAt: new Date()
            };
            if (proofOfDeliveryUrl) taskUpdate.proofOfDeliveryUrl = proofOfDeliveryUrl;
            batch.set(db.collection("task").doc(taskID), taskUpdate, { merge: true });
        }

        if (scheduleID) {
            const schedUpdate = {
                scheduleStatus: "completed",
                completedAt: FieldValue.serverTimestamp(),
                updatedAt: new Date()
            };
            batch.set(db.collection("schedule").doc(scheduleID), schedUpdate, { merge: true });
        }

        if (orderID) {
            const delID = `DEL-${orderID}`;
            const delRef = db.collection("delivery").doc(delID);
            const delUpdate = {
                deliveryStatus: "completed",
                completedAt: FieldValue.serverTimestamp(),
                updatedAt: new Date()
            };
            if (proofOfDeliveryUrl) delUpdate.proofOfDeliveryUrl = proofOfDeliveryUrl;
            batch.set(delRef, delUpdate, { merge: true });

            batch.set(db.collection("order").doc(orderID), {
                orderStatus: "Delivered",
                updatedAt: new Date()
            }, { merge: true });

            // Send notification to customer for delivered order
            try {
                const ordSnap = await db.collection("order").doc(orderID).get();
                if (ordSnap.exists) {
                    const ordData = ordSnap.data() || {};
                    let custEmail = ordData.email || ordData.userEmail || "";
                    let custId = ordData.customerID || ordData.userId || "";

                    if (!custEmail && ordData.addressID) {
                        const addrSnap = await db.collection("address").doc(ordData.addressID).get();
                        if (addrSnap.exists) {
                            custEmail = addrSnap.data().email || "";
                        }
                    }
                    if (!custEmail && custId) {
                        const userSnap = await db.collection("users").doc(custId).get();
                        if (userSnap.exists) {
                            custEmail = userSnap.data().email || "";
                        }
                    }

                    if (custEmail) {
                        const notifRef = db.collection("notification").doc();
                        batch.set(notifRef, {
                            email: custEmail,
                            userId: custId,
                            type: "order",
                            title: "Order Delivered",
                            message: `Package Delivered: Your order #${orderID} has been successfully delivered. Thank you for choosing ReByte!`,
                            orderID: orderID,
                            isRead: false,
                            createdAt: new Date(),
                            proofOfDeliveryUrl: proofOfDeliveryUrl || null
                        });
                    }
                }
            } catch (notifErr) {
                console.error("Error creating delivery notification:", notifErr);
            }
        }

        await batch.commit();

        // Broadcast delivery completion to Socket.IO room if active
        try {
            const io = req.app.get("io");
            if (io && orderID) {
                const cleanOrderID = String(orderID).replace(/^#/, "").trim();
                io.to(`delivery:${cleanOrderID}`).emit("delivery-completed", {
                    orderID: cleanOrderID,
                    status: "Delivered",
                    message: "Package has been successfully delivered!",
                    completedAt: new Date().toISOString(),
                    proofOfDeliveryUrl: proofOfDeliveryUrl || null
                });
            }
        } catch (sockErr) {
            console.error("Socket emit delivery-completed error:", sockErr);
        }

        return res.json({
            success: true,
            proofOfDeliveryUrl,
            message: "Delivery completed and proof of delivery saved successfully."
        });
    } catch (err) {
        console.error("complete-delivery error:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

/**
 * POST /api/task-assignment/update-staff-location
 * Updates live GPS location of the delivering staff member for real-time customer tracking
 */
router.post("/update-staff-location", async (req, res) => {
    try {
        const { orderID, taskID, staffID, lat, lng, heading, estimatedDistanceKm, estimatedDurationMinutes } = req.body;
        if (!lat || !lng) {
            return res.status(400).json({ success: false, error: "lat and lng are required" });
        }

        const numericLat = Number(lat);
        const numericLng = Number(lng);
        const numericHeading = Number(heading || 0);

        if (isNaN(numericLat) || isNaN(numericLng)) {
            return res.status(400).json({ success: false, error: "Invalid coordinates" });
        }

        const updateData = {
            staffLat: numericLat,
            staffLng: numericLng,
            staffHeading: numericHeading,
            lastGpsUpdate: new Date()
        };

        if (estimatedDistanceKm != null && !isNaN(Number(estimatedDistanceKm))) {
            updateData.estimatedDistance = Number(estimatedDistanceKm);
        }
        if (estimatedDurationMinutes != null && !isNaN(Number(estimatedDurationMinutes))) {
            updateData.estimatedDuration = Number(estimatedDurationMinutes);
        }

        if (orderID) {
            await db.collection("delivery").doc(`DEL-${orderID}`).set(updateData, { merge: true }).catch(() => {});
        }
        if (taskID) {
            await db.collection("task").doc(taskID).set(updateData, { merge: true }).catch(() => {});
        }
        if (staffID) {
            await db.collection("users").doc(staffID).set({
                currentLat: numericLat,
                currentLng: numericLng,
                lastLocationUpdate: new Date()
            }, { merge: true }).catch(() => {});
        }

        return res.json({ success: true, message: "Staff location updated" });
    } catch (err) {
        console.error("Error in update-staff-location:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

/**
 * GET /api/task-assignment/socket-rooms
 * Inspect active delivery rooms, participant count, roles (staff/customer), and cached live locations
 */
router.get("/socket-rooms", (req, res) => {
    try {
        const io = req.app.get("io");
        const status = getDeliveryRoomsStatus(io);

        // If visited in a browser or ?view=html requested, render a clean visual dashboard
        const isHtml = req.query.view === "html" || (req.headers.accept && req.headers.accept.includes("text/html") && req.query.view !== "json");
        if (isHtml) {
            const roomsHtml = status.rooms.length === 0
                ? `<div style="text-align:center; padding: 40px; color: #6b7280; font-size: 15px; background: white; border-radius: 12px; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">
                    <p style="margin: 0; font-weight: 600; color: #374151;">No active delivery rooms right now.</p>
                    <p style="margin: 6px 0 0 0; font-size: 13px;">Rooms are created automatically when Staff starts navigation or Customer tracks an order.</p>
                   </div>`
                : status.rooms.map(r => `
                    <div style="background: white; border-radius: 12px; padding: 20px; margin-bottom: 16px; box-shadow: 0 2px 4px rgba(0,0,0,0.06); border-left: 6px solid #10b981;">
                        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px;">
                            <h3 style="margin: 0; color: #111827; font-size: 17px;">
                                Room: <span style="color: #059669; font-family: monospace;">${r.room}</span> &nbsp;
                                <span style="color: #6b7280; font-size: 13px;">(Order #${r.orderID})</span>
                            </h3>
                            <span style="background: #ecfdf5; color: #047857; font-weight: 600; padding: 4px 12px; border-radius: 20px; font-size: 12px;">
                                ${r.participantCount} Connected (${r.staffCount} Staff, ${r.customerCount} Customer)
                            </span>
                        </div>
                        <div style="background: #f9fafb; padding: 12px; border-radius: 8px; margin-bottom: 14px; font-size: 13px;">
                            <strong>Latest GPS Location:</strong>
                            ${r.location ? `
                                <div style="margin-top: 4px; font-family: monospace; color: #1f2937;">
                                    Latitude: <b>${r.location.lat}</b> | Longitude: <b>${r.location.lng}</b><br>
                                    Heading: <b>${r.location.heading}°</b> | Speed: <b>${r.location.speed} km/h</b> | Last Updated: <b>${r.location.ageSeconds}s ago</b>
                                </div>
                            ` : '<span style="color: #9ca3af; margin-left: 6px;">Waiting for first GPS broadcast...</span>'}
                        </div>
                        <div style="font-size: 12px; font-weight: 600; color: #4b5563; text-transform: uppercase; margin-bottom: 6px;">Connected Participants:</div>
                        <ul style="margin: 0; padding-left: 20px; font-size: 13px; color: #374151;">
                            ${r.participants.map(p => `
                                <li>
                                    <span style="display: inline-block; padding: 2px 6px; border-radius: 4px; font-size: 11px; font-weight: 700; ${p.role === 'staff' ? 'background: #dbeafe; color: #1d4ed8;' : 'background: #fef3c7; color: #b45309;'}">
                                        ${p.role.toUpperCase()}
                                    </span>
                                    &nbsp;Socket ID: <code>${p.socketId}</code>
                                    <span style="color: #9ca3af; font-size: 11px; margin-left: 6px;">(Joined: ${p.joinedAt || 'N/A'})</span>
                                </li>
                            `).join('')}
                        </ul>
                    </div>
                `).join('');

            return res.send(`
                <!DOCTYPE html>
                <html>
                <head>
                    <title>ReByte Socket.IO Delivery Monitor</title>
                    <meta http-equiv="refresh" content="4">
                    <style>
                        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f3f4f6; margin: 0; padding: 28px; }
                        .container { max-width: 820px; margin: 0 auto; }
                        .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 22px; }
                        .badge { background: #3b82f6; color: white; padding: 6px 14px; border-radius: 20px; font-weight: 700; font-size: 13px; }
                    </style>
                </head>
                <body>
                    <div class="container">
                        <div class="header">
                            <div>
                                <h1 style="margin: 0; color: #111827; font-size: 24px;">ReByte Socket.IO Delivery Rooms</h1>
                                <p style="margin: 4px 0 0 0; color: #6b7280; font-size: 13px;">Auto-refreshes every 4s &bull; Total sockets: <b>${status.totalConnectedSockets}</b> &bull; <a href="?view=json" style="color: #2563eb; text-decoration: none;">View JSON API</a></p>
                            </div>
                            <span class="badge">${status.activeRoomsCount} Active Room${status.activeRoomsCount === 1 ? '' : 's'}</span>
                        </div>
                        ${roomsHtml}
                    </div>
                </body>
                </html>
            `);
        }

        return res.json({ success: true, ...status });
    } catch (err) {
        console.error("Error in GET /socket-rooms:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

/**
 * GET /api/task-assignment/track-delivery/:orderID
 * Returns real-time delivery and staff tracking information for customer tracking map
 */
router.get("/track-delivery/:orderID", async (req, res) => {
    try {
        const orderID = String(req.params.orderID || "").replace("#", "").trim();
        if (!orderID) {
            return res.status(400).json({ success: false, error: "orderID is required" });
        }

        let orderData = {};
        const ordSnap = await db.collection("order").doc(orderID).get();
        if (ordSnap.exists) {
            orderData = ordSnap.data();
        }

        let taskData = {};
        const taskID = `TSK-${orderID}`;
        const taskSnap = await db.collection("task").doc(taskID).get();
        if (taskSnap.exists) {
            taskData = taskSnap.data();
        }

        let schedData = {};
        const scheduleID = taskData.scheduleID || orderData.scheduleID;
        if (scheduleID) {
            const sDoc = await db.collection("schedule").doc(scheduleID).get();
            if (sDoc.exists) {
                schedData = sDoc.data();
            }
        }

        let delData = {};
        const delSnap = await db.collection("delivery").doc(`DEL-${orderID}`).get();
        if (delSnap.exists) {
            delData = delSnap.data();
        }

        // Resolve customer address & destination coordinates
        let address = {};
        const addressID = orderData.addressID;
        if (addressID) {
            const aDoc = await db.collection("address").doc(addressID).get();
            if (aDoc.exists) {
                address = aDoc.data();
            }
        }

        let destLat = Number(delData.destinationLat || address.lat || address.latitude || 5.3911);
        let destLng = Number(delData.destinationLng || address.lng || address.longitude || 100.3237);

        // Resolve staff member
        const staffID = schedData.staffID || taskData.staffID || delData.staffID || "";
        let staffName = schedData.staffName || taskData.staffName || "Delivery Specialist";
        let staffPhone = "";
        let staffLat = null;
        let staffLng = null;
        let staffHeading = 0;

        if (staffID) {
            const uDoc = await db.collection("users").doc(staffID).get();
            if (uDoc.exists) {
                const uData = uDoc.data();
                if (!staffName || staffName === "Delivery Specialist") {
                    staffName = uData.fullName || uData.name || staffName;
                }
                staffPhone = uData.phoneNumber || uData.phone || "";

                // Check staff live location, registered workLocation, or direct lat/lng
                if (uData.currentLat && uData.currentLng) {
                    staffLat = Number(uData.currentLat);
                    staffLng = Number(uData.currentLng);
                } else if (uData.workLocation && uData.workLocation.lat && uData.workLocation.lng) {
                    staffLat = Number(uData.workLocation.lat);
                    staffLng = Number(uData.workLocation.lng);
                } else if (uData.lat && uData.lng) {
                    staffLat = Number(uData.lat);
                    staffLng = Number(uData.lng);
                }
            }
        }

        // Top Priority: Live GPS location actively broadcast by the staff member during navigation
        let isLiveGps = false;
        if (delData.staffLat && delData.staffLng) {
            staffLat = Number(delData.staffLat);
            staffLng = Number(delData.staffLng);
            staffHeading = Number(delData.staffHeading || 0);
            isLiveGps = true;
        } else if (taskData.staffLat && taskData.staffLng) {
            staffLat = Number(taskData.staffLat);
            staffLng = Number(taskData.staffLng);
            staffHeading = Number(taskData.staffHeading || 0);
            isLiveGps = true;
        }

        // Absolute fallback only if staff has no registered location and no GPS
        if (!staffLat || !staffLng) {
            staffLat = 5.453240417145323;
            staffLng = 100.2848625551094;
        }

        const deliveryAddressText = [address.addressLine, address.city, address.state, address.postcode].filter(Boolean).join(", ");

        return res.json({
            success: true,
            orderID,
            taskID,
            scheduleID: scheduleID || null,
            orderStatus: orderData.orderStatus || taskData.taskStatus || "Shipping",
            taskStatus: taskData.taskStatus || orderData.orderStatus || "Shipping",
            scheduleDate: schedData.scheduleDate || null,
            estimatedEndTime: schedData.scheduleEndTime || taskData.taskStartTime || null,
            estimatedDuration: delData.estimatedDuration || taskData.estimatedDuration || 18,
            estimatedDistance: delData.estimatedDistance || taskData.estimatedDistance || 4.2,
            destinationLat: destLat,
            destinationLng: destLng,
            deliveryAddress: deliveryAddressText || address.addressLine || "Delivery Destination",
            recipientName: address.recipentName || address.recipientName || "",
            staffID,
            staffName,
            staffPhone,
            staffLat,
            staffLng,
            staffHeading,
            isLiveGps,
            lastGpsUpdate: delData.lastGpsUpdate || null
        });
    } catch (err) {
        console.error("Error in track-delivery:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

/**
 * Helper: Compute display status according to business requirements:
 * 1. If order is cancelled by customer -> Refunded
 * 2. If order is self-pick up / terminated, task is rejected -> Terminated
 * 3. If order is Delivered, task is Delivered -> Completed
 * 4. If order delivering, task is packaging or delivering -> Assigned
 * 5. If order unassigned, task is rejected -> Cancelled
 * 6. If order unassigned, task is unassigned -> Unassigned
 */
function computeDisplayStatus(orderStatus, taskStatus, fulfillmentType, cancelledBy, rejectionReason, staffID) {
    const o = String(orderStatus || '').trim().toLowerCase();
    const t = String(taskStatus || '').trim().toLowerCase();
    const f = String(fulfillmentType || '').trim().toLowerCase();
    const cb = String(cancelledBy || '').trim().toLowerCase();
    const rr = String(rejectionReason || '').trim().toLowerCase();
    const isPickup = f.includes('pickup') || f.includes('self') || o.includes('pickup') || o.includes('self');

    // Rule 3: If order is Delivered, task is Delivered -> Completed
    if ((o === 'delivered' || o === 'completed') && (t === 'delivered' || t === 'completed')) return 'Completed';
    if (o === 'delivered' || t === 'delivered' || t === 'completed') return 'Completed';

    // Rule 1: If order is cancelled by customer -> Refunded
    if (cb === 'customer' || rr.includes('cancelled by customer') || rr.includes('canceled by customer') || (o === 'cancelled' && t === 'cancelled')) {
        return 'Refunded';
    }

    // Rule 2: If order is self-pick up, task is rejected -> Terminated
    if (isPickup && (t === 'rejected' || t === 'terminated' || o === 'rejected' || o === 'terminated' || o === 'self pickup' || o === 'self-pickup')) return 'Terminated';
    if (o === 'terminated' || t === 'terminated' || o === 'self pickup' || o === 'self-pickup') return 'Terminated';

    // Rule 5: If order unassigned, task is rejected -> Cancelled (by staff or operational)
    if ((o === 'unassigned' || o === 'cancelled' || o === 'processing') && (t === 'rejected' || t === 'cancelled')) return 'Cancelled';
    if (t === 'rejected' || o === 'cancelled') return 'Cancelled';

    // Rule 6: If explicitly unassigned, task is unassigned -> Unassigned
    if (t === 'unassigned' || o === 'unassigned') return 'Unassigned';

    // Rule 4: If assigned staff exists and task is active -> Assigned
    const cleanStaff = String(staffID || '').trim().toLowerCase();
    if (cleanStaff && cleanStaff !== 'unassigned' && cleanStaff !== 'null' && cleanStaff !== 'undefined') {
        return 'Assigned';
    }

    // Rule 4 (continued): If order status is packaging/delivering/assigned/processing/success, and task is packaging/delivering/shipping/assigned/ongoing -> Assigned
    if ((o === 'delivering' || o === 'assigned' || o === 'processing' || o === 'packaging' || o === 'success') && 
        (t === 'packaging' || t === 'delivering' || t === 'shipping' || t === 'assigned' || t === 'ongoing')) return 'Assigned';

    if (t === 'packaging' || t === 'delivering' || t === 'shipping' || t === 'assigned' || t === 'ongoing') {
        return 'Assigned';
    }

    if (o === 'delivering' || o === 'packaging' || o === 'assigned') {
        return 'Assigned';
    }

    return 'Unassigned';
}

/**
 * Format a Date object to readable Appointment string (e.g. "Oct 24, 2023")
 */
function formatAppointmentDate(d) {
    if (!d) return "Oct 24, 2026";
    const dateObj = d.toDate ? d.toDate() : new Date(d);
    if (isNaN(dateObj.getTime())) return "Oct 24, 2026";
    return dateObj.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}

function formatOrderDateTime(d) {
    if (!d) return "—";
    const dateObj = d.toDate ? d.toDate() : new Date(d);
    if (isNaN(dateObj.getTime())) return "—";
    const day = dateObj.getDate();
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    const month = months[dateObj.getMonth()];
    const year = dateObj.getFullYear();
    const hh = String(dateObj.getHours()).padStart(2, "0");
    const mm = String(dateObj.getMinutes()).padStart(2, "0");
    return `${day} ${month} ${year}, ${hh}:${mm}`;
}

function getOrderTimestamp(d) {
    if (!d) return 0;
    const raw = d.createdAt || d.orderDate;
    if (!raw) return 0;
    if (raw.toDate && typeof raw.toDate === "function") return raw.toDate().getTime();
    if (raw._seconds) return raw._seconds * 1000 + (raw._nanoseconds ? raw._nanoseconds / 1e6 : 0);
    const dt = new Date(raw);
    return isNaN(dt.getTime()) ? 0 : dt.getTime();
}

/**
 * GET /api/task-assignment/admin/tasks
 * Fetch all tasks and orders for Admin Task Assignment page
 */
router.get("/admin/tasks", async (req, res) => {
    try {
        // 1. Fetch all orders
        const ordersSnap = await db.collection("order").get();

        // 2. Fetch all tasks
        const tasksSnap = await db.collection("task").get();
        const tasksByOrderId = new Map();
        const tasksById = new Map();
        tasksSnap.forEach(doc => {
            const data = doc.data();
            const tid = data.taskID || doc.id;
            tasksById.set(tid, data);
            if (data.orderID) {
                tasksByOrderId.set(data.orderID, data);
            }
        });

        // 3. Fetch all schedules
        const schedSnap = await db.collection("schedule").get();
        const schedMap = new Map();
        schedSnap.forEach(doc => {
            const data = doc.data();
            const sid = data.scheduleID || doc.id;
            schedMap.set(sid, data);
            if (data.orderID) {
                schedMap.set(`order_${data.orderID}`, data);
            }
        });

        // 4. Fetch all staff members from users collection
        const staffSnap = await db.collection("users").where("role", "==", "Staff").get();
        const staffMap = new Map();
        staffSnap.forEach(doc => {
            const data = doc.data();
            const name = data.fullName || data.name || "Staff Member";
            staffMap.set(doc.id, { staffID: doc.id, name, email: data.email || "", phone: data.phoneNumber || data.phone || "" });
        });

        // Caches for products, addresses, and customer users to minimize duplicate reads
        const productCache = new Map();
        const addressCache = new Map();
        const userCache = new Map();

        const taskList = [];

        for (const oDoc of ordersSnap.docs) {
            const ordData = oDoc.data();
            const orderID = ordData.orderID || oDoc.id;

            // Resolve linked task
            const taskData = tasksByOrderId.get(orderID) || {};
            const taskID = taskData.taskID || `TSK-${orderID}`;
            const taskStatus = taskData.taskStatus || "Unassigned";

            // Resolve linked schedule
            const scheduleID = taskData.scheduleID || ordData.scheduleID || "";
            const schedData = (scheduleID ? schedMap.get(scheduleID) : null) || schedMap.get(`order_${orderID}`) || {};

            // Resolve linked staff
            const staffID = schedData.staffID || taskData.staffID || "";
            const staffInfo = staffMap.get(staffID);
            const staffName = staffInfo ? staffInfo.name : (schedData.staffName || taskData.staffName || "");

            // Resolve customer address
            let address = {};
            const addressID = ordData.addressID;
            if (addressID) {
                if (addressCache.has(addressID)) {
                    address = addressCache.get(addressID);
                } else {
                    const aDoc = await db.collection("address").doc(addressID).get();
                    if (aDoc.exists) {
                        address = aDoc.data();
                        addressCache.set(addressID, address);
                    }
                }
            }

            // Resolve customer profile
            let customerName = address.recipentName || address.recipientName || "";
            let customerEmail = address.email || ordData.email || ordData.userEmail || "";
            let customerPhone = address.phoneNumber || ordData.phoneNumber || "";
            const customerID = ordData.customerID || ordData.userId || "";

            if ((!customerName || customerName === "Customer") && customerID) {
                if (userCache.has(customerID)) {
                    const u = userCache.get(customerID);
                    customerName = customerName || u.name;
                    customerEmail = customerEmail || u.email;
                    customerPhone = customerPhone || u.phone;
                } else {
                    const uDoc = await db.collection("users").doc(customerID).get();
                    if (uDoc.exists) {
                        const uData = uDoc.data();
                        const uName = uData.fullName || uData.name || "Customer";
                        userCache.set(customerID, { name: uName, email: uData.email || "", phone: uData.phoneNumber || "" });
                        customerName = customerName || uName;
                        customerEmail = customerEmail || uData.email || "";
                        customerPhone = customerPhone || uData.phoneNumber || "";
                    }
                }
            }
            if (!customerName) customerName = "Customer";

            // Resolve products & device summary
            const pIds = Array.isArray(ordData.productIDs) ? ordData.productIDs : [];
            let deviceSummary = "";
            const items = [];

            for (const pid of pIds) {
                let p = productCache.get(pid);
                if (!p) {
                    const pDoc = await db.collection("product").doc(pid).get();
                    if (pDoc.exists) {
                        p = pDoc.data();
                        productCache.set(pid, p);
                    }
                }
                if (p) {
                    let brand = p.brand || "";
                    let model = p.model || "";
                    let storage = p.storage || "";
                    let color = p.color || "";

                    if (!model && p.description) {
                        const parenIdx = p.description.indexOf("(");
                        if (parenIdx > -1) {
                            model = p.description.substring(0, parenIdx).trim();
                            const inParen = p.description.substring(parenIdx + 1, p.description.indexOf(")", parenIdx));
                            if (!storage) storage = inParen.trim();
                        } else {
                            model = p.description.split(" - ")[0].trim();
                        }
                    }

                    const itemSummary = [brand, model].filter(Boolean).join(" ") + (storage ? ` • ${storage}` : "");
                    if (!deviceSummary && itemSummary) deviceSummary = itemSummary;

                    items.push({
                        productID: pid,
                        brand,
                        model,
                        storage,
                        color,
                        price: p.price || 0,
                        imageUrl: p.imageUrl || ""
                    });
                }
            }

            if (!deviceSummary) {
                deviceSummary = "Electronics Device";
            }

            // Appointment Date & Time
            // Priority: ordData.createdAt first as requested by user
            const createdAtMs = getOrderTimestamp(ordData);
            const orderDateRaw = ordData.createdAt || ordData.orderDate;
            const appointmentDate = schedData.scheduleDate ? formatAppointmentDate(schedData.scheduleDate) : formatAppointmentDate(orderDateRaw);

            let appointmentTime = "09:00 - 17:00";
            if (schedData.scheduleStartTime && schedData.scheduleEndTime) {
                appointmentTime = `${schedData.scheduleStartTime} - ${schedData.scheduleEndTime}`;
            } else if (taskData.taskStartTime) {
                appointmentTime = `${taskData.taskStartTime} - 17:00`;
            }

            // Flag as Urgent if order created early morning before 9 AM or explicitly marked
            let isUrgent = false;
            if (createdAtMs > 0) {
                const dateObj = new Date(createdAtMs);
                if (dateObj.getHours() < 9) {
                    isUrgent = true;
                }
            }
            if (ordData.isUrgent || taskData.isUrgent) isUrgent = true;

            const orderStatus = ordData.orderStatus || "Unassigned";
            const fulfillmentType = ordData.fulfillmentType || ordData.deliveryOption || "Delivery";
            const rejectionReason = taskData.rejectionReason || schedData.rejectionReason || "";

            // Compute exact display status according to the user's business rules:
            const displayStatus = computeDisplayStatus(orderStatus, taskStatus, fulfillmentType, ordData.cancelledBy, rejectionReason, staffID);

            const deliveryAddress = [address.addressLine, address.postcode, address.city, address.state].filter(Boolean).join(", ");

            taskList.push({
                taskID,
                orderID,
                scheduleID: scheduleID || null,
                staffID: staffID || null,
                staffName: staffName || "Unassigned",
                customerID,
                customerName,
                customerEmail,
                customerPhone,
                deliveryAddress: deliveryAddress || "Penang, Malaysia",
                deviceSummary,
                items,
                appointmentDate,
                appointmentTime,
                isUrgent,
                orderStatus,
                taskStatus,
                fulfillmentType,
                displayStatus,
                totalAmount: ordData.totalAmount || ordData.subtotal || 0,
                rejectionReason,
                rejectionNotes: taskData.rejectionNotes || schedData.rejectionNotes || "",
                proofOfDeliveryUrl: taskData.proofOfDeliveryUrl || "",
                estimatedDistance: taskData.estimatedDistance || 0,
                estimatedDuration: taskData.estimatedDuration || 0,
                completedAt: taskData.completedAt || null,
                createdAt: createdAtMs ? new Date(createdAtMs).toISOString() : new Date().toISOString(),
                createdAtMs: createdAtMs
            });
        }

        // Sort strictly based on order createdAt date time (newest first)
        taskList.sort((a, b) => (b.createdAtMs || 0) - (a.createdAtMs || 0));

        // Count totals for all status categories
        const counts = {
            unassigned: 0,
            assigned: 0,
            cancelled: 0,
            refunded: 0,
            terminated: 0,
            completed: 0,
            total: taskList.length
        };

        taskList.forEach(t => {
            const key = t.displayStatus.toLowerCase();
            if (counts[key] !== undefined) {
                counts[key]++;
            }
        });

        return res.json({
            success: true,
            counts,
            tasks: taskList
        });
    } catch (err) {
        console.error("Error in GET /admin/tasks:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

/**
 * GET /api/task-assignment/admin/staff
 * Returns list of staff members with their current active task count
 */
router.get("/admin/staff", async (req, res) => {
    try {
        const staffSnap = await db.collection("users").where("role", "==", "Staff").get();
        const schedSnap = await db.collection("schedule").where("scheduleStatus", "in", ["assigned", "ongoing"]).get();

        const activeTaskCountByStaff = new Map();
        schedSnap.forEach(doc => {
            const sid = doc.data().staffID;
            if (sid) {
                activeTaskCountByStaff.set(sid, (activeTaskCountByStaff.get(sid) || 0) + 1);
            }
        });

        const staffList = staffSnap.docs.map(doc => {
            const d = doc.data();
            const sid = doc.id;
            return {
                staffID: sid,
                name: d.fullName || d.name || "Staff Member",
                email: d.email || "",
                phone: d.phoneNumber || d.phone || "",
                activeTasks: activeTaskCountByStaff.get(sid) || 0
            };
        });

        return res.json({ success: true, staff: staffList });
    } catch (err) {
        console.error("Error in GET /admin/staff:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

// Haversine distance calculator in km
function calculateHaversineKm(lat1, lon1, lat2, lon2) {
    if (!lat1 || !lon1 || !lat2 || !lon2) return 2.5;
    const R = 6371; // km
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLon = (lon2 - lon1) * Math.PI / 180;
    const a =
        Math.sin(dLat / 2) * Math.sin(dLat / 2) +
        Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
        Math.sin(dLon / 2) * Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return Number((R * c).toFixed(1));
}

/**
 * GET /api/task-assignment/admin/reassign-candidates
 * Returns task details for the left panel and filtered available staff for the right panel.
 * Rule: If delivery type, return staff whose position is 'Deliverer' or 'Both'.
 *       If inspection type, return staff whose position is 'Inspector' or 'Both'.
 */
router.get("/admin/reassign-candidates", async (req, res) => {
    try {
        const { orderID } = req.query;
        if (!orderID) {
            return res.status(400).json({ success: false, error: "orderID is required" });
        }

        // 1. Fetch Order
        const orderDoc = await db.collection("order").doc(orderID).get();
        if (!orderDoc.exists) {
            return res.status(404).json({ success: false, error: `Order #${orderID} not found` });
        }
        const orderData = orderDoc.data();

        // 2. Fetch Task
        let taskData = {};
        let taskID = `TSK-${orderID}`;
        const taskSnap = await db.collection("task").where("orderID", "==", orderID).limit(1).get();
        if (!taskSnap.empty) {
            taskData = taskSnap.docs[0].data();
            taskID = taskData.taskID || taskSnap.docs[0].id;
        } else {
            const directTaskDoc = await db.collection("task").doc(taskID).get();
            if (directTaskDoc.exists) {
                taskData = directTaskDoc.data();
            }
        }

        // 3. Fetch Linked Schedule & Previous Staff Name
        let previousStaffName = taskData.staffName || "";
        let currentStaffID = taskData.staffID || "";
        const scheduleID = taskData.scheduleID || orderData.scheduleID || "";
        if (scheduleID) {
            const schedDoc = await db.collection("schedule").doc(scheduleID).get();
            if (schedDoc.exists) {
                const sData = schedDoc.data();
                if (!currentStaffID && sData.staffID) {
                    currentStaffID = sData.staffID;
                }
                if (!previousStaffName && sData.staffName) {
                    previousStaffName = sData.staffName;
                }
                if (!previousStaffName && sData.staffID) {
                    const uDoc = await db.collection("users").doc(sData.staffID).get();
                    if (uDoc.exists) {
                        previousStaffName = uDoc.data().fullName || uDoc.data().name || "";
                    }
                }
            }
        }
        if (!previousStaffName) {
            previousStaffName = "Sarah Jenkins";
        }

        // 4. Resolve Address & Coordinates
        let address = {};
        let destLat = 5.4164;
        let destLng = 100.3327;
        let locationDisplay = "Hub C - Bay 4";

        if (orderData.addressID) {
            const addrDoc = await db.collection("address").doc(orderData.addressID).get();
            if (addrDoc.exists) {
                address = addrDoc.data();
                if (address.lat && address.lng) {
                    destLat = Number(address.lat);
                    destLng = Number(address.lng);
                } else if (address.latitude && address.longitude) {
                    destLat = Number(address.latitude);
                    destLng = Number(address.longitude);
                }
                const parts = [address.addressLine, address.city, address.state].filter(Boolean);
                if (parts.length > 0) {
                    locationDisplay = parts.join(", ");
                }
            }
        }

        // 5. Resolve Product & Device Info
        let deviceName = "Apple iPhone 13 Pro";
        let deviceBrand = "Apple";
        let deviceModel = "iPhone 13 Pro";
        let deviceStorage = "256 GB";
        let deviceImei = "354678091234567";
        let deviceColor = "Sierra Blue";

        const pIds = Array.isArray(orderData.productIDs) ? orderData.productIDs : [];
        if (pIds.length > 0) {
            const prodDoc = await db.collection("product").doc(pIds[0]).get();
            if (prodDoc.exists) {
                const p = prodDoc.data();
                if (p.brand) deviceBrand = p.brand;
                if (p.model) deviceModel = p.model;
                if (p.storage) deviceStorage = p.storage;
                if (p.color) deviceColor = p.color;
                if (p.imei) deviceImei = p.imei;
                if (p.serialNumber) deviceImei = p.serialNumber;

                if (!p.model && p.description) {
                    const parenIdx = p.description.indexOf("(");
                    if (parenIdx > -1) {
                        deviceModel = p.description.substring(0, parenIdx).trim();
                        const inParen = p.description.substring(parenIdx + 1, p.description.indexOf(")", parenIdx));
                        if (!p.storage) deviceStorage = inParen.trim();
                    } else {
                        deviceModel = p.description.split(" - ")[0].trim();
                    }
                }
                if (deviceModel.toLowerCase().startsWith(deviceBrand.toLowerCase())) {
                    deviceName = deviceModel;
                } else {
                    deviceName = [deviceBrand, deviceModel].filter(Boolean).join(" ");
                }
            }
        }

        // 6. Cancellation Reason & Priority
        const cancellationReason = taskData.rejectionReason || 
                                   taskData.rejectionNotes || 
                                   "Client arrived late and I have a conflicting with next task. Needs immediate reassignment to clear queue.";

        const orderDateRaw = orderData.orderDate || orderData.createdAt;
        let isUrgent = !!(orderData.isUrgent || taskData.isUrgent);
        if (orderDateRaw) {
            const dateObj = orderDateRaw.toDate ? orderDateRaw.toDate() : new Date(orderDateRaw);
            if (!isNaN(dateObj.getTime()) && dateObj.getHours() < 9) {
                isUrgent = true;
            }
        }

        // 7. Task Type Determination
        const fulfillmentType = String(orderData.fulfillmentType || orderData.deliveryOption || "Delivery").trim();
        const taskTypeRaw = String(taskData.taskType || "").trim().toLowerCase();
        const isDelivery = fulfillmentType.toLowerCase().includes("delivery") || 
                           taskTypeRaw.includes("deliver") || 
                           fulfillmentType.toLowerCase().includes("shipping");

        const taskTypeLabel = isDelivery ? "Delivery Task" : "Inspection Task";
        const displayStatus = computeDisplayStatus(orderData.orderStatus, taskData.taskStatus, fulfillmentType, orderData.cancelledBy, taskData.rejectionReason, currentStaffID);

        // Resolve customer destination state
        let customerState = "Penang";
        if (address.state) {
            customerState = String(address.state).trim();
        } else if (locationDisplay) {
            const parts = locationDisplay.split(",").map(p => p.trim());
            if (parts.length > 0) customerState = parts[parts.length - 1];
        }

        // 8. Filter Staff according to User's Core Rules:
        // Rule 1: If delivery type, position must be 'Deliverer' or 'Both'.
        //         If inspection type, position must be 'Inspector' or 'Both'.
        // Rule 2: Active tasks must be under 8 (activeTasks < 8).
        // Rule 3: Staff must operate in the same state as customer destination.
        // Rule 4: Distance calculated from last task ended location to this task location.
        // Rule 5: Availability: "Now", or if today over 9am "Tomorrow HH:mm", or if 00:00-08:59 "Today HH:mm".
        const staffSnap = await db.collection("users").where("role", "==", "Staff").get();

        // Date helpers for Malaysia local time (UTC+8)
        function parseScheduleDate(timeVal, dateStr) {
            if (!timeVal) return null;
            if (timeVal.toDate) return timeVal.toDate();
            const str = String(timeVal).trim();
            if (str.includes("T") || (str.includes("-") && str.length > 8)) {
                const dt = new Date(str);
                return isNaN(dt.getTime()) ? null : dt;
            }
            const parts = str.split(":");
            if (parts.length >= 2) {
                const hh = parts[0].padStart(2, "0");
                const mm = parts[1].padStart(2, "0");
                const ss = parts[2] ? parts[2].padStart(2, "0") : "00";
                const baseDate = dateStr || "2026-10-21";
                const d = new Date(`${baseDate}T${hh}:${mm}:${ss}`);
                return isNaN(d.getTime()) ? null : d;
            }
            return null;
        }

        function formatLocalYMD(d) {
            const y = d.getFullYear();
            const m = String(d.getMonth() + 1).padStart(2, "0");
            const day = String(d.getDate()).padStart(2, "0");
            return `${y}-${m}-${day}`;
        }

        function formatTimeHHmmMY(timeVal) {
            if (!timeVal) return "09:00";
            const str = String(timeVal).trim();
            if (/^\d{1,2}:\d{1,2}/.test(str) && !str.includes("T")) {
                const parts = str.split(":");
                return `${parts[0].padStart(2, "0")}:${parts[1].padStart(2, "0")}`;
            }
            const d = new Date(str);
            if (!isNaN(d.getTime())) {
                const utcMs = d.getTime() + (d.getTimezoneOffset() * 60000);
                const myDate = new Date(utcMs + (8 * 3600000));
                return `${String(myDate.getHours()).padStart(2, "0")}:${String(myDate.getMinutes()).padStart(2, "0")}`;
            }
            return "09:00";
        }

        const nowUtc = new Date();
        const nowMs = nowUtc.getTime() + (nowUtc.getTimezoneOffset() * 60000);
        const myNow = new Date(nowMs + (8 * 3600000));
        const currentHour = myNow.getHours();
        const currentMinute = myNow.getMinutes();
        const currentTimeStr = `${String(currentHour).padStart(2, "0")}:${String(currentMinute).padStart(2, "0")}`;

        const todayStr = formatLocalYMD(myNow);
        const tmrDate = new Date(myNow);
        tmrDate.setDate(tmrDate.getDate() + 1);
        const tomorrowStr = formatLocalYMD(tmrDate);

        const isWithinWorkingHours = (currentHour >= 9 && currentHour < 17 && currentHour !== 12);
        const isOver9am = currentHour >= 9;
        const isEarlyMorning = currentHour < 9;

        const eligibleStaff = [];

        for (const doc of staffSnap.docs) {
            const d = doc.data();
            const status = String(d.status || d.staffStatus || "Active").toLowerCase().trim();
            if (status === "archived") continue;

            const pos = String(d.position || "").toLowerCase().trim();

            // Filter by Position based on Task Type
            if (isDelivery) {
                if (pos !== "deliverer" && pos !== "both") continue;
            } else {
                if (pos !== "inspector" && pos !== "both") continue;
            }

            const staffID = doc.id;

            // Fetch this staff's schedules to evaluate active workload & last task location
            const staffSchedSnap = await db.collection("schedule")
                .where("staffID", "==", staffID)
                .get();

            const staffScheds = [];
            staffSchedSnap.forEach(sDoc => {
                staffScheds.push({ id: sDoc.id, ...sDoc.data() });
            });

            // Count active tasks for today (assigned or ongoing)
            const todayActive = staffScheds.filter(s => 
                s.scheduleDate === todayStr && 
                (s.scheduleStatus === "assigned" || s.scheduleStatus === "ongoing")
            );
            const activeCount = todayActive.length;

            // Rule: Task count must be strictly under 8
            if (activeCount >= 8) continue;

            // Rule: Must be in the same state
            let staffState = String(d.state || "").trim();
            if (!staffState && d.workLocation && d.workLocation.address) {
                const parts = d.workLocation.address.split(",").map(p => p.trim());
                if (parts.length > 0) staffState = parts[parts.length - 1];
            }
            if (!staffState) staffState = "Penang";

            const sNorm = staffState.toLowerCase().trim();
            const cNorm = customerState.toLowerCase().trim();
            const isSameState = sNorm.includes(cNorm) || cNorm.includes(sNorm);
            if (!isSameState) continue;

            const fullName = d.fullName || d.name || "Staff Member";
            const specs = Array.isArray(d.specialization) ? d.specialization : [];

            // Specialization Tag: For delivery, show actual role (Deliverer / Both)
            let specializationTag = pos === "both" ? "Both" : "Deliverer";
            if (!isDelivery) {
                const hasAppleSpec = specs.some(s => String(s).toLowerCase().includes("apple"));
                if (pos === "both") specializationTag = "Both";
                else if (hasAppleSpec) specializationTag = "iOS Expert";
                else specializationTag = "Inspector";
            }

            // Workload (out of 8 tasks max)
            const maxTasks = 8;
            const workloadText = `${activeCount}/8 tasks`;

            // Distance calculation: from LAST TASK ENDED LOCATION to this task's destination
            const validTasks = staffScheds.filter(s => s.scheduleStatus !== "cancelled" && s.scheduleStatus !== "rejected");
            validTasks.sort((a, b) => {
                const timeA = parseScheduleDate(a.scheduleEndTime || a.scheduleStartTime, a.scheduleDate) || new Date(0);
                const timeB = parseScheduleDate(b.scheduleEndTime || b.scheduleStartTime, b.scheduleDate) || new Date(0);
                return timeB.getTime() - timeA.getTime();
            });

            let lastEndLat = null;
            let lastEndLng = null;

            if (validTasks.length > 0) {
                const lastTask = validTasks[0];
                if (lastTask.destinationLat && lastTask.destinationLng) {
                    lastEndLat = Number(lastTask.destinationLat);
                    lastEndLng = Number(lastTask.destinationLng);
                }
                if (!lastEndLat || !lastEndLng) {
                    let orderIdForLast = lastTask.orderID;
                    if (!orderIdForLast && lastTask.scheduleID) {
                        const m = lastTask.scheduleID.match(/^SCH-(.+)-\d+$/);
                        if (m) orderIdForLast = m[1];
                    }
                    if (orderIdForLast) {
                        const dDoc = await db.collection("delivery").doc(`DEL-${orderIdForLast}`).get();
                        if (dDoc.exists) {
                            const delData = dDoc.data();
                            if (delData.destinationLat && delData.destinationLng) {
                                lastEndLat = Number(delData.destinationLat);
                                lastEndLng = Number(delData.destinationLng);
                            }
                        }
                        if (!lastEndLat || !lastEndLng) {
                            const ordDoc = await db.collection("order").doc(orderIdForLast).get();
                            if (ordDoc.exists && ordDoc.data().addressID) {
                                const addrDoc = await db.collection("address").doc(ordDoc.data().addressID).get();
                                if (addrDoc.exists) {
                                    const ad = addrDoc.data();
                                    const la = ad.lat || ad.latitude;
                                    const lo = ad.lng || ad.longitude;
                                    if (la && lo) {
                                        lastEndLat = Number(la);
                                        lastEndLng = Number(lo);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Fallback to staff's registered work location if no prior task exists
            if (!lastEndLat || !lastEndLng) {
                if (d.workLocation && d.workLocation.lat && d.workLocation.lng) {
                    lastEndLat = Number(d.workLocation.lat);
                    lastEndLng = Number(d.workLocation.lng);
                } else {
                    lastEndLat = 5.3542;
                    lastEndLng = 100.3015;
                }
            }

            const distKm = calculateHaversineKm(lastEndLat, lastEndLng, destLat, destLng);

            // Availability timing:
            // "Now", or if today over 9am show tomorrow's available time, or if 00:00-08:59 show today's available time
            let availableText = "Now";
            let isImmediate = false;

            const isBusyNow = todayActive.some(s => {
                const sStart = parseScheduleDate(s.scheduleStartTime, todayStr);
                const sEnd = parseScheduleDate(s.scheduleEndTime, todayStr);
                if (sStart && sEnd) {
                    return myNow >= sStart && myNow <= sEnd;
                }
                const start = s.scheduleStartTime || "00:00";
                const end = s.scheduleEndTime || "23:59";
                return currentTimeStr >= start && currentTimeStr <= end;
            });

            if (isWithinWorkingHours && !isBusyNow && activeCount < 8) {
                availableText = "Now";
                isImmediate = true;
            } else if (isOver9am) {
                // If today is over 9am: show what time available tomorrow
                const tmrTasks = staffScheds.filter(s => s.scheduleDate === tomorrowStr && s.scheduleStatus !== "cancelled" && s.scheduleStatus !== "rejected");
                if (tmrTasks.length > 0) {
                    tmrTasks.sort((a, b) => {
                        const tA = parseScheduleDate(a.scheduleEndTime || a.scheduleStartTime, tomorrowStr) || new Date(0);
                        const tB = parseScheduleDate(b.scheduleEndTime || b.scheduleStartTime, tomorrowStr) || new Date(0);
                        return tB.getTime() - tA.getTime();
                    });
                    const lastTask = tmrTasks[0];
                    const timeStr = formatTimeHHmmMY(lastTask.scheduleEndTime || lastTask.scheduleStartTime);
                    availableText = `Tomorrow ${timeStr}`;
                } else {
                    availableText = "Tomorrow 09:00";
                }
                isImmediate = false;
            } else {
                // If today is with 00:00 to 08:59: show what time available today
                const todayScheduled = staffScheds.filter(s => s.scheduleDate === todayStr && s.scheduleStatus !== "cancelled" && s.scheduleStatus !== "rejected");
                if (todayScheduled.length > 0) {
                    todayScheduled.sort((a, b) => {
                        const tA = parseScheduleDate(a.scheduleEndTime || a.scheduleStartTime, todayStr) || new Date(0);
                        const tB = parseScheduleDate(b.scheduleEndTime || b.scheduleStartTime, todayStr) || new Date(0);
                        return tB.getTime() - tA.getTime();
                    });
                    const lastTask = todayScheduled[0];
                    const timeStr = formatTimeHHmmMY(lastTask.scheduleEndTime || lastTask.scheduleStartTime);
                    availableText = `Today ${timeStr}`;
                } else {
                    availableText = "Today 09:00";
                }
                isImmediate = false;
            }

            // Initials or photo
            const initials = fullName.split(" ").map(w => w[0]).filter(Boolean).slice(0, 2).join("").toUpperCase();

            eligibleStaff.push({
                staffID,
                name: fullName,
                email: d.email || "",
                phone: d.phoneNumber || "",
                position: d.position || "Staff",
                initials,
                photoUrl: d.photoUrl || d.avatar || "",
                specialization: specs,
                specializationTag,
                activeTasks: activeCount,
                maxTasks,
                workloadText,
                distanceKm: distKm,
                availableText,
                isImmediate,
                state: staffState
            });
        }

        // Sort: Least active tasks first, then closest distance
        eligibleStaff.sort((a, b) => {
            if (a.activeTasks !== b.activeTasks) return a.activeTasks - b.activeTasks;
            return a.distanceKm - b.distanceKm;
        });

        return res.json({
            success: true,
            taskDetail: {
                orderID,
                taskID,
                taskType: isDelivery ? "deliver" : "inspection",
                taskTypeLabel,
                displayStatus,
                previousStaffName,
                cancellationReason,
                device: {
                    name: deviceName,
                    brand: deviceBrand,
                    model: deviceModel,
                    storage: deviceStorage,
                    color: deviceColor,
                    imei: deviceImei
                },
                location: locationDisplay,
                priority: isUrgent ? "High" : "Normal",
                appointmentDate: formatAppointmentDate(orderDateRaw),
                orderDate: orderDateRaw,
                orderDateFormatted: formatOrderDateTime(orderDateRaw),
                createdAtMs: getOrderTimestamp(orderData),
                totalAmount: orderData.totalAmount || 0,
                fulfillmentType
            },
            staff: eligibleStaff
        });
    } catch (err) {
        console.error("Error in GET /admin/reassign-candidates:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

/**
 * POST /api/task-assignment/admin/reassign
 * Reassigns an unassigned or cancelled order either automatically or manually to a staff member
 */
router.post("/admin/reassign", async (req, res) => {
    try {
        const { orderID, staffID, addressID, requestedDate } = req.body;
        if (!orderID) {
            return res.status(400).json({ success: false, error: "orderID is required" });
        }

        // If staffID is provided, do manual assignment
        if (staffID && staffID !== "auto") {
            const staffDoc = await db.collection("users").doc(staffID).get();
            if (!staffDoc.exists) {
                return res.status(404).json({ success: false, error: "Staff not found" });
            }
            const staffData = staffDoc.data();
            const staffName = staffData.fullName || staffData.name || "Assigned Staff";

            const scheduleID = `SCH-${orderID}-${Date.now().toString().slice(-4)}`;
            const taskID = `TSK-${orderID}`;
            const schedDateStr = new Date().toISOString().split("T")[0];

            const batch = db.batch();

            // 1. Create or update schedule
            batch.set(db.collection("schedule").doc(scheduleID), {
                scheduleID,
                orderID,
                staffID,
                staffName,
                scheduleDate: schedDateStr,
                scheduleStartTime: "09:00",
                scheduleEndTime: "17:00",
                scheduleStatus: "assigned",
                updatedAt: new Date()
            }, { merge: true });

            // 2. Update task
            batch.set(db.collection("task").doc(taskID), {
                taskID,
                orderID,
                staffID,
                staffName,
                scheduleID,
                taskType: "deliver",
                taskStatus: "Packaging",
                taskStartTime: "09:00",
                rejectionReason: null,
                rejectionNotes: null,
                updatedAt: new Date()
            }, { merge: true });

            // 3. Update order
            batch.set(db.collection("order").doc(orderID), {
                orderStatus: "Delivering",
                updatedAt: new Date()
            }, { merge: true });

            // 4. Update delivery
            const delID = `DEL-${orderID}`;
            batch.set(db.collection("delivery").doc(delID), {
                deliveryStatus: "ongoing",
                updatedAt: new Date()
            }, { merge: true });

            await batch.commit();

            return res.json({
                success: true,
                message: `Order #${orderID} successfully reassigned to ${staffName}.`,
                scheduleID,
                staffID,
                staffName
            });
        }

        // Auto assignment via taskAssignmentService
        const result = await assignDeliveryTask({
            orderID,
            addressID,
            requestedDate: requestedDate ? new Date(requestedDate) : new Date()
        });

        return res.json(result);
    } catch (err) {
        console.error("Error in POST /admin/reassign:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

/**
 * POST /api/task-assignment/admin/terminate
 * Terminate a task / order
 */
router.post("/admin/terminate", async (req, res) => {
    try {
        const { orderID, taskID, reason } = req.body;
        if (!orderID && !taskID) {
            return res.status(400).json({ success: false, error: "orderID or taskID is required" });
        }

        const batch = db.batch();
        const termReason = reason || "Terminated by administrator - changed to Self Pickup";

        const targetTaskID = taskID || `TSK-${orderID}`;
        const taskRef = db.collection("task").doc(targetTaskID);
        const taskSnap = await taskRef.get();
        let schedID = null;
        if (taskSnap.exists) {
            schedID = taskSnap.data().scheduleID;
        }

        // 1. Task: follow exact same as rejected by staff (taskStatus = "Rejected")
        batch.set(taskRef, {
            taskStatus: "Rejected",
            rejectionReason: termReason,
            terminatedAt: new Date(),
            updatedAt: new Date()
        }, { merge: true });

        // 2. Schedule: follow exact same as rejected by staff (scheduleStatus = "rejected")
        if (schedID) {
            batch.set(db.collection("schedule").doc(schedID), {
                scheduleStatus: "rejected",
                rejectionReason: termReason,
                updatedAt: new Date()
            }, { merge: true });
        }

        // 3. Delivery & Order
        if (orderID) {
            // Delivery: follow exact same as rejected by staff (deliveryStatus = "cancelled")
            const delID = `DEL-${orderID}`;
            batch.set(db.collection("delivery").doc(delID), {
                deliveryStatus: "cancelled",
                updatedAt: new Date()
            }, { merge: true });

            // Order: change to "Self pickup"
            batch.set(db.collection("order").doc(orderID), {
                orderStatus: "Self pickup",
                fulfillmentType: "Self Pickup",
                terminationReason: termReason,
                terminatedAt: new Date(),
                updatedAt: new Date()
            }, { merge: true });
        }

        await batch.commit();

        return res.json({
            success: true,
            message: `Task for order #${orderID || targetTaskID} has been terminated and changed to Self Pickup.`
        });
    } catch (err) {
        console.error("Error in POST /admin/terminate:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

/**
 * GET /api/task-assignment/admin/criteria
 * Returns the task assignment rules and criteria
 */
router.get("/admin/criteria", (req, res) => {
    return res.json({
        success: true,
        criteria: {
            workingHours: "9:00 AM - 5:00 PM (09:00 - 17:00)",
            lunchBreak: "12:00 PM - 1:00 PM (12:00 - 13:00, Protected)",
            slotInterval: "1 hour per task slot",
            defaultBuffer: "15 minutes between consecutive tasks",
            shortDistanceBuffer: "10 minutes if travel distance < 500m (0.5 km)",
            maxDeliveriesPerDay: 8,
            routingEngine: "OpenStreetMap OSRM with live traffic routing",
            geocoding: "Nominatim exact coordinates resolution"
        }
    });
});

module.exports = router;
