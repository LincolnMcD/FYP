const express = require("express");
const router = express.Router();
const db = require("../config/firebase");
const { FieldValue } = require("firebase-admin/firestore");
const cloudinary = require("../config/cloudinary");
const multer = require("multer");
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 10 * 1024 * 1024 } });
const { assignDeliveryTask, assignTradeInTask, getStaffIDsOnApprovedLeave, parseLeaveDate, handleFailedTradeInReassignment } = require("./taskAssignmentService");
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
            // Skip absent, rejected, cancelled, or reassigned schedules from staff task list
            if (schedStatus === "absent" || schedStatus === "rejected" || schedStatus === "cancelled" || schedStatus === "reassigned") {
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
                                model: model.trim(),
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
            } else if (schedData.appointmentID || taskData.appointmentID || taskData.taskType === "inspect" || taskData.taskType === "collect" || scheduleID.includes("APP")) {
                const appID = schedData.appointmentID || taskData.appointmentID || scheduleID.replace(/^SCH-/, '').split('-')[0];
                let aData = {};
                if (appID) {
                    const aSnap = await db.collection("tradeInAppointment").doc(appID).get();
                    if (aSnap.exists) aData = aSnap.data();
                }

                let addressID = aData.addressID || taskData.addressID || schedData.addressID;
                if (addressID) {
                    const aDoc = await db.collection("address").doc(addressID).get();
                    if (aDoc.exists) address = aDoc.data();
                } else if (aData.address && typeof aData.address === "object") {
                    address = aData.address;
                }

                const trID = aData.tradeInRequestID || taskData.tradeInRequestID || null;
                let trData = {};
                if (trID) {
                    const trDoc = await db.collection("tradeInRequests").doc(trID).get();
                    if (trDoc.exists) trData = trDoc.data() || {};
                }

                // Query device details from devices collection via tradeInRequests -> deviceID
                let devData = {};
                const deviceID = trData.deviceID || taskData.deviceID || aData.deviceID || null;
                if (deviceID) {
                    try {
                        let devDoc = await db.collection("devices").doc(deviceID).get();
                        if (!devDoc.exists) {
                            devDoc = await db.collection("device").doc(deviceID).get();
                        }
                        if (devDoc.exists) {
                            devData = devDoc.data() || {};
                        }
                    } catch (dErr) {
                        console.error("Error fetching device for trade-in:", dErr);
                    }
                }

                // Fetch device image from subcollection if not on record
                let devImageUrl = trData.deviceImageUrl || trData.imageUrl || devData.imageUrl || "";
                if (!devImageUrl && trID) {
                    try {
                        const imgSnap = await db.collection("tradeInRequests").doc(trID).collection("images").limit(1).get();
                        if (!imgSnap.empty) {
                            devImageUrl = imgSnap.docs[0].data().imageUrl || "";
                        }
                    } catch (_) {}
                }

                if (!address.addressLine && trData.inspectionAddress && typeof trData.inspectionAddress === "object") {
                    address = trData.inspectionAddress;
                }

                const deviceBrand = devData.brand || trData.deviceBrand || trData.brand || "Apple";
                const deviceModel = devData.model || devData.name || trData.deviceModel || trData.model || "Device";
                const storage = devData.storageCapacity || devData.storage || trData.storageCapacity || trData.storage || "";
                const color = devData.colour || devData.color || trData.colour || trData.color || trData.deviceColor || "";
                const condition = trData.deviceCondition || trData.reportedCondition || devData.condition || "Good";
                let tradeInEstimate = trData.tradeInEstimate || trData.offeredPrice || 0;
                if (!tradeInEstimate && trData.estimatedValue) {
                    if (typeof trData.estimatedValue === "number") {
                        tradeInEstimate = trData.estimatedValue;
                    } else if (typeof trData.estimatedValue === "object") {
                        tradeInEstimate = trData.estimatedValue.max || trData.estimatedValue.min || 0;
                    } else {
                        const cleanStr = String(trData.estimatedValue).replace(/[^0-9.]/g, " ").trim();
                        const numParts = cleanStr.split(/\s+/).map(Number).filter(n => !isNaN(n) && n > 0);
                        tradeInEstimate = numParts.length > 0 ? numParts[numParts.length - 1] : 0;
                    }
                }
                const imei = devData.imeiNum || devData.imei || trData.imei || trData.imeiNum || trData.serialNumber || "";
                const imageUrl = devImageUrl;

                const rawAppType = String(aData.appointmentType || taskData.taskType || (trData.inspectionMethod && trData.inspectionMethod.includes("Shipment") ? "Collect" : "Inspect")).toLowerCase();
                const resolvedTaskType = rawAppType.includes("collect") ? "collect" : "inspect";

                items.push({
                    productID: trID || appID,
                    brand: deviceBrand,
                    model: deviceModel.trim(),
                    storage,
                    color,
                    condition,
                    price: tradeInEstimate,
                    tradeInEstimate,
                    imei,
                    imageUrl,
                    tradeInRequestID: trID,
                    appointmentID: appID,
                    appointmentType: aData.appointmentType || (resolvedTaskType === "collect" ? "Collect" : "Inspect"),
                    description: [storage, color].filter(Boolean).join(" • ")
                });

                // Attach trade-in specific overrides
                taskData.taskType = resolvedTaskType;
                taskData.customerName = trData.customerName || trData.name || address.recipientName || address.recipentName || "Customer";
                taskData.customerPhone = trData.customerPhone || trData.phone || trData.contactNumber || address.phoneNumber || "";
                taskData.customerEmail = trData.customerEmail || trData.email || trData.userEmail || address.email || "";
                taskData.appointmentID = appID;
                taskData.tradeInRequestID = trID;
                taskData.deviceID = deviceID;
                taskData.deviceModel = `${deviceBrand} ${deviceModel}`.trim();
                taskData.storage = storage;
                taskData.color = color;
                taskData.reportedCondition = condition;
                taskData.tradeInEstimate = tradeInEstimate;
                taskData.imei = imei;
                taskData.imageUrl = imageUrl;
                if (typeof trData.inspectionAddress === "string" && trData.inspectionAddress.trim()) {
                    taskData.deliveryAddress = trData.inspectionAddress.trim();
                }
            }

            // 5. Fetch Delivery record (Delivery tasks only)
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
            const fullAddressText = taskData.deliveryAddress || [address.addressLine, address.postcode, address.city, address.state].filter(Boolean).join(", ");
            if ((!finalLat || finalLat === 5.3542) && fullAddressText) {
                try {
                    const geoRes = await fetch(
                        `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(fullAddressText)}&countrycodes=my&limit=1`,
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

            const isInspectOrCollect = taskData.taskType === "inspect" || taskData.taskType === "collect";
            const customerName = taskData.customerName || address.recipentName || address.recipientName || (orderData && orderData.customerName) || "Customer";
            const customerPhone = taskData.customerPhone || address.phoneNumber || (orderData && orderData.customerPhone) || "";
            const customerEmail = taskData.customerEmail || (orderData && orderData.customerEmail) || address.email || (orderData && orderData.email) || "";
            const deliveryAddress = taskData.deliveryAddress || [address.addressLine, address.postcode, address.city, address.state].filter(Boolean).join(", ") || "Penang, Malaysia";

            tasksList.push({
                scheduleID,
                scheduleDate: schedData.scheduleDate || "",
                scheduleStartTime: schedData.scheduleStartTime || taskData.taskStartTime || "",
                scheduleEndTime: schedData.scheduleEndTime || "",
                scheduleStatus: schedData.scheduleStatus || "assigned",
                taskID,
                taskType: taskData.taskType || "deliver",
                taskStatus: taskData.taskStatus === "In Progress" ? "In Progress" : ((taskData.taskStatus === "Shipping" || String(schedData.scheduleStatus || "").toLowerCase() === "ongoing") ? "Ongoing" : (taskData.taskStatus || (schedData.scheduleStatus === "completed" ? "Delivered" : "Packaging"))),
                estimatedDistanceinKM: distNum,
                estimatedDurationinMinutes: durNum,
                estimatedDuration: `${durNum} mins`,
                estimatedDistance: `${distNum} km`,
                staffID: targetStaffID,
                staffName: staffName || schedData.staffName || "",
                orderID: orderID || taskData.tradeInRequestID || taskData.appointmentID || taskID,
                appointmentID: taskData.appointmentID || null,
                tradeInRequestID: taskData.tradeInRequestID || null,
                deviceModel: taskData.deviceModel || (items[0] && `${items[0].brand || ''} ${items[0].model || ''}`.trim()) || "Device",
                storage: taskData.storage || (items[0] && items[0].storage) || "",
                color: taskData.color || (items[0] && items[0].color) || "",
                reportedCondition: taskData.reportedCondition || (items[0] && items[0].condition) || "Good",
                tradeInEstimate: taskData.tradeInEstimate || (items[0] && items[0].price) || 0,
                imei: taskData.imei || (items[0] && items[0].imei) || "",
                imageUrl: taskData.imageUrl || (items[0] && items[0].imageUrl) || "",
                customerName,
                customerPhone,
                customerEmail,
                deliveryAddress,
                deliveryStatus: isInspectOrCollect ? (schedData.scheduleStatus === "completed" ? "completed" : "ongoing") : (deliveryData.deliveryStatus || "ongoing"),
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

        // Pre-fetch task & schedule records to accurately resolve IDs and roles
        let effectiveTaskID = taskID || null;
        let taskData = null;
        if (effectiveTaskID) {
            try {
                const tDoc = await db.collection("task").doc(effectiveTaskID).get();
                if (tDoc.exists) taskData = tDoc.data();
            } catch (_) {}
        }
        if (!taskData && orderID) {
            try {
                const tDoc = await db.collection("task").doc(orderID).get();
                if (tDoc.exists) {
                    taskData = tDoc.data();
                    effectiveTaskID = tDoc.id;
                } else {
                    const tSnap1 = await db.collection("task").where("appointmentID", "==", orderID).limit(1).get();
                    if (!tSnap1.empty) {
                        taskData = tSnap1.docs[0].data();
                        effectiveTaskID = tSnap1.docs[0].id;
                    } else {
                        const tSnap2 = await db.collection("task").where("tradeInRequestID", "==", orderID).limit(1).get();
                        if (!tSnap2.empty) {
                            taskData = tSnap2.docs[0].data();
                            effectiveTaskID = tSnap2.docs[0].id;
                        } else {
                            const tSnap3 = await db.collection("task").where("orderID", "==", orderID).limit(1).get();
                            if (!tSnap3.empty) {
                                taskData = tSnap3.docs[0].data();
                                effectiveTaskID = tSnap3.docs[0].id;
                            }
                        }
                    }
                }
            } catch (_) {}
        }

        const effectiveSchedID = scheduleID || (taskData && taskData.scheduleID) || null;
        let schedData = null;
        if (effectiveSchedID) {
            try {
                const sDoc = await db.collection("schedule").doc(effectiveSchedID).get();
                if (sDoc.exists) schedData = sDoc.data();
            } catch (_) {}
        }

        let apptID = (taskData && taskData.appointmentID) ||
            (schedData && schedData.appointmentID) ||
            (orderID && (orderID.startsWith("APPT-") || orderID.startsWith("APT-") || orderID.includes("APP")) ? orderID : null);
        if (!apptID && effectiveTaskID && effectiveTaskID.includes("APP")) {
            apptID = effectiveTaskID.replace(/^TSK-/, "");
        }

        let tradeInReqID = (taskData && (taskData.tradeInRequestID || taskData.tradeInID)) ||
            (schedData && schedData.tradeInRequestID) ||
            (orderID && orderID.startsWith("TR") ? orderID : null);

        if (!apptID && tradeInReqID) {
            try {
                const aSnap = await db.collection("tradeInAppointment").where("tradeInRequestID", "==", tradeInReqID).limit(1).get();
                if (!aSnap.empty) {
                    apptID = aSnap.docs[0].id;
                }
            } catch (_) {}
        }

        const isTradeInTask = !!(
            apptID ||
            (taskData && (taskData.taskType === "inspect" || taskData.taskType === "collect")) ||
            (taskData && (taskData.appointmentID || taskData.tradeInRequestID)) ||
            tradeInReqID
        );

        const rejectingStaffID = (schedData && schedData.staffID) || (taskData && taskData.staffID) || null;

        const batch = db.batch();

        if (effectiveTaskID) {
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

            batch.set(db.collection("task").doc(effectiveTaskID), taskUpdate, { merge: true });
        }

        if (effectiveSchedID) {
            let schedStatus = "assigned";
            if (normalized === "Shipping" || normalized === "In Progress" || normalized === "ongoing" || normalized === "Ongoing") schedStatus = "ongoing";
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

            batch.set(db.collection("schedule").doc(effectiveSchedID), schedUpdate, { merge: true });
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
        } else if (orderID && isRejected && !isTradeInTask) {
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

        const isInProgressStatus = normalized === "In Progress" || normalized === "Ongoing" || normalized === "Shipping";

        if (isInProgressStatus) {
            if (apptID) {
                batch.set(db.collection("tradeInAppointment").doc(apptID), {
                    appointmentStatus: "In Progress",
                    status: "In Progress",
                    updatedAt: new Date()
                }, { merge: true });
            }
            if (tradeInReqID) {
                batch.set(db.collection("tradeInRequests").doc(tradeInReqID), {
                    requestStatus: "In Progress",
                    bookingStatus: "In Progress",
                    status: "In Progress",
                    updatedAt: new Date()
                }, { merge: true });
            }
        } else if (isCompleted) {
            if (apptID) {
                batch.set(db.collection("tradeInAppointment").doc(apptID), {
                    appointmentStatus: "Completed",
                    status: "Completed",
                    completedAt: FieldValue.serverTimestamp(),
                    updatedAt: new Date()
                }, { merge: true });
            }
            if (tradeInReqID) {
                const resolvedStatus = (taskData && taskData.taskType === "collect") ? "Collected" : "Inspected";
                batch.set(db.collection("tradeInRequests").doc(tradeInReqID), {
                    requestStatus: resolvedStatus,
                    status: resolvedStatus,
                    bookingStatus: "Completed",
                    updatedAt: new Date()
                }, { merge: true });
            }
        }

        await batch.commit();

        // Update active schedule timer on status transitions
        if (effectiveSchedID) {
            if (isCompleted || isRejected || isTerminated) {
                clearScheduleTimers(effectiveSchedID);
            } else {
                registerScheduleTimer(effectiveSchedID);
            }
        }

        // When staff rejects an inspection or collection task, reassign to another suitable staff
        // If no replacement staff is available, place On Hold and email customer to rebook or cancel
        if (isRejected && isTradeInTask) {
            console.log(`[TRADE-IN TASK REJECTED] Task: ${effectiveTaskID || "N/A"}, Appointment: ${apptID || "N/A"}, Staff: ${rejectingStaffID || "N/A"}. Attempting reassignment to another suitable staff...`);

            let appData = {};
            if (apptID) {
                try {
                    const aDoc = await db.collection("tradeInAppointment").doc(apptID).get();
                    if (aDoc.exists) appData = aDoc.data();
                } catch (_) {}
            }

            const effectiveTradeInReqID = tradeInReqID || appData.tradeInRequestID || (taskData && taskData.tradeInRequestID) || null;
            const rawType = (appData.appointmentType || (taskData && taskData.taskType) || "Inspect").toLowerCase();
            const method = rawType.includes("collect") ? "Doorstep Collection" : "On-Site Inspection";

            let schedDate = (schedData && schedData.scheduleDate) || appData.appointmentDate;
            if (!schedDate && appData.scheduledAt && typeof appData.scheduledAt.toDate === "function") {
                const d = appData.scheduledAt.toDate();
                schedDate = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
            }

            let appointmentTime = (schedData && schedData.scheduleStartTime) || (taskData && taskData.taskStartTime) || appData.appointmentTime;
            if (!appointmentTime && appData.scheduledAt && typeof appData.scheduledAt.toDate === "function") {
                const d = appData.scheduledAt.toDate();
                appointmentTime = `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
            }
            if (!appointmentTime) appointmentTime = "09:00 AM";

            const addressID = appData.addressID || (taskData && taskData.addressID) || null;
            const address = appData.appointmentLocation || null;

            const excludeStaffIDs = rejectingStaffID ? [rejectingStaffID] : [];

            const reassignResult = await assignTradeInTask({
                tradeInRequestID: effectiveTradeInReqID,
                method,
                appointmentDate: schedDate,
                appointmentTime,
                addressID,
                address,
                excludeStaffIDs,
                existingAppointmentID: apptID,
                existingTaskID: effectiveTaskID,
                forceNewRecords: false
            });

            if (reassignResult && reassignResult.success) {
                console.log(`[TRADE-IN REASSIGN SUCCESS] Trade-In ${method} Task reassigned to ${reassignResult.staffName || reassignResult.staffID} on ${reassignResult.scheduleDate} (${reassignResult.scheduleStartTime})`);
                return res.status(200).json({
                    success: true,
                    reassigned: true,
                    message: `Task rejected and successfully reassigned to ${reassignResult.staffName || reassignResult.staffID}.`,
                    staffID: reassignResult.staffID,
                    scheduleID: reassignResult.scheduleID
                });
            } else {
                console.warn(`[TRADE-IN REASSIGN WARNING] Could not automatically reassign rejected Trade-In task ${apptID}:`, reassignResult?.message);
                const rejectDesc = rejectionReason 
                    ? `${rejectionReason}${rejectionNotes ? ` (${rejectionNotes})` : ""}`
                    : "Technician was unable to fulfill this appointment slot";

                await handleFailedTradeInReassignment({
                    appointmentID: apptID,
                    tradeInRequestID: effectiveTradeInReqID,
                    scheduleID: effectiveSchedID,
                    taskID: effectiveTaskID,
                    appointmentDate: schedDate,
                    appointmentTime,
                    method,
                    reason: `Staff rejection: ${rejectDesc}. No replacement staff is currently available for this scheduled time slot.`
                });

                return res.status(200).json({
                    success: true,
                    reassigned: false,
                    onHold: true,
                    message: "Task rejected. No replacement staff available; appointment placed On Hold and notification email sent to customer."
                });
            }
        }

        return res.status(200).json({
            success: true,
            message: "Task status updated successfully."
        });
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

        const isTradeIn = String(orderID || "").startsWith("TR") || String(taskID || "").includes("APP") || String(orderID || "").includes("APP");

        if (taskID) {
            const taskUpdate = {
                taskStatus: isTradeIn ? "Completed" : "Delivered",
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

        if (orderID && orderID.startsWith("TR")) {
            const trDoc = await db.collection("tradeInRequests").doc(orderID).get();
            if (trDoc.exists) {
                batch.set(trDoc.ref, {
                    requestStatus: "Collected",
                    collectedAt: new Date(),
                    proofOfCollectionUrl: proofOfDeliveryUrl || null,
                    updatedAt: new Date()
                }, { merge: true });
            }
        } else if (orderID) {
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

        if (taskID) {
            const cleanTID = String(taskID).trim();
            await db.collection("task").doc(cleanTID).set(updateData, { merge: true }).catch(() => {});
            if (!cleanTID.startsWith("TSK-")) {
                await db.collection("task").doc(`TSK-${cleanTID}`).set(updateData, { merge: true }).catch(() => {});
            }
        }

        if (orderID) {
            const clean = String(orderID).replace(/^#/, "").trim();
            await db.collection("delivery").doc(`DEL-${clean}`).set(updateData, { merge: true }).catch(() => {});
            if (clean.startsWith("TR-")) {
                await db.collection("tradeInRequests").doc(clean).set(updateData, { merge: true }).catch(() => {});
            }
            const tSnap1 = await db.collection("task").where("tradeInRequestID", "==", clean).get().catch(() => null);
            if (tSnap1 && !tSnap1.empty) {
                for (const d of tSnap1.docs) {
                    await d.ref.set(updateData, { merge: true }).catch(() => {});
                }
            }
        }

        // Keep in-memory socket cache synchronized
        const { activeDeliveryLocations } = require("./deliverySocket");
        if (activeDeliveryLocations) {
            const locObj = {
                orderID: String(orderID || "").replace(/^#/, "").trim(),
                lat: numericLat,
                lng: numericLng,
                heading: numericHeading,
                speed: 0,
                estimatedDistanceKm: updateData.estimatedDistance || null,
                estimatedDurationMinutes: updateData.estimatedDuration || null,
                timestamp: Date.now()
            };
            if (locObj.orderID) activeDeliveryLocations.set(locObj.orderID, locObj);
            if (taskID) {
                const tClean = String(taskID).replace(/^#/, "").trim();
                activeDeliveryLocations.set(tClean, locObj);
                activeDeliveryLocations.set(tClean.replace(/^TSK-/, ""), locObj);
            }
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
        let resolvedTaskID = `TSK-${orderID}`;
        let taskSnap = await db.collection("task").doc(resolvedTaskID).get();
        if (taskSnap.exists) {
            taskData = taskSnap.data();
        } else {
            const directSnap = await db.collection("task").doc(orderID).get();
            if (directSnap.exists) {
                taskData = directSnap.data();
                resolvedTaskID = orderID;
            } else {
                const trQuery = await db.collection("task")
                    .where("tradeInRequestID", "==", orderID)
                    .limit(1)
                    .get();
                if (!trQuery.empty) {
                    taskData = trQuery.docs[0].data();
                    resolvedTaskID = trQuery.docs[0].id;
                } else {
                    const appQuery = await db.collection("task")
                        .where("appointmentID", "==", orderID)
                        .limit(1)
                        .get();
                    if (!appQuery.empty) {
                        taskData = appQuery.docs[0].data();
                        resolvedTaskID = appQuery.docs[0].id;
                    }
                }
            }
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

        // Check if this is a trade-in request / appointment
        let tradeInReq = {};
        let tradeInAppt = {};
        if (!ordSnap.exists || taskData.tradeInRequestID || taskData.appointmentID) {
            const trDoc = await db.collection("tradeInRequests").doc(orderID).get();
            if (trDoc.exists) {
                tradeInReq = trDoc.data() || {};
            } else if (taskData.tradeInRequestID) {
                const trDoc2 = await db.collection("tradeInRequests").doc(taskData.tradeInRequestID).get();
                if (trDoc2.exists) tradeInReq = trDoc2.data() || {};
            }

            const apptID = taskData.appointmentID || (orderID.startsWith("APPT-") || orderID.startsWith("APT-") ? orderID : null);
            if (apptID) {
                const aDoc = await db.collection("tradeInAppointment").doc(apptID).get();
                if (aDoc.exists) tradeInAppt = aDoc.data() || {};
            } else if (orderID) {
                const aSnap = await db.collection("tradeInAppointment").where("tradeInRequestID", "==", orderID).limit(1).get();
                if (!aSnap.empty) tradeInAppt = aSnap.docs[0].data() || {};
            }
        }

        // Resolve customer address & destination coordinates
        let address = {};
        const addressID = orderData.addressID || tradeInAppt.addressID || tradeInReq.addressID || taskData.addressID;
        if (addressID) {
            const aDoc = await db.collection("address").doc(addressID).get();
            if (aDoc.exists) {
                address = aDoc.data() || {};
            }
        } else if (tradeInReq.inspectionAddress && typeof tradeInReq.inspectionAddress === "object") {
            address = tradeInReq.inspectionAddress;
        } else if (tradeInAppt.address && typeof tradeInAppt.address === "object") {
            address = tradeInAppt.address;
        }

        let destLat = Number(delData.destinationLat || address.lat || address.latitude || 0);
        let destLng = Number(delData.destinationLng || address.lng || address.longitude || 0);

        if ((!destLat || !destLng) && tradeInReq.inspectionAddress && typeof tradeInReq.inspectionAddress === "object") {
            destLat = Number(tradeInReq.inspectionAddress.lat || tradeInReq.inspectionAddress.latitude || 0);
            destLng = Number(tradeInReq.inspectionAddress.lng || tradeInReq.inspectionAddress.longitude || 0);
        }
        if (!destLat || !destLng) {
            destLat = 5.3911;
            destLng = 100.3237;
        }

        // Resolve task type and staff role
        const taskTypeStr = String(taskData.taskType || (tradeInAppt.appointmentType ? tradeInAppt.appointmentType.toLowerCase() : "") || (tradeInReq.inspectionMethod || "")).toLowerCase();
        const isInspect = taskTypeStr.includes("inspect");
        const isCollect = taskTypeStr.includes("collect");
        const defaultStaffTitle = isInspect ? "Inspector" : (isCollect ? "Collector" : "Delivery Specialist");

        // Resolve staff member
        const staffID = schedData.staffID || taskData.staffID || delData.staffID || "";
        let staffName = schedData.staffName || taskData.staffName || defaultStaffTitle;
        if (staffName === "Delivery Specialist" && (isInspect || isCollect)) {
            staffName = defaultStaffTitle;
        }
        let staffPhone = "";
        let staffLat = null;
        let staffLng = null;
        let staffHeading = 0;

        if (staffID) {
            const uDoc = await db.collection("users").doc(staffID).get();
            if (uDoc.exists) {
                const uData = uDoc.data();
                if (!staffName || staffName === "Delivery Specialist" || staffName === "Inspector" || staffName === "Collector") {
                    staffName = uData.fullName || uData.name || staffName;
                }
                staffPhone = uData.phoneNumber || uData.phone || "";

                if (uData.currentLat && uData.currentLng) {
                    staffLat = Number(uData.currentLat);
                    staffLng = Number(uData.currentLng);
                }
            }
        }

        // Top Priority: Live GPS location actively broadcast by staff via Socket.IO memory cache
        let isLiveGps = false;
        const { activeDeliveryLocations } = require("./deliverySocket");
        const cleanID = String(orderID).replace(/^#/, "").trim();
        const socketLoc = (activeDeliveryLocations && (
            activeDeliveryLocations.get(cleanID) ||
            (resolvedTaskID && activeDeliveryLocations.get(resolvedTaskID.replace(/^TSK-/, ''))) ||
            (resolvedTaskID && activeDeliveryLocations.get(resolvedTaskID)) ||
            (taskData.tradeInRequestID && activeDeliveryLocations.get(String(taskData.tradeInRequestID).replace(/^#/, ''))) ||
            (taskData.appointmentID && activeDeliveryLocations.get(String(taskData.appointmentID).replace(/^#/, ''))) ||
            activeDeliveryLocations.get(cleanID.replace(/^TR-/, '')) ||
            activeDeliveryLocations.get(`TR-${cleanID}`)
        )) || null;

        if (socketLoc && socketLoc.lat && socketLoc.lng) {
            staffLat = Number(socketLoc.lat);
            staffLng = Number(socketLoc.lng);
            staffHeading = Number(socketLoc.heading || 0);
            isLiveGps = true;
        } else if (delData.staffLat && delData.staffLng) {
            staffLat = Number(delData.staffLat);
            staffLng = Number(delData.staffLng);
            staffHeading = Number(delData.staffHeading || 0);
            isLiveGps = true;
        } else if (taskData.staffLat && taskData.staffLng) {
            staffLat = Number(taskData.staffLat);
            staffLng = Number(taskData.staffLng);
            staffHeading = Number(taskData.staffHeading || 0);
            isLiveGps = true;
        } else if (tradeInReq.staffLat && tradeInReq.staffLng) {
            staffLat = Number(tradeInReq.staffLat);
            staffLng = Number(tradeInReq.staffLng);
            staffHeading = Number(tradeInReq.staffHeading || 0);
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
            taskID: resolvedTaskID || null,
            taskType: isInspect ? "inspect" : (isCollect ? "collect" : (taskData.taskType || "deliver")),
            staffRole: defaultStaffTitle,
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
            staffName: staffName || defaultStaffTitle,
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
            taskType: "Deliver",
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

    // 5. Fetch and include Trade-In Inspection and Collection tasks for Admin View
    const processedTaskIds = new Set(taskList.map(t => t.taskID));
    for (const tDoc of tasksSnap.docs) {
        const tData = tDoc.data();
        const tid = tData.taskID || tDoc.id;
        if (processedTaskIds.has(tid)) continue;

        const isTradeInTask = Boolean(tData.appointmentID || tData.taskType === "inspect" || tData.taskType === "collect");
        if (!isTradeInTask) continue;
        processedTaskIds.add(tid);

        const appointmentID = tData.appointmentID || (tData.tradeInRequestID ? null : tid.replace(/^TSK-/, ''));
        let aData = {};
        if (appointmentID) {
            const aDoc = await db.collection("tradeInAppointment").doc(appointmentID).get();
            if (aDoc.exists) aData = aDoc.data();
        }

        const tradeInRequestID = tData.tradeInRequestID || aData.tradeInRequestID || null;
        let trData = {};
        if (tradeInRequestID) {
            const trDoc = await db.collection("tradeInRequests").doc(tradeInRequestID).get();
            if (trDoc.exists) trData = trDoc.data();
        }

        // Query device details from devices collection via tradeInRequests -> deviceID
        let devData = {};
        const deviceID = trData.deviceID || tData.deviceID || aData.deviceID || null;
        if (deviceID) {
            try {
                let devDoc = await db.collection("devices").doc(deviceID).get();
                if (!devDoc.exists) {
                    devDoc = await db.collection("device").doc(deviceID).get();
                }
                if (!devDoc.exists) {
                    const devQuery = await db.collection("devices").where("deviceID", "==", deviceID).limit(1).get();
                    if (!devQuery.empty) devDoc = devQuery.docs[0];
                }
                if (devDoc && devDoc.exists) {
                    devData = devDoc.data() || {};
                }
            } catch (dErr) {
                console.error("Error fetching device for trade-in in admin tasks:", dErr);
            }
        }
        if (!devData.model && tradeInRequestID) {
            try {
                const devQuery = await db.collection("devices").where("tradeInRequestID", "==", tradeInRequestID).limit(1).get();
                if (!devQuery.empty) {
                    devData = devQuery.docs[0].data() || {};
                }
            } catch (_) {}
        }

        // Fetch device image from subcollection if not available
        let devImageUrl = trData.deviceImageUrl || trData.imageUrl || devData.imageUrl || "";
        if (!devImageUrl && tradeInRequestID) {
            try {
                const imgSnap = await db.collection("tradeInRequests").doc(tradeInRequestID).collection("images").limit(1).get();
                if (!imgSnap.empty) {
                    devImageUrl = imgSnap.docs[0].data().imageUrl || "";
                }
            } catch (_) {}
        }

        // Schedule
        const scheduleID = tData.scheduleID || aData.scheduleID || "";
        const schedData = (scheduleID ? schedMap.get(scheduleID) : null) || {};

        // Staff
        const staffID = schedData.staffID || tData.staffID || "";
        const staffInfo = staffMap.get(staffID);
        const staffName = staffInfo ? staffInfo.name : (schedData.staffName || tData.staffName || "Unassigned");

        // Customer & Address
        let address = {};
        const addressID = aData.addressID || trData.addressID || (trData.inspectionAddress && trData.inspectionAddress.addressID);
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
        if (!address.addressLine && trData.inspectionAddress && typeof trData.inspectionAddress === "object") {
            address = trData.inspectionAddress;
        } else if (!address.addressLine && aData.address && typeof aData.address === "object") {
            address = aData.address;
        }

        let customerName = trData.customerName || trData.name || address.recipientName || address.recipentName || "";
        const customerEmail = trData.customerEmail || trData.email || trData.userEmail || devData.userEmail || address.email || "";
        let customerPhone = trData.customerPhone || trData.phone || trData.contactNumber || address.phoneNumber || "";

        // Fallback customer name & phone from users collection
        if ((!customerName || customerName === "Customer") && customerEmail) {
            try {
                const uSnap = await db.collection("users").where("email", "==", customerEmail).limit(1).get();
                if (!uSnap.empty) {
                    const uData = uSnap.docs[0].data();
                    customerName = uData.fullName || uData.name || customerName || "Customer";
                    if (!customerPhone) customerPhone = uData.phoneNumber || uData.phone || "";
                }
            } catch (_) {}
        }
        if (!customerName) customerName = "Customer";

        const customerAddress = typeof trData.inspectionAddress === "string"
            ? trData.inspectionAddress
            : [address.addressLine, address.postcode, address.city, address.state].filter(Boolean).join(", ");

        // Determine Task Type: Inspect or Collect
        const rawType = String(tData.taskType || aData.appointmentType || trData.inspectionMethod || "Inspect").toLowerCase();
        const taskType = rawType.includes("collect") ? "Collect" : "Inspect";

        // Determine Admin displayStatus based on requirement:
        // Cancelled - show in cancel tab
        // Ongoing - show in assigned tab
        // Completed - show in completed tab
        const rawStatus = String(tData.taskStatus || schedData.scheduleStatus || aData.appointmentStatus || "Ongoing").toLowerCase();
        let displayStatus = "Assigned";
        if (rawStatus.includes("cancel")) {
            displayStatus = "Cancelled";
        } else if (rawStatus.includes("complete") || rawStatus.includes("done") || rawStatus === "inspected" || rawStatus === "collected") {
            displayStatus = "Completed";
        } else {
            // Ongoing -> show in assigned tab
            displayStatus = "Assigned";
        }

        // Resolve device details from devices record
        const deviceBrand = devData.brand || trData.deviceBrand || trData.brand || "Apple";
        let deviceModel = devData.model || devData.name || trData.deviceModel || trData.model || "Device";
        if (deviceModel.toLowerCase().startsWith(deviceBrand.toLowerCase()) && deviceModel.length > deviceBrand.length) {
            deviceModel = deviceModel.substring(deviceBrand.length).trim();
        }
        const storage = devData.storageCapacity || devData.storage || trData.storageCapacity || trData.storage || "";
        const color = devData.colour || devData.color || trData.colour || trData.color || trData.deviceColor || "";
        const condition = trData.deviceCondition || trData.reportedCondition || devData.condition || "Good";
        const imei = devData.imeiNum || devData.imei || trData.imei || trData.imeiNum || trData.serialNumber || "";

        let tradeInEstimate = trData.tradeInEstimate || trData.offeredPrice || 0;
        if (!tradeInEstimate && trData.estimatedValue) {
            if (typeof trData.estimatedValue === "number") {
                tradeInEstimate = trData.estimatedValue;
            } else if (typeof trData.estimatedValue === "object") {
                tradeInEstimate = trData.estimatedValue.max || trData.estimatedValue.min || 0;
            } else {
                const cleanStr = String(trData.estimatedValue).replace(/[^0-9.]/g, " ").trim();
                const numParts = cleanStr.split(/\s+/).map(Number).filter(n => !isNaN(n) && n > 0);
                tradeInEstimate = numParts.length > 0 ? numParts[numParts.length - 1] : 0;
            }
        }

        const specs = storage ? ` (${storage})` : "";
        const deviceSummary = `${deviceBrand} ${deviceModel}${specs}`.trim();

        let estimatedValueRange = "";
        if (trData.estimatedValue) {
            if (typeof trData.estimatedValue === "object") {
                const min = Number(trData.estimatedValue.min != null ? trData.estimatedValue.min : 2340.50);
                const max = Number(trData.estimatedValue.max != null ? trData.estimatedValue.max : 2355.30);
                estimatedValueRange = `RM ${min.toFixed(2)} - RM ${max.toFixed(2)}`;
            } else if (typeof trData.estimatedValue === "string") {
                estimatedValueRange = trData.estimatedValue.startsWith("RM") ? trData.estimatedValue : `RM ${trData.estimatedValue}`;
            }
        } else {
            estimatedValueRange = "RM 2,340.50 - RM 2,355.30";
        }

        // Appointment Date & Time
        let appointmentDate = "Upcoming";
        if (schedData.scheduleDate) {
            appointmentDate = formatAppointmentDate(schedData.scheduleDate);
        } else if (aData.scheduledAt) {
            appointmentDate = formatAppointmentDate(aData.scheduledAt);
        } else if (trData.appointmentDate) {
            appointmentDate = formatAppointmentDate(trData.appointmentDate);
        }

        let appointmentTime = "09:30 AM";
        if (schedData.scheduleStartTime && schedData.scheduleEndTime) {
            appointmentTime = `${schedData.scheduleStartTime} - ${schedData.scheduleEndTime}`;
        } else if (schedData.scheduleStartTime) {
            appointmentTime = schedData.scheduleStartTime;
        } else if (tData.taskStartTime) {
            appointmentTime = tData.taskStartTime;
        } else if (trData.appointmentTime) {
            appointmentTime = trData.appointmentTime;
        }

        let createdAtMs = Date.now();
        if (tData.createdAt) {
            const cd = tData.createdAt.toDate ? tData.createdAt.toDate() : new Date(tData.createdAt);
            if (!isNaN(cd.getTime())) createdAtMs = cd.getTime();
        } else if (aData.createdAt) {
            const cd = aData.createdAt.toDate ? aData.createdAt.toDate() : new Date(aData.createdAt);
            if (!isNaN(cd.getTime())) createdAtMs = cd.getTime();
        }

        taskList.push({
            taskID: tid,
            orderID: tradeInRequestID || appointmentID || tid,
            scheduleID: scheduleID || null,
            staffID: staffID || null,
            staffName: staffName || "Unassigned",
            customerID: trData.userID || devData.userEmail || "",
            customerName,
            customerEmail,
            customerPhone,
            deliveryAddress: customerAddress || "Customer Address",
            deviceSummary,
            taskType, // "Inspect" or "Collect"
            device: {
                name: `${deviceBrand} ${deviceModel}`.trim(),
                brand: deviceBrand,
                model: deviceModel,
                storage,
                color,
                condition,
                imei,
                imageUrl: devImageUrl,
                tradeInEstimate
            },
            items: [{
                productID: tradeInRequestID || appointmentID || tid,
                brand: deviceBrand,
                model: deviceModel,
                storage,
                color,
                condition,
                price: tradeInEstimate,
                tradeInEstimate,
                imei,
                imageUrl: devImageUrl
            }],
            appointmentDate,
            appointmentTime,
            isUrgent: false,
            orderStatus: displayStatus,
            taskStatus: tData.taskStatus || "Ongoing",
            fulfillmentType: taskType,
            displayStatus,
            totalAmount: tradeInEstimate,
            estimatedValue: trData.estimatedValue || { min: 2340.50, max: 2355.30 },
            estimatedValueRange,
            rejectionReason: "",
            rejectionNotes: "",
            proofOfDeliveryUrl: "",
            estimatedDistance: tData.estimatedDistance || 0,
            estimatedDuration: tData.estimatedDuration || 0,
            completedAt: tData.completedAt || null,
            createdAt: new Date(createdAtMs).toISOString(),
            createdAtMs
        });
    }

    // Sort strictly based on order/task createdAt date time (newest first)
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
 *   type: 'deliver' | 'inspect' | 'collect' | 'all'
 *   page: 1-based page number (default 1)
 *   limit: page size (default 10)
 *   search: keyword filter
 *   sort: 'asc' | 'desc' (default 'desc')
 */
router.get("/admin/tasks", async (req, res) => {
    try {
        const { taskList, counts } = await getOrBuildTasksDataset();

        const tab = String(req.query.tab || "").trim().toLowerCase();
        const typeFilter = String(req.query.type || "").trim().toLowerCase();
        const page = Math.max(1, parseInt(req.query.page, 10) || 1);
        const limit = Math.max(1, Math.min(100, parseInt(req.query.limit, 10) || 10));
        const search = String(req.query.search || "").trim().toLowerCase();
        const sortOrder = String(req.query.sort || "desc").trim().toLowerCase();

        // 1. Filter by Tab
        let filtered = taskList;
        if (tab && tab !== "all") {
            filtered = filtered.filter(t => (t.displayStatus || "").toLowerCase() === tab);
        }

        // 1b. Filter by Task Type (Deliver, Inspect, Collect)
        if (typeFilter && typeFilter !== "all") {
            filtered = filtered.filter(t => (t.taskType || "Deliver").toLowerCase() === typeFilter);
        }

        // 2. Filter by Search Query
        if (search) {
            filtered = filtered.filter(t => {
                const matchStr = `${t.taskID || ''} ${t.orderID || ''} ${t.customerName || ''} ${t.deviceSummary || ''} ${t.deliveryAddress || ''} ${t.staffName || ''} ${t.taskType || ''}`.toLowerCase();
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

        // 1. Fetch Order or Trade-In Task
        let isTradeIn = false;
        let trData = {};
        let aData = {};
        let devData = {};
        let orderData = {};

        const orderDoc = await db.collection("order").doc(orderID).get();
        if (orderDoc.exists) {
            orderData = orderDoc.data();
        } else {
            // Check if orderID belongs to tradeInRequests, tradeInAppointment, or task
            const trDoc = await db.collection("tradeInRequests").doc(orderID).get();
            if (trDoc.exists) {
                isTradeIn = true;
                trData = trDoc.data() || {};
            } else {
                const aDoc = await db.collection("tradeInAppointment").doc(orderID).get();
                if (aDoc.exists) {
                    isTradeIn = true;
                    aData = aDoc.data() || {};
                    if (aData.tradeInRequestID) {
                        const rDoc = await db.collection("tradeInRequests").doc(aData.tradeInRequestID).get();
                        if (rDoc.exists) trData = rDoc.data() || {};
                    }
                } else {
                    let tDoc = await db.collection("task").doc(orderID).get();
                    if (!tDoc.exists) {
                        const tSnap = await db.collection("task").where("orderID", "==", orderID).limit(1).get();
                        if (!tSnap.empty) tDoc = tSnap.docs[0];
                    }
                    if (tDoc && tDoc.exists) {
                        const tD = tDoc.data();
                        if (tD.tradeInRequestID || tD.appointmentID || tD.taskType === "inspect" || tD.taskType === "collect") {
                            isTradeIn = true;
                            if (tD.tradeInRequestID) {
                                const rDoc = await db.collection("tradeInRequests").doc(tD.tradeInRequestID).get();
                                if (rDoc.exists) trData = rDoc.data() || {};
                            }
                            if (tD.appointmentID) {
                                const aDoc = await db.collection("tradeInAppointment").doc(tD.appointmentID).get();
                                if (aDoc.exists) aData = aDoc.data() || {};
                            }
                        }
                    }
                }
            }

            if (!isTradeIn) {
                return res.status(404).json({ success: false, error: `Order #${orderID} not found` });
            }
        }

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
            } else if (isTradeIn && aData.appointmentID) {
                const appTaskSnap = await db.collection("task").where("appointmentID", "==", aData.appointmentID).limit(1).get();
                if (!appTaskSnap.empty) {
                    taskData = appTaskSnap.docs[0].data();
                    taskID = taskData.taskID || appTaskSnap.docs[0].id;
                }
            }
        }

        // 3. Fetch Linked Schedule & Previous Staff Name
        let previousStaffName = taskData.staffName || "";
        let currentStaffID = taskData.staffID || "";
        let schedData = null;
        const scheduleID = taskData.scheduleID || orderData.scheduleID || aData.scheduleID || "";
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
        } else if (isTradeIn) {
            const addressID = aData.addressID || trData.addressID || (trData.inspectionAddress && trData.inspectionAddress.addressID);
            if (addressID) {
                const addrDoc = await db.collection("address").doc(addressID).get();
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
                    if (parts.length > 0) locationDisplay = parts.join(", ");
                }
            }
            if (locationDisplay === "Hub C - Bay 4" && trData.inspectionAddress) {
                if (typeof trData.inspectionAddress === "string") {
                    locationDisplay = trData.inspectionAddress;
                } else if (typeof trData.inspectionAddress === "object") {
                    address = trData.inspectionAddress;
                    const parts = [address.addressLine, address.postcode, address.city, address.state].filter(Boolean);
                    if (parts.length > 0) locationDisplay = parts.join(", ");
                }
            }
        }

        // Fallback to delivery collection if addressID wasn't found or missing address
        if (locationDisplay === "Hub C - Bay 4" && !isTradeIn) {
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

        if (isTradeIn) {
            // Query device details from devices collection via tradeInRequests -> deviceID
            const devID = trData.deviceID || aData.deviceID || taskData.deviceID;
            if (devID) {
                try {
                    let devDoc = await db.collection("devices").doc(devID).get();
                    if (!devDoc.exists) devDoc = await db.collection("device").doc(devID).get();
                    if (!devDoc.exists) {
                        const devQuery = await db.collection("devices").where("deviceID", "==", devID).limit(1).get();
                        if (!devQuery.empty) devDoc = devQuery.docs[0];
                    }
                    if (devDoc && devDoc.exists) devData = devDoc.data() || {};
                } catch (_) {}
            }
            if (!devData.model && (trData.tradeInRequestID || orderID)) {
                try {
                    const devQuery = await db.collection("devices").where("tradeInRequestID", "==", trData.tradeInRequestID || orderID).limit(1).get();
                    if (!devQuery.empty) devData = devQuery.docs[0].data() || {};
                } catch (_) {}
            }
            deviceBrand = devData.brand || trData.deviceBrand || trData.brand || "Apple";
            deviceModel = devData.model || devData.name || trData.deviceModel || trData.model || "Device";
            if (deviceModel.toLowerCase().startsWith(deviceBrand.toLowerCase()) && deviceModel.length > deviceBrand.length) {
                deviceModel = deviceModel.substring(deviceBrand.length).trim();
            }
            deviceStorage = devData.storageCapacity || devData.storage || trData.storageCapacity || trData.storage || "";
            deviceColor = devData.colour || devData.color || trData.colour || trData.color || "";
            deviceImei = devData.imeiNum || devData.imei || trData.imei || trData.imeiNum || "";
            deviceName = [deviceBrand, deviceModel, deviceStorage].filter(Boolean).join(" ");
        } else {
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
        }

        // 6. Cancellation Reason & Priority
        const cancellationReason = taskData.rejectionReason || 
                                   taskData.rejectionNotes || 
                                   "Client arrived late and I have a conflicting with next task. Needs immediate reassignment to clear queue.";

        const orderDateRaw = orderData.orderDate || orderData.createdAt || aData.scheduledAt || trData.submittedAt;
        let isUrgent = !!(orderData.isUrgent || taskData.isUrgent);
        if (orderDateRaw) {
            const dateObj = orderDateRaw.toDate ? orderDateRaw.toDate() : new Date(orderDateRaw);
            if (!isNaN(dateObj.getTime()) && dateObj.getHours() < 9) {
                isUrgent = true;
            }
        }

        // 7. Task Type Determination
        const fulfillmentType = String(orderData.fulfillmentType || orderData.deliveryOption || (isTradeIn ? (taskData.taskType || aData.appointmentType || "Inspection") : "Delivery")).trim();
        const taskTypeRaw = String(taskData.taskType || (isTradeIn ? (aData.appointmentType || trData.inspectionMethod || "inspect") : "")).trim().toLowerCase();
        const isDelivery = !isTradeIn && (fulfillmentType.toLowerCase().includes("delivery") || 
                           taskTypeRaw.includes("deliver") || 
                           fulfillmentType.toLowerCase().includes("shipping"));
        const isCollect = isTradeIn && taskTypeRaw.includes("collect");
        const isInspect = isTradeIn && !isCollect;

        const taskTypeLabel = isInspect ? "Inspection Task" : (isCollect ? "Collection Task" : "Delivery Task");
        const displayStatus = isTradeIn ? (taskData.taskStatus || "Ongoing") : computeDisplayStatus(orderData.orderStatus, taskData.taskStatus, fulfillmentType, orderData.cancelledBy, taskData.rejectionReason, currentStaffID);

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
            if (timeVal instanceof Date) return isNaN(timeVal.getTime()) ? null : timeVal;
            const str = String(timeVal).trim();
            if (str.includes("T") || (str.includes("-") && str.length > 8)) {
                const dt = new Date(str);
                return isNaN(dt.getTime()) ? null : dt;
            }

            const baseDate = dateStr || "2026-10-21";

            const isAmPm = /am|pm/i.test(str);
            if (isAmPm) {
                const isPm = /pm/i.test(str);
                const cleanStr = str.replace(/am|pm/i, "").trim();
                const parts = cleanStr.split(":");
                if (parts.length >= 2) {
                    let hours = parseInt(parts[0], 10);
                    const minutes = parseInt(parts[1], 10);
                    if (isPm && hours < 12) hours += 12;
                    if (!isPm && hours === 12) hours = 0;
                    const hh = String(hours).padStart(2, "0");
                    const mm = String(minutes).padStart(2, "0");
                    const d = new Date(`${baseDate}T${hh}:${mm}:00`);
                    return isNaN(d.getTime()) ? null : d;
                }
            }

            const parts = str.split(":");
            if (parts.length >= 2) {
                const hh = parts[0].padStart(2, "0");
                const mm = parts[1].padStart(2, "0");
                const ss = parts[2] ? parts[2].padStart(2, "0") : "00";
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

            // Filter by Position based on Task Type:
            if (isDelivery) {
                if (pos !== "deliverer" && pos !== "both") continue;
            } else if (isCollect) {
                if (!pos.includes("collect") && pos !== "both") continue;
            } else {
                if (!pos.includes("inspect") && pos !== "both") continue;
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

        // Check if orderID is a delivery order or a trade-in task
        const checkOrder = await db.collection("order").doc(orderID).get();
        if (!checkOrder.exists) {
            let reqID = orderID;
            let appID = null;
            const appDoc = await db.collection("tradeInAppointment").doc(orderID).get();
            if (appDoc.exists) {
                appID = orderID;
                reqID = appDoc.data().tradeInRequestID || orderID;
            } else {
                const trDoc = await db.collection("tradeInRequests").doc(orderID).get();
                if (trDoc.exists) {
                    reqID = orderID;
                    appID = trDoc.data().appointmentID || appID;
                } else {
                    const tDoc = await db.collection("task").doc(orderID).get();
                    if (tDoc.exists) {
                        const td = tDoc.data();
                        reqID = td.tradeInRequestID || reqID;
                        appID = td.appointmentID || appID;
                    }
                }
            }

            let tID = null;
            if (appID) {
                const tSnap = await db.collection("task").where("appointmentID", "==", appID).limit(1).get();
                if (!tSnap.empty) tID = tSnap.docs[0].id;
            }
            if (!tID && reqID) {
                const tSnap = await db.collection("task").where("tradeInRequestID", "==", reqID).limit(1).get();
                if (!tSnap.empty) tID = tSnap.docs[0].id;
            }

            const result = await assignTradeInTask({
                tradeInRequestID: reqID,
                existingAppointmentID: appID,
                existingTaskID: tID,
                specificStaffID: (staffID && staffID !== "auto") ? staffID : null
            });

            if (result && result.success) {
                if (result.scheduleID) {
                    registerScheduleTimer(result.scheduleID);
                }
                invalidateTaskCache();
            }
            return res.json(result);
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

                const scheduleID = sDoc.id;

                // 1. Fetch corresponding task to accurately determine task type
                let taskData = null;
                let taskID = null;
                const tSnap = await db.collection("task").where("scheduleID", "==", scheduleID).limit(1).get();
                if (!tSnap.empty) {
                    taskData = tSnap.docs[0].data();
                    taskID = taskData.taskID || tSnap.docs[0].id;
                } else if (sData.orderID) {
                    const directTask = await db.collection("task").doc(`TSK-${sData.orderID}`).get();
                    if (directTask.exists) {
                        taskData = directTask.data();
                        taskID = directTask.id;
                    }
                }

                const orderID = sData.orderID || (taskData && taskData.orderID);
                const taskType = (taskData && taskData.taskType) ? String(taskData.taskType).toLowerCase() : "";
                const isDelivery = Boolean(orderID) || taskType === "deliver";
                const isTradeIn = Boolean(taskData && taskData.appointmentID) || taskType === "inspect" || taskType === "collect";

                // Mark current schedule as reassigned due to leave
                await sDoc.ref.set({
                    scheduleStatus: "reassigned",
                    reassignReason: `Staff on approved leave (${leaveID})`,
                    reassignedAt: new Date().toISOString(),
                    updatedAt: new Date().toISOString()
                }, { merge: true });

                // Clear existing timers for this schedule
                clearScheduleTimers(scheduleID);

                if (isDelivery && orderID) {
                    console.log(`[REASSIGN ON LEAVE] Reassigning Delivery Task Order #${orderID} (Schedule ${scheduleID}) on ${dateStr} due to approved leave [${leaveID}] 1 by 1...`);

                    // Reassign task 1-by-1 to a suitable delivery staff
                    const reassignResult = await assignDeliveryTask({
                        orderID,
                        addressID: sData.addressID,
                        requestedDate: dateStr,
                        forceNextDay: false, // Try same day first with other eligible deliverers; cascades if all full
                        excludeStaffIDs: [staffID]
                    });

                    if (reassignResult && reassignResult.success) {
                        if (reassignResult.scheduleID) {
                            registerScheduleTimer(reassignResult.scheduleID);
                        }
                        totalReassigned++;
                        console.log(`[REASSIGN ON LEAVE SUCCESS] Delivery Order #${orderID} reassigned to ${reassignResult.staffName || reassignResult.staffID} on ${reassignResult.scheduleDate} (${reassignResult.scheduleStartTime})`);
                    } else {
                        console.warn(`[REASSIGN ON LEAVE WARNING] Could not automatically reassign Delivery Order #${orderID}:`, reassignResult?.reason || reassignResult?.message);
                    }
                } else if (isTradeIn) {
                    const appointmentID = (taskData && taskData.appointmentID) || sData.appointmentID;
                    let appData = {};
                    if (appointmentID) {
                        const aDoc = await db.collection("tradeInAppointment").doc(appointmentID).get();
                        if (aDoc.exists) appData = aDoc.data();
                    }

                    const rawType = (appData.appointmentType || (taskData && taskData.taskType) || "Inspect").toLowerCase();
                    const method = rawType.includes("collect") ? "Doorstep Collection" : "On-Site Inspection";
                    const tradeInRequestID = appData.tradeInRequestID || (taskData && taskData.tradeInRequestID) || null;
                    const addressID = appData.addressID || sData.addressID || null;
                    const appointmentTime = sData.scheduleStartTime || (taskData && taskData.taskStartTime) || "09:00 AM";

                    console.log(`[REASSIGN ON LEAVE] Reassigning Trade-In ${method} Task (Appointment ${appointmentID || scheduleID}) on ${dateStr} ${appointmentTime} due to approved leave [${leaveID}] 1 by 1...`);

                    const reassignResult = await assignTradeInTask({
                        tradeInRequestID,
                        method,
                        appointmentDate: dateStr,
                        appointmentTime,
                        addressID,
                        excludeStaffIDs: [staffID],
                        existingAppointmentID: appointmentID,
                        existingTaskID: taskID
                    });

                    if (reassignResult && reassignResult.success) {
                        totalReassigned++;
                        console.log(`[REASSIGN ON LEAVE SUCCESS] Trade-In ${method} Task reassigned to ${reassignResult.staffName || reassignResult.staffID} on ${reassignResult.scheduleDate} (${reassignResult.scheduleStartTime})`);
                    } else {
                        console.warn(`[REASSIGN ON LEAVE WARNING] Could not automatically reassign Trade-In task ${appointmentID}:`, reassignResult?.message);
                        await handleFailedTradeInReassignment({
                            appointmentID,
                            tradeInRequestID,
                            scheduleID,
                            taskID,
                            appointmentDate: dateStr,
                            appointmentTime,
                            method,
                            reason: `Assigned technician is on approved leave (${leaveID}) and no replacement staff is currently available for this time slot.`
                        });
                    }
                } else {
                    console.log(`[REASSIGN ON LEAVE] Schedule ${scheduleID} on ${dateStr} is neither delivery nor trade-in. Skipping reassignment.`);
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

