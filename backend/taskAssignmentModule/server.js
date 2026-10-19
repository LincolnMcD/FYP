const express = require("express");
const router = express.Router();
const db = require("../config/firebase");
const { assignDeliveryTask } = require("./taskAssignmentService");

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
        const { taskID, orderID, scheduleID, status } = req.body;
        // status can be 'Packaging', 'Shipping' (In Progress), 'Delivered' (Completed)
        const normalized = String(status || "").trim();

        const batch = db.batch();

        if (taskID) {
            batch.set(db.collection("task").doc(taskID), {
                taskStatus: normalized,
                updatedAt: new Date()
            }, { merge: true });
        }

        if (scheduleID) {
            let schedStatus = "assigned";
            if (normalized === "Shipping" || normalized === "In Progress" || normalized === "ongoing") schedStatus = "ongoing";
            if (normalized === "Delivered" || normalized === "Completed" || normalized === "completed") schedStatus = "completed";

            // Update scheduleStatus without Timestamp objects
            batch.set(db.collection("schedule").doc(scheduleID), {
                scheduleStatus: schedStatus
            }, { merge: true });
        }

        // Delivery status strictly ongoing or completed ONLY
        let deliveryStatus = "ongoing";
        if (normalized === "Delivered" || normalized === "Completed" || normalized === "completed") {
            deliveryStatus = "completed";
        } else {
            deliveryStatus = "ongoing";
        }

        const delID = `DEL-${orderID}`;
        const delRef = db.collection("delivery").doc(delID);
        const delSnap = await delRef.get();
        if (delSnap.exists) {
            // delivery: deliveryStatus (ongoing or completed ONLY), no deliveredAt or pickUpAt
            batch.set(delRef, { deliveryStatus }, { merge: true });
        }

        if (orderID && (normalized === "Delivered" || normalized === "Completed")) {
            batch.set(db.collection("order").doc(orderID), {
                orderStatus: "Delivered",
                updatedAt: new Date()
            }, { merge: true });
        }

        await batch.commit();

        return res.json({ success: true, message: `Task status updated to ${normalized}` });
    } catch (err) {
        console.error("Error updating task status:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

module.exports = router;
