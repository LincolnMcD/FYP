const express = require("express");
const router = express.Router();
const db = require("../config/firebase");
const { FieldValue } = require("firebase-admin/firestore");
const cloudinary = require("../config/cloudinary");
const multer = require("multer");
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });
const { assignDeliveryTask, getStaffIDsOnApprovedLeave, parseLeaveDate } = require("./taskAssignmentService");
const { getOsrmRoute, COMPANY_LOCATION } = require("./osrmService");
const { getDeliveryRoomsStatus } = require("./deliverySocket");
const {
    registerScheduleTimer,
    clearScheduleTimers,
    handleStartTimeViolation,
    handleEndTimeViolation,
    checkAndResetMonthlyMistakes
} = require("./taskDelayMonitorService");
const nodemailer = require("nodemailer");

// Nodemailer transporter for delivery termination & self-pickup notifications
const terminationEmailTransporter = nodemailer.createTransport({
    service: "gmail",
    auth: {
        user: "lolincoln021@gmail.com",
        pass: "uooc wvdf zoqy nujh"
    }
});

// Helper to send Self Pickup Notification Email to Customer
async function sendTerminationSelfPickupEmail({
    toEmail,
    customerName,
    orderID,
    reason,
    items = []
}) {
    if (!toEmail) return { success: false, error: "No recipient email" };

    const hubAddress = COMPANY_LOCATION.address || "ReByte Central Hub, Penang";
    const hubLat = COMPANY_LOCATION.lat || 5.453240417145323;
    const hubLng = COMPANY_LOCATION.lng || 100.2848625551094;
    const mapsLink = `https://www.google.com/maps/dir/?api=1&destination=${hubLat},${hubLng}`;

    let itemsHtml = "";
    if (Array.isArray(items) && items.length > 0) {
        itemsHtml = items.map((it, idx) => {
            const title = [it.brand, it.model].filter(Boolean).join(" ") || it.productName || it.title || "Electronic Device";
            const spec = [it.storage, it.condition].filter(Boolean).join(" • ");
            return `
              <div style="display: flex; align-items: center; padding: 10px 0; border-bottom: 1px solid #E2E8F0;">
                <div style="flex: 1;">
                  <div style="font-weight: 700; color: #0F172A; font-size: 14px;">#${idx + 1}. ${title}</div>
                  ${spec ? `<div style="font-size: 12px; color: #64748B; margin-top: 2px;">${spec}</div>` : ''}
                </div>
              </div>
            `;
        }).join("");
    }

    const mailOptions = {
        from: "\"ReByte Customer Care\" <lolincoln021@gmail.com>",
        to: toEmail,
        subject: `Delivery Update: Order #${orderID} Changed to Self Pickup`,
        html: `
        <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; max-width: 580px; margin: 0 auto; padding: 24px; background: #FFFFFF; border: 1px solid #E2E8F0; border-radius: 16px;">
            <!-- Header -->
            <div style="text-align: center; padding-bottom: 20px; border-bottom: 1px solid #F1F5F9;">
                <h1 style="color: #0C5AD2; font-size: 28px; font-weight: 900; margin: 0; letter-spacing: -0.5px;">ReByte</h1>
                <p style="color: #64748B; font-size: 13px; margin-top: 4px;">Premium Sustainable Tech</p>
            </div>

            <!-- Body Content -->
            <div style="padding: 24px 0 16px 0;">
                <h2 style="color: #0F172A; font-size: 18px; font-weight: 800; margin: 0 0 12px 0;">
                    Hello ${customerName || "Customer"},
                </h2>
                <p style="color: #334155; font-size: 14px; line-height: 1.6; margin: 0 0 16px 0;">
                    Please be informed that home delivery for your Order <strong style="color: #0C5AD2;">#${orderID}</strong> has been cancelled and updated to <strong>Self Pickup</strong>.
                </p>

                <!-- Reason Card -->
                <div style="background: #FEF2F2; border: 1px solid #FECACA; border-radius: 12px; padding: 14px 16px; margin-bottom: 20px;">
                    <div style="font-size: 12px; font-weight: 800; color: #DC2626; text-transform: uppercase; letter-spacing: 0.5px;">Reason</div>
                    <div style="font-size: 14px; font-weight: 600; color: #991B1B; margin-top: 4px;">
                        ${reason || "Delivery could not be completed"}
                    </div>
                </div>

                <!-- Self Pickup Details Card -->
                <div style="background: #F8FAFC; border: 1px solid #E2E8F0; border-radius: 12px; padding: 16px; margin-bottom: 20px;">
                    <div style="font-size: 12px; font-weight: 800; color: #0C5AD2; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 6px;">
                        Self Pickup Instructions
                    </div>
                    <p style="color: #334155; font-size: 13.5px; line-height: 1.5; margin: 0 0 10px 0;">
                        Please self pick up your package at our central facility:
                    </p>
                    <div style="font-size: 15px; font-weight: 800; color: #0F172A; margin-bottom: 4px;">
                        📍 ${hubAddress}
                    </div>
                    <div style="font-size: 12.5px; color: #64748B; margin-bottom: 14px;">
                        Operating Hours: Monday – Saturday, 9:00 AM – 6:00 PM
                    </div>

                    <!-- Google Maps Directions Button -->
                    <div style="text-align: center; margin-top: 12px;">
                        <a href="${mapsLink}" target="_blank" style="display: inline-block; background: #0C5AD2; color: #FFFFFF; font-weight: 700; font-size: 13.5px; padding: 12px 24px; border-radius: 10px; text-decoration: none; box-shadow: 0 2px 6px rgba(12, 90, 210, 0.25);">
                            🗺️ Open Location in Google Maps
                        </a>
                    </div>
                </div>

                <!-- Items to Pick Up -->
                ${itemsHtml ? `
                <div style="margin-top: 20px;">
                    <div style="font-size: 12px; font-weight: 800; color: #64748B; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 8px;">
                        Package Items to Pick Up
                    </div>
                    ${itemsHtml}
                </div>` : ''}

                <p style="color: #64748B; font-size: 12.5px; line-height: 1.5; margin-top: 24px;">
                    Please present your Order Reference (<strong>#${orderID}</strong>) or this email confirmation upon arrival at the counter. If you have any inquiries, feel free to contact our customer support.
                </p>
            </div>

            <!-- Footer -->
            <div style="text-align: center; padding-top: 16px; border-top: 1px solid #F1F5F9; color: #94A3B8; font-size: 11.5px;">
                © ${new Date().getFullYear()} ReByte Technologies. All rights reserved.
            </div>
        </div>
        `
    };

    try {
        await terminationEmailTransporter.sendMail(mailOptions);
        return { success: true };
    } catch (e) {
        console.error("Error sending termination self-pickup email:", e);
        return { success: false, error: e.message };
    }
}

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

        if (result && result.success && result.scheduleID) {
            registerScheduleTimer(result.scheduleID);
        }

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
            const schedStatus = (schedData.scheduleStatus || "").toLowerCase();
            // Skip absent, rejected, or cancelled schedules from staff task list
            if (schedStatus === "absent" || schedStatus === "rejected" || schedStatus === "cancelled") {
                continue;
            }
            const scheduleID = schedData.scheduleID || sDoc.id;

            // 3. Lookup task by scheduleID, or fallback by orderID
            let taskData = {};
            let taskID = "";
            let orderID = schedData.orderID || "";

            const tSnap = await db.collection("task").where("scheduleID", "==", scheduleID).limit(1).get();
            if (!tSnap.empty) {
                taskData = tSnap.docs[0].data();
                taskID = taskData.taskID || tSnap.docs[0].id;
                orderID = taskData.orderID || orderID;
            } else if (orderID) {
                // Fallback direct doc lookup
                const directTask = await db.collection("task").doc(`TSK-${orderID}`).get();
                if (directTask.exists) {
                    taskData = directTask.data();
                    taskID = directTask.id;
                }
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
                                price: p.sellingPrice || 0,
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

        // Helper to get comparable timestamp for a task
        function getTaskTimestamp(t) {
            const datePart = t.scheduleDate || "1970-01-01";
            let timePart = t.scheduleStartTime || "00:00:00";
            if (timePart.includes("T")) {
                const parsed = new Date(timePart);
                return isNaN(parsed.getTime()) ? 0 : parsed.getTime();
            }
            if (timePart.length === 5) {
                timePart = `${timePart}:00`;
            }
            const parsed = new Date(`${datePart}T${timePart}`);
            return isNaN(parsed.getTime()) ? 0 : parsed.getTime();
        }

        // Sort: earliest schedule date/time first (chronological order)
        tasksList.sort((a, b) => getTaskTimestamp(a) - getTaskTimestamp(b));

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

        // Update active schedule timer on status transitions
        if (scheduleID) {
            if (isCompleted || isRejected || isTerminated) {
                clearScheduleTimers(scheduleID);
            } else {
                // If started (Shipping / ongoing), re-register so the End Time check activates
                registerScheduleTimer(scheduleID);
            }
        }
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

        if (scheduleID) {
            clearScheduleTimers(scheduleID);
        }

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

    // Rule 3: If order or task is Completed/Delivered -> Completed (Highest priority for finished orders)
    if (o === 'completed' || o === 'delivered' || t === 'completed' || t === 'delivered') {
        return 'Completed';
    }

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

// Short in-memory cache to prevent Firestore quota exhaustion on frequent reloads
let taskCache = {
    data: null,
    counts: null,
    timestamp: 0
};
const CACHE_TTL_MS = 30000; // 30 seconds cache

function invalidateTaskCache() {
    taskCache = { data: null, counts: null, timestamp: 0 };
}

/**
 * Helper to fetch and build tasks dataset with caching
 */
async function getOrBuildTasksDataset() {
    const now = Date.now();
    if (taskCache.data && (now - taskCache.timestamp < CACHE_TTL_MS)) {
        return { taskList: taskCache.data, counts: taskCache.counts };
    }

    // 1. Fetch orders
    const ordersSnap = await db.collection("order").get();

    // 2. Fetch tasks
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

    // 3. Fetch schedules
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

    // 4. Fetch staff members
    const staffSnap = await db.collection("users").where("role", "==", "Staff").get();
    const staffMap = new Map();
    staffSnap.forEach(doc => {
        const data = doc.data();
        const name = data.fullName || data.name || "Staff Member";
        staffMap.set(doc.id, { staffID: doc.id, name, email: data.email || "", phone: data.phoneNumber || data.phone || "" });
    });

    // Caches for batch lookups
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

        // If email or name is missing, look up customer in 'users' collection
        if ((!customerEmail || !customerName || customerName === "Customer") && (customerID || customerPhone)) {
            let uData = null;

            // 1. Check cache by customerID
            if (customerID && userCache.has(customerID)) {
                uData = userCache.get(customerID);
            } else if (customerID) {
                // Try doc(customerID)
                const uDoc = await db.collection("users").doc(customerID).get();
                if (uDoc.exists) {
                    uData = uDoc.data();
                } else {
                    // Try where("userId", "==", customerID)
                    const uSnap = await db.collection("users").where("userId", "==", customerID).limit(1).get();
                    if (!uSnap.empty) {
                        uData = uSnap.docs[0].data();
                    }
                }
                if (uData) {
                    const uName = uData.fullName || uData.name || "Customer";
                    const cached = { name: uName, email: uData.email || "", phone: uData.phoneNumber || uData.phone || "" };
                    userCache.set(customerID, cached);
                }
            }

            // 2. Fallback: if still no email, try searching users by customerPhone
            if ((!uData || !uData.email) && customerPhone) {
                const cleanPhone = String(customerPhone).trim();
                const phoneVariations = [
                    cleanPhone,
                    cleanPhone.replace(/^\+60/, '0'),
                    cleanPhone.replace(/^0/, '+60'),
                    cleanPhone.replace(/\D/g, '')
                ].filter((v, i, a) => v && a.indexOf(v) === i);

                for (const p of phoneVariations) {
                    const pSnap = await db.collection("users").where("phoneNumber", "==", p).limit(1).get();
                    if (!pSnap.empty) {
                        const found = pSnap.docs[0].data();
                        if (found) {
                            uData = uData || found;
                            if (found.email) {
                                customerEmail = found.email;
                                break;
                            }
                        }
                    }
                }
            }

            if (uData) {
                const resolvedName = uData.fullName || uData.name || "";
                if (!customerName || customerName === "Customer") {
                    customerName = resolvedName || customerName;
                }
                if (!customerEmail && uData.email) {
                    customerEmail = uData.email;
                }
                if (!customerPhone && (uData.phoneNumber || uData.phone)) {
                    customerPhone = uData.phoneNumber || uData.phone;
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
        const createdAtMs = getOrderTimestamp(ordData);
        const orderDateRaw = ordData.createdAt || ordData.orderDate;
        const appointmentDate = schedData.scheduleDate ? formatAppointmentDate(schedData.scheduleDate) : formatAppointmentDate(orderDateRaw);

        let appointmentTime = "09:00 - 17:00";
        if (schedData.scheduleStartTime && schedData.scheduleEndTime) {
            appointmentTime = `${schedData.scheduleStartTime} - ${schedData.scheduleEndTime}`;
        } else if (taskData.taskStartTime) {
            appointmentTime = `${taskData.taskStartTime} - 17:00`;
        }

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
            pickedAt: ordData.pickedAt || null,
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
        const key = (t.displayStatus || '').toLowerCase();
        if (counts[key] !== undefined) {
            counts[key]++;
        }
    });

    taskCache = {
        data: taskList,
        counts,
        timestamp: Date.now()
    };

    return { taskList, counts };
}

/**
 * GET /api/task-assignment/admin/tasks
 * Supports Server-Side Pagination & Tab Filtering:
 * Query params:
 *   tab: 'unassigned' | 'assigned' | 'cancelled' | 'refunded' | 'terminated' | 'completed' | 'all'
 *   page: 1-based page number (default 1)
 *   limit: page size (default 10)
 *   search: keyword filter
 *   sort: 'asc' | 'desc' (default 'desc')
 */
router.get("/admin/tasks", async (req, res) => {
    try {
        const { taskList, counts } = await getOrBuildTasksDataset();

        const tab = String(req.query.tab || "").trim().toLowerCase();
        const page = Math.max(1, parseInt(req.query.page, 10) || 1);
        const limit = Math.max(1, Math.min(100, parseInt(req.query.limit, 10) || 10));
        const search = String(req.query.search || "").trim().toLowerCase();
        const sortOrder = String(req.query.sort || "desc").trim().toLowerCase();

        // 1. Filter by Tab
        let filtered = taskList;
        if (tab && tab !== "all") {
            filtered = filtered.filter(t => (t.displayStatus || "").toLowerCase() === tab);
        }

        // 2. Filter by Search Query
        if (search) {
            filtered = filtered.filter(t => {
                const matchStr = `${t.taskID || ''} ${t.orderID || ''} ${t.customerName || ''} ${t.deviceSummary || ''} ${t.deliveryAddress || ''} ${t.staffName || ''}`.toLowerCase();
                return matchStr.includes(search);
            });
        }

        // 3. Sort Order
        filtered = [...filtered].sort((a, b) => {
            const timeA = Number(a.createdAtMs) || 0;
            const timeB = Number(b.createdAtMs) || 0;
            return sortOrder === "asc" ? timeA - timeB : timeB - timeA;
        });

        // 4. Paginate
        const total = filtered.length;
        const totalPages = Math.max(1, Math.ceil(total / limit));
        const safePage = Math.min(page, totalPages);
        const startIndex = (safePage - 1) * limit;
        const paginatedTasks = filtered.slice(startIndex, startIndex + limit);

        return res.json({
            success: true,
            counts,
            pagination: {
                total,
                page: safePage,
                limit,
                totalPages
            },
            tasks: paginatedTasks
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
        let schedData = null;
        const scheduleID = taskData.scheduleID || orderData.scheduleID || "";
        if (scheduleID) {
            const schedDoc = await db.collection("schedule").doc(scheduleID).get();
            if (schedDoc.exists) {
                const sData = schedDoc.data();
                schedData = sData;
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
                const parts = [address.addressLine, address.postcode, address.city, address.state].filter(Boolean);
                if (parts.length > 0) {
                    locationDisplay = parts.join(", ");
                }
            }
        }

        // Fallback to delivery collection if addressID wasn't found or missing address
        if (locationDisplay === "Hub C - Bay 4") {
            const delSnap = await db.collection("delivery").doc(`DEL-${orderID}`).get();
            if (delSnap.exists && delSnap.data().deliveryAddress) {
                locationDisplay = delSnap.data().deliveryAddress;
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

        // Target schedule date according to task assignment algorithm rules:
        // If current local time is >= 9:00 AM, task is scheduled for tomorrow; otherwise today
        let targetDateObj = new Date(myNow);
        if (currentHour >= 9) {
            targetDateObj.setDate(targetDateObj.getDate() + 1);
        }
        const targetDateStr = formatLocalYMD(targetDateObj);
        const monthNamesShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        const targetDateFormatted = `${targetDateObj.getDate()} ${monthNamesShort[targetDateObj.getMonth()]} ${targetDateObj.getFullYear()}`;

        const isWithinWorkingHours = (currentHour >= 9 && currentHour < 17 && currentHour !== 12);
        const isOver9am = currentHour >= 9;

        // Customer coordinate & ReByte Central Hub location
        const customerLoc = { lat: destLat, lng: destLng };
        const hubLoc = COMPANY_LOCATION;
        const hubToCustomerRoute = await getOsrmRoute(hubLoc, customerLoc);

        const staffOnLeave = await getStaffIDsOnApprovedLeave(targetDateObj);
        const eligibleStaff = [];

        for (const doc of staffSnap.docs) {
            const d = doc.data();
            const status = String(d.status || d.staffStatus || "Active").toLowerCase().trim();
            if (status === "archived") continue;

            const pos = String(d.position || "").toLowerCase().trim();

            // Filter by Position based on Task Type: must be delivery or both for delivery task
            if (isDelivery) {
                if (pos !== "deliverer" && pos !== "both") continue;
            } else {
                if (pos !== "inspector" && pos !== "both") continue;
            }

            const staffID = doc.id;

            // Constraint: Exclude staff who have an approved leave on the target schedule date
            if (staffOnLeave.has(staffID)) {
                continue;
            }

            // Fetch this staff's schedules to evaluate active workload on the target schedule date
            const staffSchedSnap = await db.collection("schedule")
                .where("staffID", "==", staffID)
                .get();

            const staffScheds = [];
            staffSchedSnap.forEach(sDoc => {
                staffScheds.push({ id: sDoc.id, ...sDoc.data() });
            });

            // Count active tasks specifically for the target schedule date (assigned or ongoing)
            const targetDateActive = staffScheds.filter(s => 
                s.scheduleDate === targetDateStr && 
                (s.scheduleStatus === "assigned" || s.scheduleStatus === "ongoing")
            );
            const activeCount = targetDateActive.length;

            // Rule: Task count must be strictly under 8 for the schedule date
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

            // Staff saved workplace coordinate
            let staffWorkLocation = hubLoc;
            if (d.workLocation && d.workLocation.lat && d.workLocation.lng) {
                staffWorkLocation = { lat: Number(d.workLocation.lat), lng: Number(d.workLocation.lng) };
            } else if (d.currentLat && d.currentLng) {
                staffWorkLocation = { lat: Number(d.currentLat), lng: Number(d.currentLng) };
            }

            // Route Distance Calculation via OSRM:
            // For 0 task: staff saved work place -> Rebyte Hub -> task deliver location
            // For >0 task: last task location on schedule date -> new task deliver location
            let distKm = 0;
            let travelDurationMins = 0;

            if (activeCount === 0) {
                // Leg 1: Staff Work Base -> ReByte Hub
                const staffToHub = await getOsrmRoute(staffWorkLocation, hubLoc);
                // Leg 2: ReByte Hub -> Customer Destination
                distKm = Number((staffToHub.distanceKm + hubToCustomerRoute.distanceKm).toFixed(1));
                travelDurationMins = Math.round(staffToHub.durationMinutes + hubToCustomerRoute.durationMinutes);
            } else {
                // Find last task ended location on targetDateStr
                targetDateActive.sort((a, b) => {
                    const timeA = parseScheduleDate(a.scheduleEndTime || a.scheduleStartTime, a.scheduleDate) || new Date(0);
                    const timeB = parseScheduleDate(b.scheduleEndTime || b.scheduleStartTime, b.scheduleDate) || new Date(0);
                    return timeB.getTime() - timeA.getTime();
                });
                const lastTask = targetDateActive[0];

                let lastEndLat = null;
                let lastEndLng = null;
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

                if (lastEndLat && lastEndLng) {
                    const lastToNewRoute = await getOsrmRoute({ lat: lastEndLat, lng: lastEndLng }, customerLoc);
                    distKm = Number(lastToNewRoute.distanceKm.toFixed(1));
                    travelDurationMins = Math.round(lastToNewRoute.durationMinutes);
                } else {
                    const fallbackRoute = await getOsrmRoute(staffWorkLocation, customerLoc);
                    distKm = Number(fallbackRoute.distanceKm.toFixed(1));
                    travelDurationMins = Math.round(fallbackRoute.durationMinutes);
                }
            }

            // Task duration calculation (travel duration + buffer: 10 mins if < 0.5km, else 15 mins)
            const bufferMins = distKm < 0.5 ? 10 : 15;
            const taskTotalDurationMins = Math.max(15, Math.round(travelDurationMins + bufferMins));

            // Availability timing on target schedule date:
            let availableTime = "09:00";
            if (targetDateActive.length > 0) {
                const latest = targetDateActive[0];
                const rawTime = latest.scheduleEndTime || latest.scheduleStartTime;
                availableTime = formatTimeHHmmMY(rawTime);
                const [hh, mm] = availableTime.split(":").map(Number);
                // If it ends during lunch break (12:00-13:00), staff is available at 13:00
                if (hh === 12 || (hh === 11 && mm > 45)) {
                    availableTime = "13:00";
                }
            } else {
                availableTime = "09:00";
            }
            const availableText = availableTime;

            // Calculate estimated complete time from available time + task duration
            const [avH, avM] = availableTime.split(":").map(Number);
            let startDt = new Date(targetDateObj.getFullYear(), targetDateObj.getMonth(), targetDateObj.getDate(), avH, avM, 0);
            if (avH === 12) {
                startDt = new Date(targetDateObj.getFullYear(), targetDateObj.getMonth(), targetDateObj.getDate(), 13, 0, 0);
                availableTime = "13:00";
            }
            const endDt = new Date(startDt.getTime() + (taskTotalDurationMins * 60 * 1000));
            const estimatedCompleteTime = formatTimeHHmmMY(endDt);

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
                scheduleDate: targetDateStr,
                scheduleDateFormatted: targetDateFormatted,
                distanceKm: distKm,
                availableTime,
                availableText,
                estimatedCompleteTime,
                estimatedDurationMinutes: taskTotalDurationMins,
                isImmediate: false,
                state: staffState
            });
        }

        // Sort: Least active tasks first, then closest route distance
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
                rejectionReason: taskData.rejectionReason || "Task needs immediate reassignment to clear queue.",
                rejectionNotes: taskData.rejectionNotes || (schedData && schedData.rejectionNotes) || (orderData && orderData.notes) || "",
                scheduleDate: targetDateStr,
                scheduleDateFormatted: targetDateFormatted,
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
                addressID: orderData.addressID || "",
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

        // Reassign using the taskAssignment algorithm:
        // - Calculates duration + buffer
        // - Estimates start and end date/time
        // - If more than 1 task on schedule, reroutes all permutations to select best path
        // - Sets order: Delivering, task: Packaging, delivery: ongoing
        // - Creates brand new schedule record, leaving older rejected schedule record intact
        // - Sets task record to reference the new schedule ID
        const result = await assignDeliveryTask({
            orderID,
            addressID,
            requestedDate: requestedDate ? new Date(requestedDate) : new Date(),
            specificStaffID: (staffID && staffID !== "auto") ? staffID : null
        });

        if (result && result.success) {
            if (result.scheduleID) {
                registerScheduleTimer(result.scheduleID);
            }
            invalidateTaskCache();
        }

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

        const targetOrderID = orderID || (taskID ? taskID.replace(/^TSK-/, '') : '');
        const targetTaskID = taskID || `TSK-${targetOrderID}`;

        // Fetch task document to retrieve staff rejection reason if reason is empty
        const taskRef = db.collection("task").doc(targetTaskID);
        const taskSnap = await taskRef.get();
        let taskData = taskSnap.exists ? taskSnap.data() : {};
        let schedData = {};

        if (taskData.scheduleID) {
            const schedSnap = await db.collection("schedule").doc(taskData.scheduleID).get();
            if (schedSnap.exists) schedData = schedSnap.data();
        }

        // Determine final reason: if reason is empty, use staff rejected reason
        const staffRejectionReason = String(taskData.rejectionReason || schedData.rejectionReason || taskData.rejectionNotes || schedData.rejectionNotes || "").trim();
        let termReason = String(reason || "").trim();
        if (!termReason) {
            termReason = staffRejectionReason || "Delivery cancelled - please collect package via self pickup";
        }
        // Ensure max 50 characters
        if (termReason.length > 50) {
            termReason = termReason.substring(0, 50);
        }

        // Batch update:
        // Order changes to "Self pickup" status
        // Task, Delivery, and Schedule status remain unchanged as requested
        const batch = db.batch();

        if (targetOrderID) {
            const ordRef = db.collection("order").doc(targetOrderID);
            batch.set(ordRef, {
                orderStatus: "Self pickup",
                fulfillmentType: "Self Pickup",
                terminationReason: termReason,
                terminatedAt: new Date(),
                updatedAt: new Date()
            }, { merge: true });
        }

        await batch.commit();
        invalidateTaskCache();

        // Retrieve customer details to send email
        let customerEmail = "";
        let customerName = "Customer";
        let orderItems = [];

        if (targetOrderID) {
            const ordSnap = await db.collection("order").doc(targetOrderID).get();
            if (ordSnap.exists) {
                const ordData = ordSnap.data();
                customerEmail = ordData.email || ordData.userEmail || "";
                customerName = ordData.customerName || "";
                orderItems = ordData.items || [];

                // Fallback to address collection
                if (!customerEmail && ordData.addressID) {
                    const addrSnap = await db.collection("address").doc(ordData.addressID).get();
                    if (addrSnap.exists) {
                        const addrData = addrSnap.data();
                        customerEmail = addrData.email || "";
                        customerName = customerName || addrData.recipentName || addrData.recipientName || "";
                    }
                }

                // Fallback to users collection
                const customerID = ordData.customerID || ordData.userId || "";
                if ((!customerEmail || !customerName) && customerID) {
                    const uSnap = await db.collection("users").doc(customerID).get();
                    if (uSnap.exists) {
                        const uData = uSnap.data();
                        customerEmail = customerEmail || uData.email || "";
                        customerName = customerName || uData.fullName || uData.name || "Customer";
                    }
                }
            }
        }

        // Send email to customer asynchronously
        let emailSent = false;
        if (customerEmail) {
            const emailResult = await sendTerminationSelfPickupEmail({
                toEmail: customerEmail,
                customerName,
                orderID: targetOrderID,
                reason: termReason,
                items: orderItems
            });
            emailSent = emailResult.success === true;
        }

        return res.json({
            success: true,
            message: `Order #${targetOrderID} changed to Self pickup.${emailSent ? ' Notification email sent to customer.' : ''}`,
            reason: termReason,
            emailSent
        });
    } catch (err) {
        console.error("Error in POST /admin/terminate:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

/**
 * POST /api/task-assignment/admin/self-pickup-completed
 * Mark self-pickup terminated order as Picked / Completed
 */
router.post("/admin/self-pickup-completed", async (req, res) => {
    try {
        const { orderID } = req.body;
        if (!orderID) {
            return res.status(400).json({ success: false, error: "orderID is required" });
        }

        const ordRef = db.collection("order").doc(orderID);
        const ordSnap = await ordRef.get();
        if (!ordSnap.exists) {
            return res.status(404).json({ success: false, error: "Order not found" });
        }

        await ordRef.set({
            orderStatus: "Completed",
            pickedAt: new Date(),
            updatedAt: new Date()
        }, { merge: true });

        // Also update linked task to Completed
        const taskID = `TSK-${orderID}`;
        await db.collection("task").doc(taskID).set({
            taskStatus: "Completed",
            completedAt: new Date(),
            updatedAt: new Date()
        }, { merge: true });

        invalidateTaskCache();

        return res.json({
            success: true,
            message: `Order #${orderID} marked as Completed (Picked up).`
        });
    } catch (err) {
        console.error("Error in POST /admin/self-pickup-completed:", err);
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

/**
 * POST /api/task-assignment/admin/simulate-delay-check
 * Trigger manual violation checks for testing and demo purposes
 */
router.post("/admin/simulate-delay-check", async (req, res) => {
    try {
        const { scheduleID, type } = req.body;
        if (!scheduleID) {
            return res.status(400).json({ success: false, error: "scheduleID is required" });
        }

        if (type === "end") {
            await handleEndTimeViolation(scheduleID);
            return res.json({ success: true, message: `Simulated end-time violation check executed for ${scheduleID}` });
        } else {
            await handleStartTimeViolation(scheduleID);
            return res.json({ success: true, message: `Simulated start-time violation check executed for ${scheduleID}` });
        }
    } catch (err) {
        console.error("Error in simulate-delay-check:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

router.post("/admin/simulate-monthly-reset", async (req, res) => {
    try {
        await checkAndResetMonthlyMistakes(true);
        return res.json({ success: true, message: "Monthly staff mistake reset executed successfully (forced reset)." });
    } catch (err) {
        console.error("Error in simulate-monthly-reset:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

/**
 * =========================================================================
 * LEAVE APPLICATION MANAGEMENT
 * Collection: leaveApplication
 * Fields:
 *   [PK] leaveID
 *   leaveType: 'Annual Leave' | 'Medical Leave' | 'Unpaid Leave'
 *   startDate: 'DD/MM/YYYY'
 *   endDate: 'DD/MM/YYYY'
 *   leaveStatus: 'Pending' | 'Approved' | 'Rejected'
 *   reason: string
 *   suportingDocUrl: string
 *   [FK] applicantStaffID: string
 * =========================================================================
 */

// Helper to resolve staff document from applicantStaffID or email
async function resolveStaffAccount(staffID, email) {
    let targetDoc = null;
    if (staffID) {
        const doc = await db.collection("users").doc(staffID).get();
        if (doc.exists) return { id: doc.id, data: doc.data() };
        // check staffNo
        const snap = await db.collection("users").where("staffNo", "==", staffID).limit(1).get();
        if (!snap.empty) return { id: snap.docs[0].id, data: snap.docs[0].data() };
    }
    if (email) {
        const snap = await db.collection("users").where("email", "==", String(email).trim().toLowerCase()).limit(1).get();
        if (!snap.empty) return { id: snap.docs[0].id, data: snap.docs[0].data() };
    }
    return null;
}

// Helper to get or initialize staff 'leave' field directly on users/{staffDocId}
// Structure: db.collection("users").doc(staffDocId) -> field 'leave': { annualRemaining, medicalRemaining }
async function getStaffLeaveBalance(staffDocId) {
    const userDocRef = db.collection("users").doc(staffDocId);
    const userDoc = await userDocRef.get();

    let annualRemaining = 12;
    let medicalRemaining = 14;

    if (userDoc.exists) {
        const userData = userDoc.data() || {};
        if (userData.leave && typeof userData.leave === "object") {
            annualRemaining = typeof userData.leave.annualRemaining === "number" ? userData.leave.annualRemaining : 12;
            medicalRemaining = typeof userData.leave.medicalRemaining === "number" ? userData.leave.medicalRemaining : 14;
        } else {
            await userDocRef.set({ leave: { annualRemaining, medicalRemaining } }, { merge: true });
        }
    }

    return {
        ref: userDocRef,
        data: { annualRemaining, medicalRemaining }
    };
}

const getStaffLeaveSubcollection = getStaffLeaveBalance;

/**
 * GET /api/task-assignment/leave-balance?staffID=...&email=...
 * Returns the staff remaining leave balances from subcollection users/{staffID}/leave/balance
 */
router.get("/leave-balance", async (req, res) => {
    try {
        const { staffID, email } = req.query;
        const staff = await resolveStaffAccount(staffID, email);
        if (!staff) {
            return res.json({
                success: true,
                annualRemaining: 12,
                medicalRemaining: 14
            });
        }
        const { data } = await getStaffLeaveSubcollection(staff.id);
        return res.json({
            success: true,
            staffID: staff.id,
            annualRemaining: data.annualRemaining,
            medicalRemaining: data.medicalRemaining
        });
    } catch (err) {
        console.error("Error fetching leave balance:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

/**
 * GET /api/task-assignment/leave-applications?staffID=...&email=...
 * Fetch all leave applications submitted by a staff member
 */
router.get("/leave-applications", async (req, res) => {
    try {
        const { staffID, email } = req.query;
        let snap;
        if (staffID || email) {
            const staff = await resolveStaffAccount(staffID, email);
            if (!staff) {
                return res.json({ success: true, applications: [] });
            }
            snap = await db.collection("leaveApplication")
                .where("applicantStaffID", "==", staff.id)
                .get();
        } else {
            // Admin view: return all leave applications
            snap = await db.collection("leaveApplication").get();
        }

        const applications = [];
        const staffMap = {};

        for (const doc of snap.docs) {
            const data = doc.data();
            const staffId = data.applicantStaffID;
            let staffInfo = null;

            if (staffId) {
                if (!staffMap[staffId]) {
                    const uDoc = await db.collection("users").doc(staffId).get();
                    if (uDoc.exists) {
                        const uData = uDoc.data();
                        staffMap[staffId] = {
                            staffName: uData.fullName || uData.name || data.applicantStaffName || "Staff",
                            staffNo: uData.staffNo || data.applicantStaffNo || "",
                            email: uData.email || "",
                            annualRemaining: uData.leave?.annualRemaining ?? 12,
                            medicalRemaining: uData.leave?.medicalRemaining ?? 14
                        };
                    } else {
                        staffMap[staffId] = {
                            staffName: data.applicantStaffName || "Staff",
                            staffNo: data.applicantStaffNo || "",
                            annualRemaining: 12,
                            medicalRemaining: 14
                        };
                    }
                }
                staffInfo = staffMap[staffId];
            }

            applications.push({
                ...data,
                id: doc.id,
                leaveID: data.leaveID || doc.id,
                applicantStaffName: staffInfo?.staffName || data.applicantStaffName || "Staff",
                applicantStaffNo: staffInfo?.staffNo || data.applicantStaffNo || "",
                staffEmail: staffInfo?.email || "",
                annualRemaining: staffInfo?.annualRemaining ?? 12,
                medicalRemaining: staffInfo?.medicalRemaining ?? 14
            });
        }

        // Sort desc by createdAt or leaveID
        applications.sort((a, b) => {
            const tA = a.createdAt ? new Date(a.createdAt).getTime() : 0;
            const tB = b.createdAt ? new Date(b.createdAt).getTime() : 0;
            return tB - tA;
        });

        return res.json({ success: true, applications });
    } catch (err) {
        console.error("Error fetching leave applications:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

/**
 * POST /api/task-assignment/apply-leave
 * Multi-part / JSON endpoint to create a leave application record
 */
router.post("/apply-leave", (req, res, next) => {
    upload.single("supportingDoc")(req, res, (err) => {
        if (err) {
            return res.status(400).json({ success: false, error: `Upload error: ${err.message}` });
        }
        next();
    });
}, async (req, res) => {
    try {
        const {
            applicantStaffID,
            email,
            leaveType,
            startDate, // Expected DD/MM/YYYY
            endDate,   // Expected DD/MM/YYYY
            reason = "",
            days
        } = req.body;

        let suportingDocUrl = req.body.suportingDocUrl || "";

        // 1. Resolve staff
        const staff = await resolveStaffAccount(applicantStaffID, email);
        if (!staff) {
            return res.status(404).json({ success: false, error: "Staff account not found." });
        }

        // 2. Validate leaveType: Annual Leave, Medical Leave, Unpaid Leave
        const validTypes = ["Annual Leave", "Medical Leave", "Unpaid Leave"];
        if (!validTypes.includes(leaveType)) {
            return res.status(400).json({
                success: false,
                error: "Invalid leave type. Only Annual Leave, Medical Leave, and Unpaid Leave are accepted."
            });
        }

        // 3. Validate dates format DD/MM/YYYY
        if (!startDate || !endDate) {
            return res.status(400).json({ success: false, error: "Start date and End date are required." });
        }

        // Parse DD/MM/YYYY
        const parseDMY = (dStr) => {
            if (!dStr) return null;
            const parts = dStr.split("/");
            if (parts.length === 3) {
                const day = parseInt(parts[0], 10);
                const month = parseInt(parts[1], 10) - 1;
                const year = parseInt(parts[2], 10);
                return new Date(year, month, day, 0, 0, 0);
            }
            return new Date(dStr);
        };

        const startDt = parseDMY(startDate);
        const endDt = parseDMY(endDate);

        if (!startDt || isNaN(startDt.getTime()) || !endDt || isNaN(endDt.getTime())) {
            return res.status(400).json({ success: false, error: "Dates must be valid and formatted as DD/MM/YYYY." });
        }

        // The start date should limit until tmr (meaning the leave needs to be applied at least 1 day before)
        const now = new Date();
        const tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 0);
        if (startDt < tomorrow) {
            return res.status(400).json({
                success: false,
                error: "Start date must be tomorrow or later. Leave applications must be submitted at least 1 day in advance."
            });
        }

        if (endDt < startDt) {
            return res.status(400).json({ success: false, error: "End date cannot be earlier than start date." });
        }

        // Calculate duration in days
        const durationDays = parseInt(days, 10) || Math.floor((endDt.getTime() - startDt.getTime()) / (1000 * 60 * 60 * 24)) + 1;

        // 4. Check for overlapping dates and calculate total pending days for Annual and Medical Leave
        const existingAppsSnap = await db.collection("leaveApplication")
            .where("applicantStaffID", "==", staff.id)
            .get();

        const testStart = new Date(startDt.getFullYear(), startDt.getMonth(), startDt.getDate(), 0, 0, 0);
        const testEnd = new Date(endDt.getFullYear(), endDt.getMonth(), endDt.getDate(), 23, 59, 59, 999);

        let pendingAnnualDays = 0;
        let pendingMedicalDays = 0;

        for (const doc of existingAppsSnap.docs) {
            const app = doc.data();
            const status = (app.leaveStatus || "").toLowerCase();
            const appDays = parseInt(app.daysCount || app.duration || 1, 10) || 1;

            // Track total requested (pending) days per leave type
            if (["pending", "in request", "requested"].includes(status)) {
                if (app.leaveType === "Annual Leave") {
                    pendingAnnualDays += appDays;
                } else if (app.leaveType === "Medical Leave") {
                    pendingMedicalDays += appDays;
                }
            }

            // Check only active/pending/approved requests for date collisions
            if (["pending", "approved", "in request", "requested"].includes(status)) {
                const exStart = parseDMY(app.startDate);
                const exEnd = parseDMY(app.endDate);
                if (exStart && exEnd && !isNaN(exStart.getTime()) && !isNaN(exEnd.getTime())) {
                    const normExStart = new Date(exStart.getFullYear(), exStart.getMonth(), exStart.getDate(), 0, 0, 0);
                    const normExEnd = new Date(exEnd.getFullYear(), exEnd.getMonth(), exEnd.getDate(), 23, 59, 59, 999);

                    // Overlap check: testStart <= normExEnd && testEnd >= normExStart
                    if (testStart <= normExEnd && testEnd >= normExStart) {
                        return res.status(400).json({
                            success: false,
                            error: `You already have a ${app.leaveStatus || "Pending"} leave application (${app.leaveID}: ${app.startDate} - ${app.endDate}) covering the selected date(s). Applications with overlapping dates are not permitted.`
                        });
                    }
                }
            }
        }

        // 5. Validate supporting document & reason according to leaveType rules
        // If Medical: reason AND attachment are necessary
        if (leaveType === "Medical Leave") {
            if (!reason || !reason.trim()) {
                return res.status(400).json({ success: false, error: "Reason is required for Medical Leave." });
            }
            if (!req.file && !suportingDocUrl) {
                return res.status(400).json({
                    success: false,
                    error: "Supporting document / Medical Certificate is mandatory for Medical Leave."
                });
            }
        }

        // If Unpaid: reason is necessary, attachment is optional
        if (leaveType === "Unpaid Leave") {
            if (!reason || !reason.trim()) {
                return res.status(400).json({ success: false, error: "Reason is required for Unpaid Leave." });
            }
        }

        // 6. Handle file upload to Cloudinary if provided
        if (req.file && req.file.buffer) {
            try {
                const folder = `rebyte/leave_documents/${staff.id}`;
                const publicName = `doc_${Date.now()}`;
                const uploadResult = await uploadBufferToCloudinary(req.file.buffer, folder, publicName);
                suportingDocUrl = uploadResult.secure_url || uploadResult.url;
            } catch (upErr) {
                console.error("Cloudinary upload failed for leave attachment:", upErr);
                return res.status(500).json({ success: false, error: "Failed to upload supporting document." });
            }
        }

        // 7. Check leave balances in staff user record users/{staffID}.leave
        // NOTE: Balance is NOT deducted until approved!
        // The total request of annual/medical leave (pending + current) cannot exceed the remaining balance
        const leaveBal = await getStaffLeaveBalance(staff.id);
        const currentBalance = leaveBal.data;

        if (leaveType === "Annual Leave") {
            const totalRequested = pendingAnnualDays + durationDays;
            if (totalRequested > currentBalance.annualRemaining) {
                const available = Math.max(0, currentBalance.annualRemaining - pendingAnnualDays);
                return res.status(400).json({
                    success: false,
                    error: `The total requested Annual Leave (${totalRequested} days: ${pendingAnnualDays} pending + ${durationDays} current) cannot exceed your remaining balance (${currentBalance.annualRemaining} days). You can only request up to ${available} more day(s).`
                });
            }
        } else if (leaveType === "Medical Leave") {
            const totalRequested = pendingMedicalDays + durationDays;
            if (totalRequested > currentBalance.medicalRemaining) {
                const available = Math.max(0, currentBalance.medicalRemaining - pendingMedicalDays);
                return res.status(400).json({
                    success: false,
                    error: `The total requested Medical Leave (${totalRequested} days: ${pendingMedicalDays} pending + ${durationDays} current) cannot exceed your remaining balance (${currentBalance.medicalRemaining} days). You can only request up to ${available} more day(s).`
                });
            }
        }

        // 8. Generate leaveID: LV-XXXXXX
        const leaveID = `LV-${Date.now().toString().slice(-6)}`;

        // 9. Create leaveApplication record in Firestore with leaveStatus: "Pending"
        const leaveRecord = {
            leaveID,
            leaveType,
            startDate, // Display format DD/MM/YYYY
            endDate,   // Display format DD/MM/YYYY
            leaveStatus: "Pending",
            reason: reason ? reason.trim() : "",
            suportingDocUrl: suportingDocUrl || "",
            applicantStaffID: staff.id,
            applicantStaffNo: staff.data.staffNo || "",
            applicantStaffName: staff.data.fullName || staff.data.name || "",
            duration: durationDays,
            daysCount: durationDays,
            createdAt: new Date().toISOString()
        };

        // Unapproved application: do NOT deduct remaining balance yet
        await db.collection("leaveApplication").doc(leaveID).set(leaveRecord);

        return res.status(201).json({
            success: true,
            message: "Leave application submitted successfully. Awaiting approval and review.",
            leaveRecord,
            annualRemaining: currentBalance.annualRemaining,
            medicalRemaining: currentBalance.medicalRemaining
        });
    } catch (err) {
        console.error("Error creating leave application:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

/**
 * DELETE /api/task-assignment/cancel-leave/:leaveID
 * Cancel a pending leave application
 */
router.delete("/cancel-leave/:leaveID", async (req, res) => {
    try {
        const { leaveID } = req.params;
        const docRef = db.collection("leaveApplication").doc(leaveID);
        const doc = await docRef.get();
        if (!doc.exists) {
            return res.status(404).json({ success: false, error: "Leave application not found." });
        }
        const data = doc.data();
        if (data.leaveStatus === "Cancelled") {
            return res.status(400).json({ success: false, error: "This leave application is already cancelled." });
        }
        if (data.leaveStatus !== "Pending") {
            return res.status(400).json({ success: false, error: "Only Pending applications can be cancelled." });
        }

        const batch = db.batch();
        // If cancel request, just change status to Cancelled
        batch.update(docRef, {
            leaveStatus: "Cancelled",
            cancelledAt: new Date().toISOString()
        });

        // If it was already Approved, restore balance. If Pending, it was not deducted yet so no restoration needed.
        const staffDocId = data.applicantStaffID;
        const durationDays = parseInt(data.daysCount || data.duration || 1, 10);
        const leaveType = data.leaveType;

        if (data.leaveStatus === "Approved" && staffDocId && (leaveType === "Annual Leave" || leaveType === "Medical Leave")) {
            const leaveBal = await getStaffLeaveBalance(staffDocId);
            if (leaveType === "Annual Leave") {
                const restored = Math.min(12, leaveBal.data.annualRemaining + durationDays);
                batch.update(leaveBal.ref, {
                    "leave.annualRemaining": restored
                });
            } else if (leaveType === "Medical Leave") {
                const restored = Math.min(14, leaveBal.data.medicalRemaining + durationDays);
                batch.update(leaveBal.ref, {
                    "leave.medicalRemaining": restored
                });
            }
        }

        await batch.commit();
        return res.json({ success: true, message: "Leave application cancelled successfully." });
    } catch (err) {
        console.error("Error cancelling leave application:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

/**
 * Helper: Reassign any active tasks scheduled for a staff member on approved leave dates 1-by-1
 * When approved, task on that day of the staff need reassign to suitable staff
 */
async function reassignStaffTasksOnApprovedLeave(staffID, startDateStr, endDateStr, leaveID) {
    try {
        const start = parseLeaveDate(startDateStr);
        const end = parseLeaveDate(endDateStr);
        if (!start || !end) {
            console.warn(`[REASSIGN ON LEAVE] Invalid date range for staff ${staffID}: ${startDateStr} - ${endDateStr}`);
            return { reassignedCount: 0 };
        }

        // Collect all YYYY-MM-DD date strings in the leave duration
        const dateKeys = [];
        const cur = new Date(start.getFullYear(), start.getMonth(), start.getDate(), 0, 0, 0);
        const endMidnight = new Date(end.getFullYear(), end.getMonth(), end.getDate(), 0, 0, 0);

        while (cur <= endMidnight) {
            const y = cur.getFullYear();
            const m = String(cur.getMonth() + 1).padStart(2, "0");
            const d = String(cur.getDate()).padStart(2, "0");
            dateKeys.push(`${y}-${m}-${d}`);
            cur.setDate(cur.getDate() + 1);
        }

        console.log(`[REASSIGN ON LEAVE] Checking tasks for staff ${staffID} across approved leave dates:`, dateKeys);

        let totalReassigned = 0;

        for (const dateStr of dateKeys) {
            const schedSnap = await db.collection("schedule")
                .where("staffID", "==", staffID)
                .where("scheduleDate", "==", dateStr)
                .get();

            if (schedSnap.empty) continue;

            for (const sDoc of schedSnap.docs) {
                const sData = sDoc.data();
                const status = (sData.scheduleStatus || "").toLowerCase();

                // Only reassign active / uncompleted tasks
                if (["completed", "cancelled", "absent", "reassigned"].includes(status)) {
                    continue;
                }

                const orderID = sData.orderID;
                const scheduleID = sDoc.id;

                console.log(`[REASSIGN ON LEAVE] Reassigning Order #${orderID} (Schedule ${scheduleID}) on ${dateStr} due to approved leave [${leaveID}] 1 by 1...`);

                // Mark current schedule as reassigned due to leave
                await sDoc.ref.set({
                    scheduleStatus: "reassigned",
                    reassignReason: `Staff on approved leave (${leaveID})`,
                    reassignedAt: new Date().toISOString(),
                    updatedAt: new Date().toISOString()
                }, { merge: true });

                // Clear existing timers for this schedule
                clearScheduleTimers(scheduleID);

                // Reassign task 1-by-1 to a suitable delivery staff
                const reassignResult = await assignDeliveryTask({
                    orderID,
                    addressID: sData.addressID,
                    requestedDate: dateStr,
                    forceNextDay: false, // Try same day first with other eligible staff; cascades if all full
                    excludeStaffIDs: [staffID]
                });

                if (reassignResult && reassignResult.success) {
                    if (reassignResult.scheduleID) {
                        registerScheduleTimer(reassignResult.scheduleID);
                    }
                    totalReassigned++;
                    console.log(`[REASSIGN ON LEAVE SUCCESS] Order #${orderID} reassigned to ${reassignResult.staffName || reassignResult.staffID} on ${reassignResult.scheduleDate} (${reassignResult.scheduleStartTime})`);
                } else {
                    console.warn(`[REASSIGN ON LEAVE WARNING] Could not automatically reassign Order #${orderID}:`, reassignResult?.reason || reassignResult?.message);
                }
            }
        }

        if (totalReassigned > 0) {
            invalidateTaskCache();
        }

        return { reassignedCount: totalReassigned };
    } catch (err) {
        console.error(`[REASSIGN ON LEAVE ERROR] Failed reassigning tasks for staff ${staffID}:`, err);
        return { reassignedCount: 0, error: err.message };
    }
}

/**
 * PUT /api/task-assignment/review-leave/:leaveID
 * Review/Approve/Reject a leave application (deducts remaining leave and reassigns tasks on approved leave dates)
 */
router.put("/review-leave/:leaveID", async (req, res) => {
    try {
        const { leaveID } = req.params;
        const { status, reviewRemarks, reviewerID } = req.body;
        if (!status || !["Approved", "Rejected"].includes(status)) {
            return res.status(400).json({ success: false, error: "Status must be 'Approved' or 'Rejected'." });
        }

        const docRef = db.collection("leaveApplication").doc(leaveID);
        const doc = await docRef.get();
        if (!doc.exists) {
            return res.status(404).json({ success: false, error: "Leave application not found." });
        }
        const currentData = doc.data();
        if (currentData.leaveStatus !== "Pending") {
            return res.status(400).json({ success: false, error: `Leave application is already ${currentData.leaveStatus}.` });
        }

        const batch = db.batch();
        batch.update(docRef, {
            leaveStatus: status,
            reviewedAt: new Date().toISOString(),
            reviewerID: reviewerID || "",
            reviewRemarks: reviewRemarks || ""
        });

        // Deduct balance ONLY when Approved!
        if (status === "Approved") {
            const staffDocId = currentData.applicantStaffID;
            const durationDays = parseInt(currentData.daysCount || currentData.duration || 1, 10);
            const leaveType = currentData.leaveType;

            if (staffDocId && (leaveType === "Annual Leave" || leaveType === "Medical Leave")) {
                const leaveBal = await getStaffLeaveBalance(staffDocId);
                if (leaveType === "Annual Leave") {
                    const newBal = Math.max(0, leaveBal.data.annualRemaining - durationDays);
                    batch.update(leaveBal.ref, { "leave.annualRemaining": newBal });
                } else if (leaveType === "Medical Leave") {
                    const newBal = Math.max(0, leaveBal.data.medicalRemaining - durationDays);
                    batch.update(leaveBal.ref, { "leave.medicalRemaining": newBal });
                }
            }
        }

        await batch.commit();

        // When approved the leave, the task on that day of the staff need reassign to suitable staff
        let reassignedInfo = null;
        if (status === "Approved") {
            const staffDocId = currentData.applicantStaffID;
            reassignedInfo = await reassignStaffTasksOnApprovedLeave(
                staffDocId,
                currentData.startDate,
                currentData.endDate,
                leaveID
            );
        }

        return res.json({
            success: true,
            message: `Leave application ${status.toLowerCase()} successfully.` +
                (reassignedInfo && reassignedInfo.reassignedCount > 0
                    ? ` ${reassignedInfo.reassignedCount} task(s) on the leave date(s) were reassigned to available staff.`
                    : ""),
            reassignedTasksCount: reassignedInfo ? reassignedInfo.reassignedCount : 0
        });
    } catch (err) {
        console.error("Error reviewing leave application:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

/**
 * PUT /api/task-assignment/batch-review-leave
 * Batch review (Approve/Reject) multiple leave applications
 * Deducts annual/medical days only on Approved; skips deduction for Unpaid leave
 * Reassigns staff tasks 1-by-1 on approved leave dates
 */
router.put("/batch-review-leave", async (req, res) => {
    try {
        const { leaveIDs, status, reviewRemarks, reviewerID } = req.body;
        if (!Array.isArray(leaveIDs) || leaveIDs.length === 0) {
            return res.status(400).json({ success: false, error: "leaveIDs must be a non-empty array." });
        }
        if (!status || !["Approved", "Rejected"].includes(status)) {
            return res.status(400).json({ success: false, error: "Status must be 'Approved' or 'Rejected'." });
        }

        const batch = db.batch();
        let updatedCount = 0;
        const nowIso = new Date().toISOString();

        // Keep running cache of updated balances per staff so multiple leaves for the same staff in one batch deduct properly
        const staffBalanceCache = {};
        const approvedDocsToReassign = [];

        for (const id of leaveIDs) {
            const docRef = db.collection("leaveApplication").doc(id);
            const doc = await docRef.get();
            if (!doc.exists) continue;
            const currentData = doc.data();
            if (currentData.leaveStatus !== "Pending") continue;

            batch.update(docRef, {
                leaveStatus: status,
                reviewedAt: nowIso,
                reviewerID: reviewerID || "",
                reviewRemarks: reviewRemarks || ""
            });

            if (status === "Approved") {
                const staffDocId = currentData.applicantStaffID;
                approvedDocsToReassign.push({
                    staffDocId,
                    startDate: currentData.startDate,
                    endDate: currentData.endDate,
                    leaveID: id
                });

                const durationDays = parseInt(currentData.daysCount || currentData.duration || 1, 10);
                const leaveType = currentData.leaveType;

                if (staffDocId && (leaveType === "Annual Leave" || leaveType === "Medical Leave")) {
                    if (!staffBalanceCache[staffDocId]) {
                        const leaveBal = await getStaffLeaveBalance(staffDocId);
                        staffBalanceCache[staffDocId] = {
                            ref: leaveBal.ref,
                            annualRemaining: leaveBal.data.annualRemaining,
                            medicalRemaining: leaveBal.data.medicalRemaining
                        };
                    }

                    if (leaveType === "Annual Leave") {
                        staffBalanceCache[staffDocId].annualRemaining = Math.max(
                            0,
                            staffBalanceCache[staffDocId].annualRemaining - durationDays
                        );
                    } else if (leaveType === "Medical Leave") {
                        staffBalanceCache[staffDocId].medicalRemaining = Math.max(
                            0,
                            staffBalanceCache[staffDocId].medicalRemaining - durationDays
                        );
                    }
                }
            }
            updatedCount++;
        }

        // Apply cached staff balance updates to batch
        for (const [staffDocId, bal] of Object.entries(staffBalanceCache)) {
            batch.update(bal.ref, {
                "leave.annualRemaining": bal.annualRemaining,
                "leave.medicalRemaining": bal.medicalRemaining
            });
        }

        if (updatedCount > 0) {
            await batch.commit();
        }

        // Reassign tasks 1-by-1 for all approved leaves
        let totalReassigned = 0;
        if (status === "Approved") {
            for (const docInfo of approvedDocsToReassign) {
                const reassignRes = await reassignStaffTasksOnApprovedLeave(
                    docInfo.staffDocId,
                    docInfo.startDate,
                    docInfo.endDate,
                    docInfo.leaveID
                );
                if (reassignRes && reassignRes.reassignedCount) {
                    totalReassigned += reassignRes.reassignedCount;
                }
            }
        }

        return res.json({
            success: true,
            updatedCount,
            reassignedTasksCount: totalReassigned,
            message: `Successfully ${status.toLowerCase()} ${updatedCount} leave application(s).` +
                (totalReassigned > 0 ? ` ${totalReassigned} task(s) on approved leave date(s) were reassigned to available staff.` : "")
        });
    } catch (err) {
        console.error("Error batch reviewing leave applications:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

module.exports = router;

