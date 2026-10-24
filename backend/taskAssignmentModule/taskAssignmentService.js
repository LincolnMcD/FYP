const db = require("../config/firebase");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { COMPANY_LOCATION, getOsrmRoute } = require("./osrmService");
const nodemailer = require("nodemailer");

// Nodemailer transporter for trade-in on-hold notifications
const tradeInEmailTransporter = nodemailer.createTransport({
    service: "gmail",
    auth: {
        user: "lolincoln021@gmail.com",
        pass: "uooc wvdf zoqy nujh"
    }
});

/**
 * Send an email notification to the customer when their trade-in inspection/collection appointment
 * cannot be automatically reassigned and is placed On Hold.
 */
async function sendTradeInOnHoldEmail({
    toEmail,
    customerName,
    tradeInRequestID,
    appointmentID,
    appointmentType,
    appointmentDate,
    appointmentTime,
    deviceInfo,
    reason
}) {
    if (!toEmail) {
        console.warn("[TRADE-IN ON HOLD EMAIL] No customer email provided, skipping email notification.");
        return { success: false, error: "No recipient email" };
    }

    const typeLabel = String(appointmentType || "Inspection").toLowerCase().includes("collect")
        ? "Doorstep Collection"
        : "On-Site Inspection";

    const formattedTime = appointmentTime || "TBD";
    const formattedDate = appointmentDate || "TBD";
    const deviceName = deviceInfo || "Your registered device";

    const mailOptions = {
        from: '"ReByte Support" <lolincoln021@gmail.com>',
        to: toEmail,
        subject: `Action Required: Your ReByte Trade-In ${typeLabel} is On Hold (${tradeInRequestID || appointmentID})`,
        html: `
        <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 24px; background-color: #f8fafc; color: #0f172a;">
            <div style="background-color: #ffffff; border-radius: 16px; padding: 32px; border: 1px solid #e2e8f0; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.05);">
                <div style="text-align: center; margin-bottom: 24px;">
                    <div style="display: inline-block; background-color: #fff7ed; padding: 12px; border-radius: 50%; margin-bottom: 12px;">
                        <span style="font-size: 32px; color: #ea580c;">⏳</span>
                    </div>
                    <h2 style="margin: 0; color: #0f172a; font-size: 22px; font-weight: 800;">Appointment On Hold</h2>
                    <p style="margin: 6px 0 0 0; color: #64748b; font-size: 14px;">Action Required for Your Trade-In Request</p>
                </div>

                <p style="font-size: 15px; line-height: 1.6; color: #334155;">
                    Dear <strong>${customerName || "Customer"}</strong>,
                </p>
                <p style="font-size: 14.5px; line-height: 1.6; color: #475569;">
                    We are reaching out to inform you that your upcoming <strong>${typeLabel}</strong> appointment scheduled for <strong>${formattedDate} at ${formattedTime}</strong> has been temporarily placed <strong>On Hold</strong>.
                </p>
                <div style="background-color: #fffbeb; padding: 14px; border-radius: 10px; border-left: 4px solid #f59e0b; margin: 18px 0;">
                    <p style="margin: 0; font-size: 13.5px; line-height: 1.5; color: #92400e;">
                        <strong>Reason:</strong> ${reason || "Due to technician schedule adjustment or leave, our team is currently unable to fulfill your original appointment slot."}
                    </p>
                </div>

                <div style="background-color: #f8fafc; border-radius: 12px; padding: 18px; margin: 24px 0; border: 1px solid #e2e8f0;">
                    <h4 style="margin: 0 0 12px 0; color: #0f172a; font-size: 13px; text-transform: uppercase; letter-spacing: 0.5px;">Appointment Details</h4>
                    <table style="width: 100%; border-collapse: collapse; font-size: 13.5px;">
                        <tr>
                            <td style="padding: 6px 0; color: #64748b;">Request ID:</td>
                            <td style="padding: 6px 0; font-weight: 700; color: #0f172a; text-align: right;">${tradeInRequestID || "N/A"}</td>
                        </tr>
                        <tr>
                            <td style="padding: 6px 0; color: #64748b;">Appointment ID:</td>
                            <td style="padding: 6px 0; font-weight: 700; color: #0f172a; text-align: right;">${appointmentID || "N/A"}</td>
                        </tr>
                        <tr>
                            <td style="padding: 6px 0; color: #64748b;">Device:</td>
                            <td style="padding: 6px 0; font-weight: 700; color: #0f172a; text-align: right;">${deviceName}</td>
                        </tr>
                        <tr>
                            <td style="padding: 6px 0; color: #64748b;">Service Type:</td>
                            <td style="padding: 6px 0; font-weight: 700; color: #0f172a; text-align: right;">${typeLabel}</td>
                        </tr>
                    </table>
                </div>

                <div style="margin: 28px 0 20px 0;">
                    <h3 style="margin: 0 0 10px 0; font-size: 15px; color: #0f172a;">What would you like to do?</h3>
                    <p style="margin: 0 0 14px 0; font-size: 14px; color: #475569; line-height: 1.5;">
                        Please open the <strong>ReByte App</strong> and navigate to <strong>My Trade-In Requests</strong> to select an option:
                    </p>
                    <ul style="margin: 0; padding-left: 20px; font-size: 13.5px; color: #475569; line-height: 1.6;">
                        <li><strong>Reselect Date & Time:</strong> Choose any other available date and time slot, or update your inspection/collection address.</li>
                        <li><strong>Cancel Inspection:</strong> You may cancel your trade-in request at any time without penalty.</li>
                    </ul>
                </div>

                <div style="border-top: 1px solid #e2e8f0; padding-top: 20px; text-align: center; color: #94a3b8; font-size: 12px;">
                    <p style="margin: 0;">ReByte Customer Support • We appreciate your patience and understanding.</p>
                </div>
            </div>
        </div>
        `
    };

    try {
        const info = await tradeInEmailTransporter.sendMail(mailOptions);
        console.log(`[TRADE-IN ON HOLD EMAIL SENT] Notification delivered to ${toEmail} (Message ID: ${info.messageId})`);
        return { success: true, messageId: info.messageId };
    } catch (emailErr) {
        console.error(`[TRADE-IN ON HOLD EMAIL ERROR] Failed to send email to ${toEmail}:`, emailErr);
        return { success: false, error: emailErr.message };
    }
}

/**
 * Handle failed reassignment when no replacement staff is available.
 * Sets tradeInAppointment to 'On Hold', updates tradeInRequests, and sends email notification via Nodemailer.
 */
async function handleFailedTradeInReassignment({
    appointmentID,
    tradeInRequestID,
    scheduleID,
    taskID,
    appointmentDate,
    appointmentTime,
    method,
    reason
}) {
    console.log(`[TRADE-IN REASSIGN FAILED] Handling unassigned appointment [${appointmentID || "N/A"}] / request [${tradeInRequestID || "N/A"}]...`);

    let appData = {};
    if (appointmentID) {
        try {
            const aDoc = await db.collection("tradeInAppointment").doc(appointmentID).get();
            if (aDoc.exists) appData = aDoc.data();
        } catch (_) {}
    }

    const effectiveReqID = tradeInRequestID || appData.tradeInRequestID;

    let reqData = {};
    if (effectiveReqID) {
        try {
            const rDoc = await db.collection("tradeInRequests").doc(effectiveReqID).get();
            if (rDoc.exists) reqData = rDoc.data();
        } catch (_) {}
    }

    // Resolve customer email and name
    let toEmail = reqData.userEmail || reqData.email || appData.customerEmail || appData.email;
    let customerName = reqData.userName || reqData.name || appData.customerName || "Customer";

    if (!toEmail && reqData.userId) {
        try {
            const uDoc = await db.collection("users").doc(reqData.userId).get();
            if (uDoc.exists) {
                const uData = uDoc.data();
                toEmail = toEmail || uData.email;
                if (customerName === "Customer") customerName = uData.fullName || uData.name || customerName;
            }
        } catch (_) {}
    }

    const addressID = appData.addressID || reqData.addressID;
    if (!toEmail && addressID) {
        try {
            const addrDoc = await db.collection("addresses").doc(addressID).get();
            if (addrDoc.exists) {
                const addrData = addrDoc.data();
                if (customerName === "Customer") customerName = addrData.recipientName || addrData.name || customerName;
            }
        } catch (_) {}
    }

    let deviceInfo = reqData.deviceBrand ? `${reqData.deviceBrand} ${reqData.deviceModel || ""}`.trim() : null;
    if (!deviceInfo && reqData.deviceID) {
        try {
            const devDoc = await db.collection("devices").doc(reqData.deviceID).get();
            if (devDoc.exists) {
                const dData = devDoc.data();
                deviceInfo = `${dData.brand || ""} ${dData.model || dData.name || ""}`.trim();
            }
        } catch (_) {}
    }

    // 1. Update tradeInAppointment record to 'On Hold'
    if (appointmentID) {
        await db.collection("tradeInAppointment").doc(appointmentID).update({
            appointmentStatus: "On Hold",
            onHoldReason: reason || "No replacement staff available for scheduled slot",
            onHoldAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp()
        }).catch(err => console.error("Error setting tradeInAppointment On Hold:", err));
    }

    // 2. Update tradeInRequests record to 'On Hold'
    if (effectiveReqID) {
        await db.collection("tradeInRequests").doc(effectiveReqID).update({
            requestStatus: "On Hold",
            bookingStatus: "On Hold",
            onHoldReason: reason || "No replacement staff available for scheduled slot",
            updatedAt: FieldValue.serverTimestamp()
        }).catch(err => console.error("Error setting tradeInRequests On Hold:", err));
    }

    // 3. Update task record if present
    if (taskID) {
        await db.collection("task").doc(taskID).update({
            taskStatus: "On Hold",
            updatedAt: new Date()
        }).catch(err => console.error("Error setting task On Hold:", err));
    }

    // 4. Send email notification via Nodemailer
    await sendTradeInOnHoldEmail({
        toEmail,
        customerName,
        tradeInRequestID: effectiveReqID,
        appointmentID,
        appointmentType: method || appData.appointmentType,
        appointmentDate,
        appointmentTime,
        deviceInfo,
        reason
    });
}

// Configurable working hours & constraints
const WORKING_HOUR_CONFIG = {
    startHour: 9,                 // 9:00 AM
    endHour: 17,                  // 5:00 PM (17:00)
    lunchStartHour: 12,           // 12:00 PM Lunch Break Start (Unassigned)
    lunchEndHour: 13,             // 1:00 PM Lunch Break End
    slotIntervalHours: 1,         // 1 hour step
    bufferMinutes: 15,            // Default 15 min buffer between tasks
    shortDistanceBufferMinutes: 10, // 10 min buffer if travel distance < 500m (0.5 km)
    maxDeliveriesPerDay: 8,       // Constraint: Maximum 8 deliveries per person per day
    defaultMaxTasks: 8            // Default max tasks cap
};

/**
 * Get applicable buffer time in minutes based on travel distance
 * If distance is less than 500m (0.5 km), buffer is 10 mins; otherwise 15 mins.
 */
function getBufferMinutes(distanceKm) {
    if (typeof distanceKm === "number" && distanceKm < 0.5) {
        return WORKING_HOUR_CONFIG.shortDistanceBufferMinutes;
    }
    return WORKING_HOUR_CONFIG.bufferMinutes;
}

/**
 * Get current time in Malaysia timezone (UTC+8)
 */
function getMalaysiaNow() {
    const nowUtc = new Date();
    const utcMs = nowUtc.getTime() + (nowUtc.getTimezoneOffset() * 60000);
    return new Date(utcMs + (8 * 3600000));
}

/**
 * Format a Date object to YYYY-MM-DD
 */
function formatDateKey(d) {
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, "0");
    const day = String(d.getDate()).padStart(2, "0");
    return `${year}-${month}-${day}`;
}

/**
 * Format a Date object to HH:mm string (e.g. "09:00", "14:35")
 */
function formatTimeOnly(d) {
    return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

/**
 * Parse a time string (e.g. "09:00", "9:33", ISO string, or Firestore timestamp) into a JavaScript Date
 */
function parseScheduleDate(timeVal, dateStr) {
    if (!timeVal) return null;
    if (timeVal.toDate) return timeVal.toDate();
    if (timeVal instanceof Date) return isNaN(timeVal.getTime()) ? null : timeVal;
    const str = String(timeVal).trim();
    if (str.includes("T") || (str.includes("-") && str.length > 8)) {
        const d = new Date(str);
        if (!isNaN(d.getTime())) return d;
    }

    const baseDate = dateStr || formatDateKey(new Date());

    // Check if string contains AM or PM (e.g. "09:30 AM", "01:30 PM")
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

    // Normalize HH:mm or H:mm to two-digit HH:mm:00
    const parts = str.split(":");
    if (parts.length >= 2) {
        const hh = parts[0].padStart(2, "0");
        const mm = parts[1].padStart(2, "0");
        const ss = parts[2] ? parts[2].padStart(2, "0") : "00";
        const d = new Date(`${baseDate}T${hh}:${mm}:${ss}`);
        return isNaN(d.getTime()) ? null : d;
    }

    const d = new Date(`${baseDate}T${str}`);
    return isNaN(d.getTime()) ? null : d;
}

/**
 * Resolve customer coordinate {lat, lng} and state from addressID or geocodes address text
 */
async function resolveCustomerDetails(addressID) {
    if (!addressID) {
        return { location: { lat: 5.3542, lng: 100.3015 }, state: "Penang" };
    }

    try {
        const aDoc = await db.collection("address").doc(addressID).get();
        if (aDoc.exists) {
            const aData = aDoc.data();
            const state = aData.state || "Penang";

            if (aData.lat && aData.lng) {
                return { location: { lat: Number(aData.lat), lng: Number(aData.lng) }, state };
            }
            if (aData.latitude && aData.longitude) {
                return { location: { lat: Number(aData.latitude), lng: Number(aData.longitude) }, state };
            }

            const addressText = [aData.addressLine, aData.postcode, aData.city, aData.state]
                .filter(Boolean)
                .join(", ");

            if (addressText) {
                try {
                    const encoded = encodeURIComponent(addressText);
                    const geoRes = await fetch(
                        `https://nominatim.openstreetmap.org/search?format=json&q=${encoded}&countrycodes=my&limit=1`,
                        { headers: { "User-Agent": "ReByte-App/1.0" } }
                    );
                    if (geoRes.ok) {
                        const geoData = await geoRes.json();
                        if (Array.isArray(geoData) && geoData.length > 0) {
                            const exactLat = parseFloat(geoData[0].lat);
                            const exactLng = parseFloat(geoData[0].lon);
                            if (!isNaN(exactLat) && !isNaN(exactLng)) {
                                await db.collection("address").doc(addressID).update({
                                    lat: exactLat,
                                    lng: exactLng
                                }).catch(() => {});
                                return { location: { lat: exactLat, lng: exactLng }, state };
                            }
                        }
                    }
                } catch (geoErr) {
                    console.warn("Nominatim geocoding error:", geoErr.message);
                }
            }
            return { location: { lat: 5.4045, lng: 100.3333 }, state };
        }
    } catch (err) {
        console.warn("Failed to fetch address doc for coordinates:", err);
    }

    return { location: { lat: 5.4045, lng: 100.3333 }, state: "Penang" };
}

/**
 * Helper: parse date from string (DD/MM/YYYY, YYYY-MM-DD, ISO string, or Date object)
 */
function parseLeaveDate(dStr) {
    if (!dStr) return null;
    if (dStr instanceof Date) return isNaN(dStr.getTime()) ? null : dStr;
    if (dStr.toDate) return dStr.toDate();
    const str = String(dStr).trim();
    if (str.includes("/")) {
        const parts = str.split("/");
        if (parts.length === 3) {
            const day = parseInt(parts[0], 10);
            const month = parseInt(parts[1], 10) - 1;
            const year = parseInt(parts[2], 10);
            return new Date(year, month, day, 0, 0, 0);
        }
    }
    if (/^\d{4}-\d{2}-\d{2}/.test(str)) {
        const parts = str.substring(0, 10).split("-");
        const year = parseInt(parts[0], 10);
        const month = parseInt(parts[1], 10) - 1;
        const day = parseInt(parts[2], 10);
        return new Date(year, month, day, 0, 0, 0);
    }
    const d = new Date(str);
    return isNaN(d.getTime()) ? null : new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0);
}

/**
 * Fetch Set of staff IDs who have an approved leave covering the given targetDate
 */
async function getStaffIDsOnApprovedLeave(targetDate) {
    const checkDt = parseLeaveDate(targetDate);
    if (!checkDt) return new Set();

    try {
        const leaveSnap = await db.collection("leaveApplication")
            .where("leaveStatus", "in", ["Approved", "approved"])
            .get();

        const staffOnLeave = new Set();
        for (const doc of leaveSnap.docs) {
            const data = doc.data();
            const staffId = data.applicantStaffID;
            if (!staffId) continue;

            const sDate = parseLeaveDate(data.startDate);
            const eDate = parseLeaveDate(data.endDate);

            if (sDate && eDate) {
                const startMidnight = new Date(sDate.getFullYear(), sDate.getMonth(), sDate.getDate(), 0, 0, 0);
                const endMidnight = new Date(eDate.getFullYear(), eDate.getMonth(), eDate.getDate(), 23, 59, 59, 999);
                if (checkDt >= startMidnight && checkDt <= endMidnight) {
                    staffOnLeave.add(staffId);
                }
            }
        }
        return staffOnLeave;
    } catch (err) {
        console.error("Error fetching approved leaves in getStaffIDsOnApprovedLeave:", err);
        return new Set();
    }
}

/**
 * Fetch all active delivery staff who do NOT have an approved leave on targetDate
 * Staff must be: Deliverer only + no approved leave request
 */
async function getEligibleDeliveryStaff(targetDate = null) {
    const usersSnap = await db.collection("users")
        .where("role", "in", ["Staff", "staff"])
        .get();

    let staffOnLeave = new Set();
    if (targetDate) {
        staffOnLeave = await getStaffIDsOnApprovedLeave(targetDate);
    }

    const staffList = [];

    for (const doc of usersSnap.docs) {
        const data = doc.data();
        const status = String(data.status || data.staffStatus || "active").toLowerCase().trim();
        if (status === "archived") continue;

        const pos = String(data.position || data.roleType || "").toLowerCase().trim();
        // Delivery tasks only assigned to Deliverer staff (no longer Both / Inspector & Collector)
        const isDeliveryRole = pos === "deliverer" || (pos.includes("deliver") && !pos.includes("inspector") && !pos.includes("both"));
        if (!isDeliveryRole) continue;

        const staffID = doc.id;

        // Constraint: Staff with approved leave covering target date cannot be selected
        if (staffOnLeave.has(staffID)) {
            console.log(`[STAFF ON APPROVED LEAVE] Staff ${staffID} (${data.fullName || "Staff"}) is on approved leave on ${formatDateKey(parseLeaveDate(targetDate))} -> Excluded from task assignment.`);
            continue;
        }

        const staffNo = data.staffNo || doc.id;
        const maxTask = Number(data.maxTask || WORKING_HOUR_CONFIG.defaultMaxTasks);

        let workBaseLocation = COMPANY_LOCATION;
        let staffState = data.state || "Penang";

        if (data.workLocation && data.workLocation.lat && data.workLocation.lng) {
            workBaseLocation = { lat: Number(data.workLocation.lat), lng: Number(data.workLocation.lng) };
            if (data.workLocation.address) {
                const parts = data.workLocation.address.split(",").map(p => p.trim());
                if (parts.length > 0) staffState = parts[parts.length - 1];
            }
        } else if (data.currentLat && data.currentLng) {
            workBaseLocation = { lat: Number(data.currentLat), lng: Number(data.currentLng) };
        }

        staffList.push({
            staffID,
            staffNo,
            fullName: data.fullName || "Delivery Staff",
            phoneNumber: data.phoneNumber || "",
            email: data.email || "",
            position: data.position,
            maxTask,
            staffState,
            workBaseLocation
        });
    }

    return staffList;
}

/**
 * Task Assignment Algorithm:
 *
 * Route Sequence Model:
 *   - Task Count = 0: Staff Location -> ReByte Central Hub -> Task 1 (starts at slot, e.g. 09:00 AM)
 *   - Task Count > 0: Follows chained route sequence:
 *       Staff Location -> ReByte -> Task 1 -> Task 2 ...
 *       Travel from previous task destination (Task 1) -> customer destination (Task 2)
 *       Evaluates whether travel duration + buffer allows Task 2 to be completed on time:
 *         e.g., Task 1 completes at 09:34. Task 1 -> Task 2 takes 1 hour (arrives 10:34) -> valid because <= 11:00 AM slot.
 *         If travel takes 2 hours (arrives 11:34) -> invalid because > 11:00 AM slot.
 */
async function assignDeliveryTask({ orderID, addressID, requestedDate, specificStaffID, excludeStaffIDs = [], forceNextDay = false }) {
    const taskID = `TSK-${orderID}`;
    const deliveryID = `DEL-${orderID}`;

    const excludeSet = new Set((Array.isArray(excludeStaffIDs) ? excludeStaffIDs : [excludeStaffIDs]).filter(Boolean));

    let effectiveAddressID = addressID;
    if (!effectiveAddressID && orderID) {
        const ordDoc = await db.collection("order").doc(orderID).get();
        if (ordDoc.exists && ordDoc.data().addressID) {
            effectiveAddressID = ordDoc.data().addressID;
        }
    }

    const customerDetails = await resolveCustomerDetails(effectiveAddressID);
    const customerLocation = customerDetails.location;
    const customerState = (customerDetails.state || "Penang").trim();
    const companyLocation = COMPANY_LOCATION;

    const deliveryDocRef = db.collection("delivery").doc(deliveryID);
    await deliveryDocRef.set({
        deliveryID,
        orderID,
        taskID,
        destinationLat: customerLocation.lat,
        destinationLng: customerLocation.lng,
        deliveryStatus: "ongoing",
        proofOfDeliveryUrl: null
    }, { merge: true });

    // Check if task already exists and has an existing schedule (for address update / re-optimization)
    const taskDocRef = db.collection("task").doc(taskID);
    const existingTaskSnap = await taskDocRef.get();
    let existingScheduleID = null;
    if (existingTaskSnap.exists && existingTaskSnap.data().scheduleID) {
        existingScheduleID = existingTaskSnap.data().scheduleID;
    }

    const matchedScheduleIDs = new Set();
    if (existingScheduleID) matchedScheduleIDs.add(existingScheduleID);

    const sSnap = await db.collection("schedule").get();
    for (const sDoc of sSnap.docs) {
        if (sDoc.id.startsWith(`SCH-${orderID}`)) {
            matchedScheduleIDs.add(sDoc.id);
            if (!existingScheduleID) existingScheduleID = sDoc.id;
        }
    }

    const processLogs = [];
    function logStep(msg) {
        console.log(msg);
        processLogs.push(msg);
    }

    logStep(`\n================================================================================`);
    logStep(`[TASK ASSIGNMENT STARTED] Order: ${orderID} | Task: ${taskID}`);
    logStep(`Central Hub Location: ${companyLocation.lat}, ${companyLocation.lng}`);
    logStep(`Customer Destination: ${customerLocation.lat}, ${customerLocation.lng} (State: ${customerState})`);
    logStep(`Working Hours Config: ${WORKING_HOUR_CONFIG.startHour}:00 - ${WORKING_HOUR_CONFIG.endHour}:00 (Step: +${WORKING_HOUR_CONFIG.slotIntervalHours} hr, Buffer: ${WORKING_HOUR_CONFIG.bufferMinutes} min)`);
    logStep(`================================================================================\n`);

    const realNow = getMalaysiaNow();
    let candidateDate;

    if (requestedDate) {
        const parsedReq = parseLeaveDate(requestedDate) || new Date(requestedDate);
        candidateDate = new Date(parsedReq.getFullYear(), parsedReq.getMonth(), parsedReq.getDate(), 0, 0, 0);

        const realTodayMidnight = new Date(realNow.getFullYear(), realNow.getMonth(), realNow.getDate(), 0, 0, 0);

        if (forceNextDay) {
            candidateDate.setDate(candidateDate.getDate() + 1);
        } else if (candidateDate.getTime() === realTodayMidnight.getTime()) {
            // Task is requested for TODAY: check if today's 9:00 AM cutoff has already passed
            const today9am = new Date(realNow.getFullYear(), realNow.getMonth(), realNow.getDate(), WORKING_HOUR_CONFIG.startHour, 0, 0);
            if (realNow >= today9am) {
                // Today 9:00 AM already passed -> schedule for tomorrow
                candidateDate.setDate(candidateDate.getDate() + 1);
            }
        } else if (candidateDate.getTime() < realTodayMidnight.getTime()) {
            // Requested date is in the past -> move to today or tomorrow
            candidateDate = new Date(realTodayMidnight);
            const today9am = new Date(realNow.getFullYear(), realNow.getMonth(), realNow.getDate(), WORKING_HOUR_CONFIG.startHour, 0, 0);
            if (realNow >= today9am) {
                candidateDate.setDate(candidateDate.getDate() + 1);
            }
        }
        // Future date (e.g. 24 on leave, reassigned before 24 9am):
        // 9:00 AM on that future day hasn't arrived -> candidateDate stays on that future date!
    } else {
        // Default (new task without explicit requestedDate): today if before 9am, else tomorrow
        candidateDate = new Date(realNow.getFullYear(), realNow.getMonth(), realNow.getDate(), 0, 0, 0);
        const today9am = new Date(realNow.getFullYear(), realNow.getMonth(), realNow.getDate(), WORKING_HOUR_CONFIG.startHour, 0, 0);
        if (forceNextDay || realNow >= today9am) {
            candidateDate.setDate(candidateDate.getDate() + 1);
        }
    }

    let candidateHour = WORKING_HOUR_CONFIG.startHour; // 9:00 AM
    let suitableStaffFound = false;
    let selectedAssignment = null;

    // Requirement: Stop assigning after 3 days if no person can be assigned
    const maxDaysToSearch = 3;
    let daysSearched = 0;

    const hubToCustomerRoute = await getOsrmRoute(companyLocation, customerLocation);
    logStep(`[OSRM Central Hub -> Customer] Distance: ${hubToCustomerRoute.distanceKm} km | Duration: ${hubToCustomerRoute.durationMinutes} mins`);

    while (!suitableStaffFound && daysSearched < maxDaysToSearch) {
        // Constraint: 12:00 PM to 1:00 PM is Lunch Break (Unassigned)
        if (candidateHour >= WORKING_HOUR_CONFIG.lunchStartHour && candidateHour < WORKING_HOUR_CONFIG.lunchEndHour) {
            logStep(`\n[LUNCH BREAK] ${String(candidateHour).padStart(2, "0")}:00 - ${String(candidateHour + 1).padStart(2, "0")}:00 is staff lunch hour -> Skipping to 13:00.`);
            candidateHour = WORKING_HOUR_CONFIG.lunchEndHour; // Skip directly to 1:00 PM
        }

        const dateStr = formatDateKey(candidateDate);
        const slotStart = new Date(candidateDate.getFullYear(), candidateDate.getMonth(), candidateDate.getDate(), candidateHour, 0, 0);
        const slotEnd = new Date(candidateDate.getFullYear(), candidateDate.getMonth(), candidateDate.getDate(), candidateHour + WORKING_HOUR_CONFIG.slotIntervalHours, 0, 0);
        const slotTimeStr = `${dateStr} ${String(candidateHour).padStart(2, "0")}:00`;

        logStep(`\n------------------------------------------------------------`);
        logStep(`[EVALUATING SLOT] ${slotTimeStr} to ${String(candidateHour + WORKING_HOUR_CONFIG.slotIntervalHours).padStart(2, "0")}:00`);

        const allStaffRaw = await getEligibleDeliveryStaff(candidateDate);
        // Requirement: Limit staff cannot work outside the state
        let allStaff = allStaffRaw.filter(staff => {
            if (excludeSet.has(staff.staffID)) return false;
            const sState = (staff.staffState || "Penang").toLowerCase().trim();
            const cState = customerState.toLowerCase().trim();
            return sState.includes(cState) || cState.includes(sState);
        });

        // If a specific staff was chosen by admin, target this staff
        if (specificStaffID && specificStaffID !== "auto") {
            const matchingStaff = allStaffRaw.filter(s => s.staffID === specificStaffID && !excludeSet.has(s.staffID));
            if (matchingStaff.length > 0) {
                allStaff = matchingStaff;
            }
        }

        if (allStaff.length === 0) {
            logStep(`[STATE MISMATCH] No delivery staff operate in customer state: '${customerState}'. Staff cannot work outside their state.`);
        }

        const staffWithDayTasks = [];
        for (const staff of allStaff) {
            const schedSnap = await db.collection("schedule")
                .where("staffID", "==", staff.staffID)
                .where("scheduleDate", "==", dateStr)
                .where("scheduleStatus", "in", ["assigned", "ongoing"])
                .get();

            const existingTasks = [];
            for (const sDoc of schedSnap.docs) {
                // If this schedule is the existing schedule of the order being re-assigned, exclude it so it doesn't conflict
                if (sDoc.id === existingScheduleID || sDoc.id.startsWith(`SCH-${orderID}`)) {
                    continue;
                }
                const sData = sDoc.data();
                const sStart = parseScheduleDate(sData.scheduleStartTime, dateStr);
                const sEnd = parseScheduleDate(sData.scheduleEndTime, dateStr);

                let dest = COMPANY_LOCATION;
                const taskSnap = await db.collection("task").where("scheduleID", "==", sDoc.id).limit(1).get();
                let taskDocID = null;
                let orderIdForTask = sData.orderID || null;
                if (!taskSnap.empty) {
                    const tData = taskSnap.docs[0].data();
                    taskDocID = taskSnap.docs[0].id;
                    if (tData.orderID) {
                        orderIdForTask = tData.orderID;
                    }
                }

                if (orderIdForTask) {
                    const ordDoc = await db.collection("order").doc(orderIdForTask).get();
                    if (ordDoc.exists && ordDoc.data().addressID) {
                        const addrRes = await resolveCustomerDetails(ordDoc.data().addressID);
                        if (addrRes && addrRes.location) {
                            dest = addrRes.location;
                        }
                    }
                    if (dest === COMPANY_LOCATION) {
                        const dSnap = await db.collection("delivery").doc(`DEL-${orderIdForTask}`).get();
                        if (dSnap.exists && dSnap.data().destinationLat) {
                            dest = { lat: Number(dSnap.data().destinationLat), lng: Number(dSnap.data().destinationLng) };
                        }
                    }
                }

                existingTasks.push({
                    scheduleID: sDoc.id,
                    taskID: taskDocID,
                    startTime: sStart,
                    endTime: sEnd,
                    location: dest
                });
            }

            existingTasks.sort((a, b) => (a.startTime && b.startTime ? a.startTime - b.startTime : 0));

            // Q2: Skip staff in slots before their actual availability
            // If staff has 0 tasks: they are available from 9:00 AM (candidate slot 09:00).
            // If staff has existing tasks: find their latest task completion time today.
            // If their latest task ends at or after slotEnd (e.g. ends at 12:29 PM, but candidate slot is 09:00 - 10:00),
            // skip evaluating them in this morning slot. They will be evaluated in the slot when they actually become free!
            if (existingTasks.length > 0) {
                const latestEndTime = existingTasks.reduce((max, t) => t.endTime > max ? t.endTime : max, existingTasks[0].endTime);
                if (latestEndTime >= slotEnd) {
                    // Staff is still committed to earlier tasks until latestEndTime
                    continue;
                }
            }

            // Constraint 1: Maximum 8 deliveries per person per day
            const maxAllowed = Math.min(staff.maxTask || WORKING_HOUR_CONFIG.maxDeliveriesPerDay, WORKING_HOUR_CONFIG.maxDeliveriesPerDay);
            if (existingTasks.length >= maxAllowed) {
                // Staff reached daily delivery limit
                continue;
            }

            staffWithDayTasks.push({
                staff,
                taskCount: existingTasks.length,
                existingTasks
            });
        }

        logStep(`Available non-occupied staff for ${slotTimeStr}: ${staffWithDayTasks.length} staff member(s)`);

        const countGroupsMap = new Map();
        for (const item of staffWithDayTasks) {
            const count = item.taskCount;
            if (!countGroupsMap.has(count)) {
                countGroupsMap.set(count, []);
            }
            countGroupsMap.get(count).push(item);
        }

        const sortedCounts = Array.from(countGroupsMap.keys()).sort((a, b) => a - b);

        for (const count of sortedCounts) {
            const group = countGroupsMap.get(count);
            logStep(`\n[CHECKING WORKLOAD GROUP] Task Count = ${count} (${group.length} staff)`);
            const feasibleStaffList = [];

            if (count === 0) {
                // Route: Staff Location -> ReByte Central Hub -> Task 1
                for (const item of group) {
                    const staff = item.staff;
                    const staffToHub = await getOsrmRoute(staff.workBaseLocation, companyLocation);

                    // Staff leaves home at slotStart (e.g. 09:00), reaches ReByte Central Hub at departFromHubTime (e.g. 09:16)
                    const departFromHubTime = new Date(slotStart.getTime() + (staffToHub.durationMinutes * 60 * 1000));

                    // Task leg: ReByte Central Hub -> Customer
                    const appliedBuffer = getBufferMinutes(hubToCustomerRoute.distanceKm);
                    const taskDuration = hubToCustomerRoute.durationMinutes + appliedBuffer;
                    const taskDistance = hubToCustomerRoute.distanceKm;

                    const taskStartTime = departFromHubTime;
                    const taskEndTime = new Date(taskStartTime.getTime() + (taskDuration * 60 * 1000));

                    const overallRouteDuration = staffToHub.durationMinutes + taskDuration;
                    const overallRouteDistance = Number((staffToHub.distanceKm + taskDistance).toFixed(2));

                    const endOfWorkday = new Date(slotStart.getFullYear(), slotStart.getMonth(), slotStart.getDate(), WORKING_HOUR_CONFIG.endHour, 0, 0);
                    if (taskEndTime <= endOfWorkday) {
                        feasibleStaffList.push({
                            staff,
                            taskStartTime,
                            taskEndTime,
                            totalDuration: taskDuration,
                            totalDistance: taskDistance,
                            overallRouteDuration,
                            overallRouteDistance,
                            slotStart
                        });
                        logStep(`   Staff [${staff.staffNo}] ${staff.fullName}:`);
                        logStep(`      Sequence: Location -> ReByte (arrives ${formatTimeOnly(departFromHubTime)}) -> New Task (${orderID})`);
                        logStep(`      Status: VALID -> Task Window: ${formatTimeOnly(taskStartTime)} - ${formatTimeOnly(taskEndTime)} (Task Dur: ${taskDuration}m, Dist: ${taskDistance}km) | Overall Route: ${overallRouteDuration}m, ${overallRouteDistance}km`);
                    } else {
                        logStep(`   Staff [${staff.staffNo}] ${staff.fullName}:`);
                        logStep(`      Sequence: Location -> ReByte -> New Task (${orderID})`);
                        logStep(`      Status: INVALID -> Exceeds 5:00 PM working hours (arrives ${formatTimeOnly(taskEndTime)})`);
                    }
                }
            } else {
                // Task Count > 0: Generate all possible task sequence permutations
                // by inserting the New Task into every possible position among existing tasks:
                // Pos 0: Hub -> New Task -> Task 1 -> Task 2 ...
                // Pos 1: Hub -> Task 1 -> New Task -> Task 2 ...
                // Pos N: Hub -> Task 1 -> Task 2 -> ... -> New Task
                for (const item of group) {
                    const staff = item.staff;
                    const existingTasks = item.existingTasks;
                    const validRoutes = [];

                    // Find the latest task end time scheduled for this staff today (e.g. if Task A ends at 10:00 and Task B ends at 11:00, show 11:00)
                    let latestTaskEndTimeStr = "None (No tasks scheduled today)";
                    if (existingTasks.length > 0) {
                        const sortedByEndTime = [...existingTasks].sort((a, b) => b.endTime - a.endTime);
                        const latestTask = sortedByEndTime[0];
                        const latestTaskId = latestTask.orderID || (latestTask.scheduleID ? latestTask.scheduleID.slice(-8) : "Task");
                        latestTaskEndTimeStr = `${formatTimeOnly(latestTask.endTime)} (from ${latestTaskId})`;
                    }

                    logStep(`   Evaluating Staff [${staff.staffNo}] ${staff.fullName} (Existing tasks: ${existingTasks.length}):`);
                    logStep(`      Latest Task End Time Today: ${latestTaskEndTimeStr}`);

                    // Try inserting new task at each possible position: 0 to existingTasks.length
                    for (let insertIdx = 0; insertIdx <= existingTasks.length; insertIdx++) {
                        const candidateSeq = [
                            ...existingTasks.slice(0, insertIdx).map(t => ({ ...t, isNew: false })),
                            { isNew: true, location: customerLocation, orderID, taskID },
                            ...existingTasks.slice(insertIdx).map(t => ({ ...t, isNew: false }))
                        ];

                        // Simulate departure timeline starting from 9:00 AM working opening
                        // Leg 0: Staff Base Location -> ReByte Central Hub
                        const staffToHub = await getOsrmRoute(staff.workBaseLocation, companyLocation);
                        let currentTime = new Date(candidateDate.getFullYear(), candidateDate.getMonth(), candidateDate.getDate(), WORKING_HOUR_CONFIG.startHour, 0, 0);
                        currentTime = new Date(currentTime.getTime() + (staffToHub.durationMinutes * 60 * 1000));

                        let currentLoc = companyLocation;
                        let seqTotalDistance = staffToHub.distanceKm;
                        let seqTotalDuration = staffToHub.durationMinutes;
                        let isValidSequence = true;
                        let newTaskStartTime = null;
                        let newTaskEndTime = null;
                        let newTaskDist = 0;
                        let newTaskDur = 0;
                        const stopTimings = [];

                        for (let stopIdx = 0; stopIdx < candidateSeq.length; stopIdx++) {
                            const stop = candidateSeq[stopIdx];

                            // Option B: If currentTime is already inside the 12:00 - 13:00 window (without an active delivery),
                            // staff takes lunch until 13:00 before departing on the next task:
                            const lunchStart = new Date(candidateDate.getFullYear(), candidateDate.getMonth(), candidateDate.getDate(), WORKING_HOUR_CONFIG.lunchStartHour, 0, 0);
                            const lunchEnd = new Date(candidateDate.getFullYear(), candidateDate.getMonth(), candidateDate.getDate(), WORKING_HOUR_CONFIG.lunchEndHour, 0, 0);
                            if (currentTime >= lunchStart && currentTime < lunchEnd) {
                                currentTime = new Date(lunchEnd);
                            }

                            const leg = await getOsrmRoute(currentLoc, stop.location);
                            const appliedBuffer = getBufferMinutes(leg.distanceKm);
                            const legTravelMinutes = leg.durationMinutes + appliedBuffer;

                            const stopStart = new Date(currentTime);
                            const arrivalTime = new Date(stopStart.getTime() + (legTravelMinutes * 60 * 1000));
                            const stopEnd = new Date(arrivalTime);

                            seqTotalDistance += leg.distanceKm;
                            seqTotalDuration += legTravelMinutes;

                            if (stop.isNew) {
                                newTaskStartTime = stopStart;
                                newTaskEndTime = stopEnd;
                                newTaskDist = leg.distanceKm;
                                newTaskDur = legTravelMinutes;
                            }

                            // Rule 1: Exceeding daily working hours (5:00 PM) makes route invalid
                            const endOfWorkday = new Date(candidateDate.getFullYear(), candidateDate.getMonth(), candidateDate.getDate(), WORKING_HOUR_CONFIG.endHour, 0, 0);
                            if (stopEnd > endOfWorkday) {
                                isValidSequence = false;
                                break;
                            }

                            stopTimings.push({
                                ...stop,
                                startTime: stopStart,
                                endTime: stopEnd
                            });

                            // Under Option B: If delivery finishes between 12:00 and 13:00, staff takes 1 hour lunch break from arrival time:
                            if (stopEnd >= lunchStart && stopEnd < lunchEnd) {
                                currentTime = new Date(stopEnd.getTime() + (60 * 60 * 1000)); // 1 hour lunch from arrival time
                            } else {
                                currentTime = stopEnd;
                            }
                            currentLoc = stop.location;
                        }

                        const stopLabels = candidateSeq.map((s, idx) => {
                            if (s.isNew) {
                                return `New Task (${orderID})`;
                            }
                            const idLabel = s.orderID || (s.scheduleID ? s.scheduleID.slice(-8) : `Task #${idx + 1}`);
                            return `Task (${idLabel})`;
                        });
                        const seqName = `Location -> ReByte -> ${stopLabels.join(" -> ")}`;

                        if (isValidSequence) {
                            validRoutes.push({
                                insertIdx,
                                sequenceName: seqName,
                                totalDistance: Number(seqTotalDistance.toFixed(2)),
                                totalDuration: seqTotalDuration,
                                newTaskStartTime,
                                newTaskEndTime,
                                newTaskDist,
                                newTaskDur,
                                stopTimings
                            });
                            logStep(`      Permutation #${insertIdx + 1}: ${seqName}`);
                            logStep(`         Status: VALID -> Total Duration: ${seqTotalDuration}m, Total Distance: ${seqTotalDistance.toFixed(1)}km, New Task Window: ${formatTimeOnly(newTaskStartTime)} - ${formatTimeOnly(newTaskEndTime)}`);
                        } else {
                            logStep(`      Permutation #${insertIdx + 1}: ${seqName}`);
                            logStep(`         Status: INVALID -> Exceeds 5:00 PM working hours`);
                        }
                    }

                    if (validRoutes.length > 0) {
                        // Select best permutation for this staff:
                        // 1. Shortest total duration
                        // 2. Shortest total distance
                        // 3. Tie-breaker: prefer higher insertIdx (new task at the end/latest position so existing tasks are not delayed)
                        validRoutes.sort((a, b) => {
                            if (a.totalDuration !== b.totalDuration) return a.totalDuration - b.totalDuration;
                            if (a.totalDistance !== b.totalDistance) return a.totalDistance - b.totalDistance;
                            return b.insertIdx - a.insertIdx; // Prefer appending as last task
                        });
                        const bestRoute = validRoutes[0];

                        feasibleStaffList.push({
                            staff,
                            taskStartTime: bestRoute.newTaskStartTime,
                            taskEndTime: bestRoute.newTaskEndTime,
                            totalDuration: bestRoute.newTaskDur,
                            totalDistance: bestRoute.newTaskDist,
                            overallRouteDuration: bestRoute.totalDuration,
                            overallRouteDistance: bestRoute.totalDistance,
                            bestRoute,
                            slotStart
                        });
                        logStep(`      => BEST ROUTE for [${staff.fullName}]: Permutation #${bestRoute.insertIdx + 1} (${bestRoute.sequenceName})`);
                    } else {
                        logStep(`      => No valid sequence permutations without exceeding working hours`);
                    }
                }
            }

            if (feasibleStaffList.length > 0) {
                // Rank staff in this workload group:
                // 1. Shortest total overall route duration
                // 2. Shortest total overall route distance
                // 3. Earliest arrival at new task
                feasibleStaffList.sort((a, b) => {
                    if (a.overallRouteDuration !== b.overallRouteDuration) return a.overallRouteDuration - b.overallRouteDuration;
                    if (a.overallRouteDistance !== b.overallRouteDistance) return a.overallRouteDistance - b.overallRouteDistance;
                    return a.taskEndTime - b.taskEndTime;
                });

                selectedAssignment = feasibleStaffList[0];
                suitableStaffFound = true;
                logStep(`   [SUCCESS] BEST SUITABLE STAFF SELECTED: [${selectedAssignment.staff.staffNo}] ${selectedAssignment.staff.fullName}`);
                logStep(`   Assigned Slot: ${formatTimeOnly(selectedAssignment.taskStartTime)} - ${formatTimeOnly(selectedAssignment.taskEndTime)} | Overall Route: ${selectedAssignment.overallRouteDuration} mins, ${selectedAssignment.overallRouteDistance} km`);

                // If bestRoute rearranged existing tasks, update their schedules to keep timeline synchronized
                if (selectedAssignment.bestRoute && selectedAssignment.bestRoute.stopTimings) {
                    for (const stop of selectedAssignment.bestRoute.stopTimings) {
                        if (!stop.isNew && stop.scheduleID) {
                            await db.collection("schedule").doc(stop.scheduleID).update({
                                scheduleStartTime: formatTimeOnly(stop.startTime),
                                scheduleEndTime: formatTimeOnly(stop.endTime)
                            }).catch(() => {});
                            if (stop.taskID) {
                                await db.collection("task").doc(stop.taskID).update({
                                    taskStartTime: formatTimeOnly(stop.startTime)
                                }).catch(() => {});
                            } else {
                                await db.collection("task").doc(`TSK-${stop.scheduleID.replace(/^SCH-/, "").replace(/-\d+$/, "")}`).update({
                                    taskStartTime: formatTimeOnly(stop.startTime)
                                }).catch(() => {});
                            }
                        }
                    }
                }
                break;
            }
        }

        if (suitableStaffFound) {
            break;
        }

        candidateHour += WORKING_HOUR_CONFIG.slotIntervalHours;
        if (candidateHour >= WORKING_HOUR_CONFIG.endHour) {
            candidateDate.setDate(candidateDate.getDate() + 1);
            candidateHour = WORKING_HOUR_CONFIG.startHour;
            daysSearched++;
        }
    }

    if (!suitableStaffFound || !selectedAssignment) {
        logStep(`\n[ASSIGNMENT FAILED] No staff available within the 3-day search window (or staff cannot work outside state).`);
        logStep(`[STATUS UPDATE] Task [${taskID}] marked as 'Unassigned'.`);

        // If old schedule(s) existed, mark non-rejected/non-absent schedules as 'reassigned'
        for (const sId of matchedScheduleIDs) {
            const sDoc = await db.collection("schedule").doc(sId).get();
            if (sDoc.exists && (sDoc.data().scheduleStatus === "rejected" || sDoc.data().scheduleStatus === "absent")) {
                continue; // Preserve rejected and absent schedules
            }
            logStep(`[SCHEDULE REASSIGNED] Marking schedule document [${sId}] as 'reassigned' because order is Unassigned.`);
            await db.collection("schedule").doc(sId).update({
                scheduleStatus: "reassigned",
                reassignedAt: new Date(),
                updatedAt: new Date()
            }).catch((err) => {
                console.error(`Failed to update schedule ${sId}:`, err);
            });
        }

        // Requirement: Make task and order status as 'Unassigned'
        await db.collection("task").doc(taskID).set({
            taskID,
            taskType: "deliver",
            taskStatus: "Unassigned",
            scheduleID: null,
            taskStartTime: null,
            estimatedDistance: null,
            estimatedDuration: null,
            orderID,
            updatedAt: new Date()
        }, { merge: true });

        if (orderID) {
            await db.collection("order").doc(orderID).set({
                orderStatus: "Unassigned",
                updatedAt: new Date()
            }, { merge: true });
        }

        await db.collection("delivery").doc(deliveryID).set({
            deliveryStatus: "unassigned",
            updatedAt: new Date()
        }, { merge: true });

        return { 
            success: false, 
            taskStatus: "Unassigned",
            reason: `No eligible staff available in ${customerState} within 3-day search window`, 
            processLogs 
        };
    }

    const selectedStaff = selectedAssignment.staff;
    const finalDateStr = formatDateKey(selectedAssignment.slotStart);
    // Create brand new schedule record so any older schedule remains rejected
    const newScheduleID = `SCH-${orderID}-${Date.now().toString().slice(-4)}`;
    const scheduleStartTime = selectedAssignment.taskStartTime;
    const scheduleEndTime = selectedAssignment.taskEndTime;

    const startTimeStr = formatTimeOnly(scheduleStartTime);
    const endTimeStr = formatTimeOnly(scheduleEndTime);

    // Mark previous active/assigned schedule(s) for this order as 'reassigned' (DO NOT delete)
    for (const sId of matchedScheduleIDs) {
        if (sId === newScheduleID) continue;
        const sDoc = await db.collection("schedule").doc(sId).get();
        if (sDoc.exists && sDoc.data().scheduleStatus !== "rejected" && sDoc.data().scheduleStatus !== "absent") {
            logStep(`[OLD SCHEDULE REASSIGNED] Marking superseded schedule [${sId}] for previous staff [${sDoc.data().staffID}] as 'reassigned'.`);
            await db.collection("schedule").doc(sId).update({
                scheduleStatus: "reassigned",
                reassignedAt: new Date(),
                updatedAt: new Date()
            }).catch((err) => {
                console.error(`Failed to update superseded schedule ${sId}:`, err);
            });
        }
    }

    const prevOrderScheds = await db.collection("schedule").where("orderID", "==", orderID).get();
    for (const sDoc of prevOrderScheds.docs) {
        if (sDoc.id === newScheduleID) continue;
        if (sDoc.data().scheduleStatus !== "rejected" && sDoc.data().scheduleStatus !== "absent") {
            logStep(`[OLD SCHEDULE REASSIGNED] Marking superseded schedule [${sDoc.id}] for previous staff [${sDoc.data().staffID}] as 'reassigned'.`);
            await sDoc.ref.update({
                scheduleStatus: "reassigned",
                reassignedAt: new Date(),
                updatedAt: new Date()
            }).catch(() => {});
        }
    }

    // Save Schedule (new schedule record with status 'assigned')
    await db.collection("schedule").doc(newScheduleID).set({
        scheduleID: newScheduleID,
        orderID,
        staffID: selectedStaff.staffID,
        scheduleDate: finalDateStr,
        scheduleStartTime: startTimeStr,
        scheduleEndTime: endTimeStr,
        scheduleStatus: "assigned",
        updatedAt: new Date()
    }, { merge: true });

    // Save Task (references newScheduleID, status 'Packaging')
    await db.collection("task").doc(taskID).set({
        taskID,
        taskType: "deliver",
        taskStatus: "Packaging",
        taskStartTime: startTimeStr,
        estimatedDistance: selectedAssignment.totalDistance,
        estimatedDuration: selectedAssignment.totalDuration,
        scheduleID: newScheduleID,
        staffID: selectedStaff.staffID,
        staffName: FieldValue.delete(),
        orderID,
        rejectionReason: FieldValue.delete(),
        rejectionNotes: FieldValue.delete(),
        staffLat: FieldValue.delete(),
        staffLng: FieldValue.delete(),
        staffHeading: FieldValue.delete(),
        lastGpsUpdate: FieldValue.delete(),
        onHoldReason: FieldValue.delete(),
        onHoldAt: FieldValue.delete(),
        holdReason: FieldValue.delete(),
        reassignedAt: FieldValue.delete(),
        reassignReason: FieldValue.delete(),
        updatedAt: new Date()
    }, { merge: true });

    // Save Delivery (status 'ongoing', no GPS fields)
    await db.collection("delivery").doc(deliveryID).set({
        deliveryID,
        orderID,
        taskID,
        destinationLat: customerLocation.lat,
        destinationLng: customerLocation.lng,
        deliveryStatus: "ongoing",
        proofOfDeliveryUrl: null,
        staffLat: FieldValue.delete(),
        staffLng: FieldValue.delete(),
        staffHeading: FieldValue.delete(),
        lastGpsUpdate: FieldValue.delete(),
        updatedAt: new Date()
    }, { merge: true });

    // Ensure order is at Delivering
    if (orderID) {
        await db.collection("order").doc(orderID).set({
            orderStatus: "Delivering",
            updatedAt: new Date()
        }, { merge: true });
    }

    return {
        success: true,
        message: `Order #${orderID} successfully reassigned to ${selectedStaff.fullName}.`,
        orderID,
        taskID,
        deliveryID,
        scheduleID: newScheduleID,
        staffID: selectedStaff.staffID,
        staffName: selectedStaff.fullName,
        scheduleDate: finalDateStr,
        scheduleStartTime: startTimeStr,
        scheduleEndTime: endTimeStr,
        estimatedDuration: `${selectedAssignment.totalDuration} mins`,
        estimatedDistance: `${selectedAssignment.totalDistance} km`,
        processLogs
    };
}

/**
 * When a staff member's position changes from Deliverer to another role,
/**
 * When a staff member changes role (e.g. Inspector / Inspector & Collector to Deliverer)
 * or is Archived, check their holding ongoing/assigned tasks and reassign any tasks they can no longer perform.
 * - Delivery tasks reassign to another Deliverer
 * - Inspect tasks reassign to another Inspector or Inspector & Collector
 * - Collect tasks reassign strictly to another Inspector & Collector
 * If no replacement staff is available for a trade-in task, the appointment is marked 'On Hold' and an email is sent.
 */
async function reassignStaffTasksOnRoleChange(staffID, oldPosition, newPosition) {
    try {
        console.log(`[ROLE CHANGE REASSIGN] Checking tasks for staff ${staffID} whose role changed from '${oldPosition}' to '${newPosition}'...`);

        const normNew = String(newPosition || "").toLowerCase().trim();
        const isArchived = normNew === "archived" || normNew === "inactive";

        // Get staffDoc to check staffNo as well
        let staffNo = null;
        try {
            const uDoc = await db.collection("users").doc(staffID).get();
            if (uDoc.exists) {
                staffNo = uDoc.data().staffNo;
            }
        } catch (_) {}

        const queryIds = [staffID];
        if (staffNo && staffNo !== staffID) queryIds.push(staffNo);

        const activeSchedules = new Map();
        for (const sid of queryIds) {
            const snap = await db.collection("schedule")
                .where("staffID", "==", sid)
                .where("scheduleStatus", "in", ["assigned", "ongoing"])
                .get();

            for (const doc of snap.docs) {
                activeSchedules.set(doc.id, doc);
            }
        }

        if (activeSchedules.size === 0) {
            console.log(`[ROLE CHANGE REASSIGN] No active tasks found for staff ${staffID}.`);
            return { reassignedCount: 0 };
        }

        console.log(`[ROLE CHANGE REASSIGN] Found ${activeSchedules.size} active task(s) for staff ${staffID}. Evaluating role eligibility...`);

        let totalReassigned = 0;
        let delayService = null;
        try {
            delayService = require("./taskDelayMonitorService");
        } catch (_) {}

        for (const [scheduleID, sDoc] of activeSchedules.entries()) {
            const sData = sDoc.data();
            const schedDate = sData.scheduleDate;

            // Fetch corresponding task to accurately identify task type
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

            // Determine if the staff can still perform this task under their new position
            let taskNeedsReassign = false;
            if (isArchived) {
                taskNeedsReassign = true;
            } else if (isDelivery) {
                taskNeedsReassign = !normNew.includes("deliver");
            } else if (isTradeIn) {
                if (taskType === "collect") {
                    // Collection requires Inspector & Collector ONLY
                    taskNeedsReassign = !(normNew.includes("collector") && normNew.includes("inspector"));
                } else {
                    // Inspection allows Inspector or Inspector & Collector
                    taskNeedsReassign = !normNew.includes("inspector");
                }
            }

            if (!taskNeedsReassign) {
                console.log(`[ROLE CHANGE REASSIGN] Staff ${staffID} can still perform ${taskType || "task"} under role '${newPosition}'. Keeping schedule ${scheduleID}.`);
                continue;
            }

            // Mark old schedule as reassigned due to role change
            await sDoc.ref.set({
                scheduleStatus: "reassigned",
                reassignReason: `Staff role changed from ${oldPosition || "Staff"} to ${newPosition}`,
                reassignedAt: new Date().toISOString(),
                updatedAt: new Date().toISOString()
            }, { merge: true });

            if (delayService && typeof delayService.clearScheduleTimers === "function") {
                try {
                    delayService.clearScheduleTimers(scheduleID);
                } catch (_) {}
            }

            if (isDelivery && orderID) {
                // Reassign delivery task to available delivery staff
                const reassignResult = await assignDeliveryTask({
                    orderID,
                    addressID: sData.addressID,
                    requestedDate: schedDate,
                    forceNextDay: false, // Try same day first with other eligible deliverers
                    excludeStaffIDs: queryIds
                });

                if (reassignResult && reassignResult.success) {
                    if (reassignResult.scheduleID && delayService && typeof delayService.registerScheduleTimer === "function") {
                        try {
                            delayService.registerScheduleTimer(reassignResult.scheduleID);
                        } catch (_) {}
                    }
                    totalReassigned++;
                    console.log(`[ROLE CHANGE REASSIGN SUCCESS] Delivery Order #${orderID} reassigned to ${reassignResult.staffName || reassignResult.staffID} on ${reassignResult.scheduleDate} (${reassignResult.scheduleStartTime})`);
                } else {
                    console.warn(`[ROLE CHANGE REASSIGN WARNING] Could not automatically reassign Delivery Order #${orderID}:`, reassignResult?.reason || reassignResult?.message);
                }
            } else if (isTradeIn) {
                // Reassign inspection / collection task to available inspector / collector
                const appointmentID = (taskData && taskData.appointmentID) || sData.appointmentID;
                let appData = {};
                if (appointmentID) {
                    const aDoc = await db.collection("tradeInAppointment").doc(appointmentID).get();
                    if (aDoc.exists) appData = aDoc.data();
                }

                const rawType = (appData.appointmentType || taskData?.taskType || "Inspect").toLowerCase();
                const method = rawType.includes("collect") ? "Doorstep Collection" : "On-Site Inspection";
                const tradeInRequestID = appData.tradeInRequestID || (taskData && taskData.tradeInRequestID) || null;
                const addressID = appData.addressID || sData.addressID || null;
                const appointmentTime = sData.scheduleStartTime || (taskData && taskData.taskStartTime) || "09:00 AM";

                const reassignResult = await assignTradeInTask({
                    tradeInRequestID,
                    method,
                    appointmentDate: schedDate,
                    appointmentTime,
                    addressID,
                    excludeStaffIDs: queryIds,
                    existingAppointmentID: appointmentID,
                    existingTaskID: taskID
                });

                if (reassignResult && reassignResult.success) {
                    totalReassigned++;
                    console.log(`[ROLE CHANGE REASSIGN SUCCESS] Trade-In ${method} Task reassigned to ${reassignResult.staffName || reassignResult.staffID} on ${reassignResult.scheduleDate} (${reassignResult.scheduleStartTime})`);
                } else {
                    console.warn(`[ROLE CHANGE REASSIGN WARNING] Could not automatically reassign Trade-In task ${appointmentID}:`, reassignResult?.message);
                    await handleFailedTradeInReassignment({
                        appointmentID,
                        tradeInRequestID,
                        scheduleID,
                        taskID,
                        appointmentDate: schedDate,
                        appointmentTime,
                        method,
                        reason: `Assigned staff role changed from ${oldPosition || "Staff"} to ${newPosition} and no replacement staff is currently available for this time slot.`
                    });
                }
            } else {
                console.log(`[ROLE CHANGE REASSIGN] Schedule ${scheduleID} is neither a delivery nor trade-in task. Skipping reassignment.`);
            }
        }

        return { reassignedCount: totalReassigned };
    } catch (err) {
        console.error(`[ROLE CHANGE REASSIGN ERROR] Failed reassigning tasks for staff ${staffID}:`, err);
        return { reassignedCount: 0, error: err.message };
    }
}

/**
 * Generate 14-character Appointment ID formatted as: YYMMDDAPPXXXXX
 * YY = 2-digit year (e.g. "26")
 * MM = 2-digit month (e.g. "10")
 * DD = 2-digit day of month (e.g. "24")
 * APP = literal "APP"
 * XXXXX = 5-digit sequential number (e.g. "00001", "00002")
 */
async function generateAppointmentID(dateObj = new Date()) {
    const yy = String(dateObj.getFullYear()).slice(-2);
    const mm = String(dateObj.getMonth() + 1).padStart(2, "0");
    const dd = String(dateObj.getDate()).padStart(2, "0");
    const prefix = `${yy}${mm}${dd}APP`;

    let nextSeq = 1;
    try {
        const snap = await db.collection("tradeInAppointment")
            .where("appointmentID", ">=", prefix)
            .where("appointmentID", "<=", prefix + "\uf8ff")
            .get();

        let maxSeq = 0;
        snap.forEach(doc => {
            const docId = doc.id || (doc.data() && doc.data().appointmentID);
            if (docId && docId.startsWith(prefix)) {
                const suffix = docId.slice(prefix.length);
                if (/^\d+$/.test(suffix)) {
                    const parsedNum = parseInt(suffix, 10);
                    if (!isNaN(parsedNum) && parsedNum > maxSeq) {
                        maxSeq = parsedNum;
                    }
                }
            }
        });
        nextSeq = maxSeq + 1;
    } catch (err) {
        console.warn("Could not query latest appointment sequence, defaulting to 1:", err.message);
    }

    const xxxxx = String(nextSeq).padStart(5, "0");
    return `${prefix}${xxxxx}`;
}

/**
 * Parse appointment slot time string into hours and minutes
 * e.g. "09:30 AM" -> { hours: 9, minutes: 30 }
 *      "01:30 PM" -> { hours: 13, minutes: 30 }
 *      "14:00"    -> { hours: 14, minutes: 0 }
 */
function parseSlotTimeToHoursMinutes(timeStr) {
    if (!timeStr) return { hours: 9, minutes: 30 };
    const clean = String(timeStr).trim().toUpperCase();
    const isPM = clean.includes("PM");
    const isAM = clean.includes("AM");
    const numeric = clean.replace(/[APM\s]/g, "");
    const parts = numeric.split(":");
    let hours = parseInt(parts[0], 10) || 0;
    const minutes = parseInt(parts[1], 10) || 0;
    if (isPM && hours < 12) hours += 12;
    if (isAM && hours === 12) hours = 0;
    return { hours, minutes };
}

/**
 * Helper to check if staff specialization matches target device brand or model
 */
function staffMatchesDeviceSpecialization(staffSpecializations, deviceBrand, deviceModel) {
    if (!staffSpecializations) return false;
    const specs = Array.isArray(staffSpecializations)
        ? staffSpecializations
        : String(staffSpecializations).split(/[|,]/);

    const normalizedSpecs = specs.map(s => String(s).trim().toLowerCase()).filter(Boolean);
    if (normalizedSpecs.length === 0) return false;

    const brandStr = String(deviceBrand || "").toLowerCase();
    const modelStr = String(deviceModel || "").toLowerCase();
    const combined = `${brandStr} ${modelStr}`.trim();

    for (const spec of normalizedSpecs) {
        if (spec.includes("apple") || spec.includes("iphone")) {
            if (combined.includes("apple") || combined.includes("iphone") || brandStr === "apple") {
                return true;
            }
        } else if (spec.includes("samsung") || spec.includes("galaxy")) {
            if (combined.includes("samsung") || combined.includes("galaxy") || brandStr === "samsung") {
                return true;
            }
        } else if (spec.includes("google") || spec.includes("pixel")) {
            if (combined.includes("google") || combined.includes("pixel") || brandStr.includes("google")) {
                return true;
            }
        } else if (spec.includes("xiaomi") || spec.includes("redmi") || spec.includes("poco")) {
            if (combined.includes("xiaomi") || combined.includes("redmi") || combined.includes("poco")) {
                return true;
            }
        } else {
            if (combined.includes(spec) || (spec.length > 2 && spec === brandStr)) {
                return true;
            }
        }
    }
    return false;
}

/**
 * Assign an Inspection or Collection appointment to the best available staff
 *
 * Rules:
 * For Inspection:
 *   1. Eligible staff: Role is 'inspector' or 'inspector & collector' and not taking approved leave.
 *   2. Filter who can make it on time:
 *      - If staff task == 0: 9:00 AM work location -> task new location (9:00 AM + duration <= customer selected time)
 *      - If staff task > 0: last task location -> new task location (last task end time + duration <= customer selected time)
 *   3. Filter by device specialization (e.g. if trade-in is iPhone, staff with iPhone/Apple specialization).
 *      - If filter results in zero staff, ignore this step.
 *   4. Filter shortest distance to task location -> select best staff.
 *
 * For Collection:
 *   1. Eligible staff: Role is 'inspector & collector' ONLY and not taking approved leave.
 *   2. Filter who can make it on time:
 *      - If staff task == 0: 9:00 AM work location -> task new location (9:00 AM + duration <= customer selected time)
 *      - If staff task > 0: last task location -> new task location (last task end time + duration <= customer selected time)
 *   3. Filter shortest distance to task location -> select best staff.
 *
 * Creates 3 records: tradeInAppointment, task, schedule
 */
async function assignTradeInTask({
    tradeInRequestID,
    method = "On-Site Inspection",
    appointmentDate,
    appointmentTime,
    address,
    addressID,
    excludeStaffIDs = [],
    existingAppointmentID = null,
    existingTaskID = null,
    forceNewRecords = false
}) {
    console.log(`\n================================================================================`);
    console.log(`[TRADE-IN TASK ASSIGNMENT] Request: ${tradeInRequestID || "(Existing: " + existingAppointmentID + ")"} | Method: ${method} | Date: ${appointmentDate} ${appointmentTime} | ForceNew: ${forceNewRecords}`);
    console.log(`================================================================================`);

    // Resolve existing appointment and task records (DO NOT create new ones when reassigning)
    let effectiveAddressID = addressID;
    let customerAddress = address;

    if (!existingAppointmentID && tradeInRequestID) {
        try {
            const reqDoc = await db.collection("tradeInRequests").doc(tradeInRequestID).get();
            if (reqDoc.exists && reqDoc.data().appointmentID) {
                existingAppointmentID = reqDoc.data().appointmentID;
            }
            if (!existingAppointmentID) {
                const exSnap = await db.collection("tradeInAppointment")
                    .where("tradeInRequestID", "==", tradeInRequestID)
                    .limit(1)
                    .get();
                if (!exSnap.empty) {
                    existingAppointmentID = exSnap.docs[0].id;
                }
            }
        } catch (_) {}
    }

    if (!existingTaskID) {
        try {
            if (existingAppointmentID) {
                const tSnap = await db.collection("task")
                    .where("appointmentID", "==", existingAppointmentID)
                    .limit(1)
                    .get();
                if (!tSnap.empty) {
                    existingTaskID = tSnap.docs[0].id;
                }
            }
            if (!existingTaskID && tradeInRequestID) {
                const tSnap = await db.collection("task")
                    .where("tradeInRequestID", "==", tradeInRequestID)
                    .limit(1)
                    .get();
                if (!tSnap.empty) {
                    existingTaskID = tSnap.docs[0].id;
                }
            }
        } catch (_) {}
    }

    if (existingAppointmentID && (!effectiveAddressID || !tradeInRequestID)) {
        try {
            const exAppDoc = await db.collection("tradeInAppointment").doc(existingAppointmentID).get();
            if (exAppDoc.exists) {
                const exData = exAppDoc.data();
                if (!effectiveAddressID && exData.addressID) effectiveAddressID = exData.addressID;
                if (!tradeInRequestID && exData.tradeInRequestID) tradeInRequestID = exData.tradeInRequestID;
                if (!customerAddress && exData.address) customerAddress = exData.address;
                if (exData.appointmentType && !method) {
                    method = exData.appointmentType === "Collect" ? "Doorstep Collection" : "On-Site Inspection";
                }
            }
        } catch (_) {}
    }

    const isInspection = String(method).toLowerCase().includes("inspect");
    const taskType = isInspection ? "inspect" : "collect";
    const appointmentType = isInspection ? "Inspect" : "Collect";
    const taskDurationMinutes = isInspection ? 90 : 30; // 1hr 30min for inspect, 30min for collect

    // 1. Resolve customer location & address details
    if (!effectiveAddressID && tradeInRequestID) {
        const reqSnap = await db.collection("tradeInRequests").doc(tradeInRequestID).get();
        if (reqSnap.exists) {
            const rData = reqSnap.data();
            if (rData.addressID) effectiveAddressID = rData.addressID;
            if (!customerAddress && rData.inspectionAddress) customerAddress = rData.inspectionAddress;
        }
    }

    let customerLocation = COMPANY_LOCATION;
    if (effectiveAddressID) {
        const custDetails = await resolveCustomerDetails(effectiveAddressID);
        if (custDetails && custDetails.location) customerLocation = custDetails.location;
    } else if (customerAddress && typeof customerAddress === "object") {
        if (customerAddress.lat && customerAddress.lng) {
            customerLocation = { lat: Number(customerAddress.lat), lng: Number(customerAddress.lng) };
        } else if (customerAddress.latitude && customerAddress.longitude) {
            customerLocation = { lat: Number(customerAddress.latitude), lng: Number(customerAddress.longitude) };
        } else if (customerAddress.addressLine) {
            try {
                const fullAddr = [customerAddress.addressLine, customerAddress.postcode, customerAddress.city, customerAddress.state].filter(Boolean).join(", ");
                const geoRes = await fetch(
                    `https://nominatim.openstreetmap.org/search?format=json&q=${encodeURIComponent(fullAddr)}&countrycodes=my&limit=1`,
                    { headers: { "User-Agent": "ReByte-App/1.0" } }
                );
                if (geoRes.ok) {
                    const geoData = await geoRes.json();
                    if (Array.isArray(geoData) && geoData.length > 0) {
                        customerLocation = { lat: parseFloat(geoData[0].lat), lng: parseFloat(geoData[0].lon) };
                    }
                }
            } catch (_) {}
        }
    }

    let formattedLocationStr = "";
    if (typeof customerAddress === "string") {
        formattedLocationStr = customerAddress;
    } else if (customerAddress && typeof customerAddress === "object") {
        formattedLocationStr = customerAddress.addressLine || customerAddress.fullAddress || customerAddress.formattedAddress || customerAddress.address || "";
    }
    if (!formattedLocationStr && effectiveAddressID) {
        try {
            const aDoc = await db.collection("address").doc(effectiveAddressID).get();
            if (aDoc.exists) {
                const aData = aDoc.data();
                formattedLocationStr = [aData.addressLine, aData.postcode, aData.city, aData.state].filter(Boolean).join(", ");
            }
        } catch (_) {}
    }

    // 2. Parse target date and time
    const parsedDate = parseLeaveDate(appointmentDate) || new Date(appointmentDate);
    const dateStr = formatDateKey(parsedDate);
    const { hours, minutes } = parseSlotTimeToHoursMinutes(appointmentTime);
    const slotStartTime = new Date(parsedDate.getFullYear(), parsedDate.getMonth(), parsedDate.getDate(), hours, minutes, 0);
    const slotEndTime = new Date(slotStartTime.getTime() + (taskDurationMinutes * 60 * 1000));

    // Identify any existing schedules linked to this appointment/task upfront so they don't count as conflicts against their own rebooking/reschedule
    const currentAppointmentSchedIDs = new Set();
    if (existingTaskID) {
        try {
            const curTaskDoc = await db.collection("task").doc(existingTaskID).get();
            if (curTaskDoc.exists && curTaskDoc.data().scheduleID) {
                currentAppointmentSchedIDs.add(curTaskDoc.data().scheduleID);
            }
        } catch (_) {}
    }
    if (existingAppointmentID) {
        try {
            const curAppTasks = await db.collection("task").where("appointmentID", "==", existingAppointmentID).get();
            for (const tDoc of curAppTasks.docs) {
                if (tDoc.data().scheduleID) currentAppointmentSchedIDs.add(tDoc.data().scheduleID);
            }
            const curAppScheds = await db.collection("schedule").where("appointmentID", "==", existingAppointmentID).get();
            for (const sDoc of curAppScheds.docs) {
                currentAppointmentSchedIDs.add(sDoc.id);
            }
        } catch (_) {}
    }

    // 3. Step 1: Get eligible staff not taking approved leave
    const staffOnLeave = await getStaffIDsOnApprovedLeave(appointmentDate);
    const excludeSet = new Set((Array.isArray(excludeStaffIDs) ? excludeStaffIDs : [excludeStaffIDs]).filter(Boolean));

    const usersSnap = await db.collection("users")
        .where("role", "in", ["Staff", "staff"])
        .get();

    const eligibleStaff = [];
    for (const doc of usersSnap.docs) {
        const data = doc.data();
        const staffID = doc.id;
        const status = String(data.status || data.staffStatus || "active").toLowerCase().trim();
        if (status === "archived" || status === "inactive") continue;

        if (excludeSet.has(staffID) || (data.staffNo && excludeSet.has(data.staffNo))) {
            console.log(`[EXCLUDED STAFF] Staff ${staffID} (${data.fullName || "Staff"}) is excluded from assignment/reassignment.`);
            continue;
        }

        if (staffOnLeave.has(staffID)) {
            console.log(`[STAFF ON APPROVED LEAVE] Staff ${staffID} (${data.fullName || "Staff"}) on approved leave -> excluded.`);
            continue;
        }

        const pos = String(data.position || data.roleType || "").toLowerCase().trim();

        if (isInspection) {
            // Inspection: Role is 'inspector' or 'inspector & collector'
            const isInspectorRole = pos === "inspector" || pos.includes("inspector");
            if (!isInspectorRole) continue;
        } else {
            // Collection: Role is 'inspector & collector' ONLY
            const isCollectorRole = pos === "inspector & collector" || (pos.includes("collector") && pos.includes("inspector"));
            if (!isCollectorRole) continue;
        }

        let workBaseLocation = COMPANY_LOCATION;
        if (data.workLocation && data.workLocation.lat && data.workLocation.lng) {
            workBaseLocation = { lat: Number(data.workLocation.lat), lng: Number(data.workLocation.lng) };
        } else if (data.currentLat && data.currentLng) {
            workBaseLocation = { lat: Number(data.currentLat), lng: Number(data.currentLng) };
        }

        eligibleStaff.push({
            staffID,
            staffNo: data.staffNo || staffID,
            fullName: data.fullName || "Staff",
            position: data.position,
            specialization: data.specialization || [],
            workBaseLocation
        });
    }

    console.log(`[ELIGIBLE STAFF FOUND] ${eligibleStaff.length} candidate(s) for ${appointmentType} role.`);
    if (eligibleStaff.length === 0) {
        return {
            success: false,
            message: `No active staff with '${isInspection ? "Inspector" : "Inspector & Collector"}' role available on ${dateStr}.`
        };
    }

    // 4. Step 2: Filter staff who can make it on time
    const onTimeStaff = [];

    for (const staff of eligibleStaff) {
        const schedSnap = await db.collection("schedule")
            .where("staffID", "==", staff.staffID)
            .where("scheduleDate", "==", dateStr)
            .where("scheduleStatus", "in", ["assigned", "ongoing"])
            .get();

        const existingTasks = [];
        for (const sDoc of schedSnap.docs) {
            // Ignore previous schedule(s) for this exact appointment being rescheduled
            if (currentAppointmentSchedIDs.has(sDoc.id) || (existingAppointmentID && sDoc.id.startsWith(`SCH-${existingAppointmentID}`))) {
                continue;
            }
            const sData = sDoc.data();
            const sStart = parseScheduleDate(sData.scheduleStartTime, dateStr);
            const sEnd = parseScheduleDate(sData.scheduleEndTime, dateStr);

            let loc = COMPANY_LOCATION;
            let appointmentID = sData.appointmentID;
            if (!appointmentID && !sData.orderID) {
                const tSnap = await db.collection("task").where("scheduleID", "==", sDoc.id).limit(1).get();
                if (!tSnap.empty) {
                    appointmentID = tSnap.docs[0].data().appointmentID;
                }
            }

            if (sData.orderID) {
                const ordDoc = await db.collection("order").doc(sData.orderID).get();
                if (ordDoc.exists && ordDoc.data().addressID) {
                    const cDet = await resolveCustomerDetails(ordDoc.data().addressID);
                    if (cDet && cDet.location) loc = cDet.location;
                }
            } else if (appointmentID) {
                const appDoc = await db.collection("tradeInAppointment").doc(appointmentID).get();
                if (appDoc.exists) {
                    const aData = appDoc.data();
                    if (aData.addressID) {
                        const cDet = await resolveCustomerDetails(aData.addressID);
                        if (cDet && cDet.location) loc = cDet.location;
                    } else if (aData.address && aData.address.lat && aData.address.lng) {
                        loc = { lat: Number(aData.address.lat), lng: Number(aData.address.lng) };
                    }
                }
            }

            existingTasks.push({
                scheduleID: sDoc.id,
                startTime: sStart,
                endTime: sEnd,
                location: loc
            });
        }

        // Direct conflict check: Cannot overlap an existing task
        const hasTimeOverlap = existingTasks.some(t => {
            if (!t.startTime || !t.endTime) return false;
            return (slotStartTime < t.endTime && slotEndTime > t.startTime);
        });
        if (hasTimeOverlap) {
            console.log(`[SCHEDULE CONFLICT] Staff ${staff.fullName} already has a task overlapping ${appointmentTime}.`);
            continue;
        }

        let route = null;
        let canMakeOnTime = false;

        if (existingTasks.length === 0) {
            // Staff task = 0: Staff work location -> task new location (9:00 AM start time)
            route = await getOsrmRoute(staff.workBaseLocation, customerLocation);
            const nineAm = new Date(parsedDate.getFullYear(), parsedDate.getMonth(), parsedDate.getDate(), 9, 0, 0);
            const arrivalTime = new Date(nineAm.getTime() + (route.durationMinutes * 60 * 1000));
            if (arrivalTime <= slotStartTime) {
                canMakeOnTime = true;
            }
            console.log(`[ON-TIME CHECK] Staff ${staff.fullName} (0 tasks): 9:00 AM + ${route.durationMinutes}m arrival ${formatTimeOnly(arrivalTime)} vs slot ${formatTimeOnly(slotStartTime)} -> ${canMakeOnTime ? 'ON TIME' : 'LATE'}`);
        } else {
            // Staff has existing tasks on that day
            const sortedByEndTime = [...existingTasks]
                .filter(t => t.endTime)
                .sort((a, b) => b.endTime.getTime() - a.endTime.getTime());

            const tasksBefore = sortedByEndTime.filter(t => t.endTime <= slotStartTime);

            if (tasksBefore.length > 0) {
                // There is a task before this slot: staff travels from lastTask to customer
                const lastTask = tasksBefore[0];
                route = await getOsrmRoute(lastTask.location || staff.workBaseLocation, customerLocation);
                const arrivalTime = new Date(lastTask.endTime.getTime() + (route.durationMinutes * 60 * 1000));
                if (arrivalTime <= slotStartTime) {
                    canMakeOnTime = true;
                }
                console.log(`[ON-TIME CHECK] Staff ${staff.fullName} (>0 tasks, prior task exists): Last task end ${formatTimeOnly(lastTask.endTime)} + ${route.durationMinutes}m travel arrival ${formatTimeOnly(arrivalTime)} vs slot ${formatTimeOnly(slotStartTime)} -> ${canMakeOnTime ? 'ON TIME' : 'LATE'}`);
            } else {
                // All existing tasks are AFTER this slot: staff starts from work base at 9:00 AM
                route = await getOsrmRoute(staff.workBaseLocation, customerLocation);
                const nineAm = new Date(parsedDate.getFullYear(), parsedDate.getMonth(), parsedDate.getDate(), 9, 0, 0);
                const arrivalTime = new Date(nineAm.getTime() + (route.durationMinutes * 60 * 1000));
                if (arrivalTime <= slotStartTime) {
                    canMakeOnTime = true;
                }
                console.log(`[ON-TIME CHECK] Staff ${staff.fullName} (>0 tasks, no prior task): 9:00 AM + ${route.durationMinutes}m arrival ${formatTimeOnly(arrivalTime)} vs slot ${formatTimeOnly(slotStartTime)} -> ${canMakeOnTime ? 'ON TIME' : 'LATE'}`);
            }

            // Also check if staff has a subsequent task after this slot and can reach it on time
            if (canMakeOnTime) {
                const tasksAfter = existingTasks
                    .filter(t => t.startTime && t.startTime >= slotEndTime)
                    .sort((a, b) => a.startTime.getTime() - b.startTime.getTime());

                if (tasksAfter.length > 0) {
                    const nextTask = tasksAfter[0];
                    const routeToNext = await getOsrmRoute(customerLocation, nextTask.location || staff.workBaseLocation);
                    const arrivalAtNext = new Date(slotEndTime.getTime() + (routeToNext.durationMinutes * 60 * 1000));
                    if (arrivalAtNext > nextTask.startTime) {
                        canMakeOnTime = false;
                        console.log(`[ON-TIME CHECK] Staff ${staff.fullName} cannot reach next task at ${formatTimeOnly(nextTask.startTime)} on time (arrival: ${formatTimeOnly(arrivalAtNext)} after slot end ${formatTimeOnly(slotEndTime)} + ${routeToNext.durationMinutes}m travel) -> LATE`);
                    }
                }
            }
        }

        const evaluatedItem = {
            staff,
            distanceKm: route ? route.distanceKm : 999,
            durationMinutes: route ? route.durationMinutes : 999,
            taskCount: existingTasks.length
        };

        if (canMakeOnTime) {
            onTimeStaff.push(evaluatedItem);
        } else {
            console.log(`[INELIGIBLE STAFF] Staff ${staff.fullName} is LATE and cannot make it on time -> Ineligible.`);
        }
    }

    // Candidate pool: ONLY staff who can make it on time are eligible to get the task.
    // Late staff (cannot arrive on time) are NOT eligible.
    let candidatePool = onTimeStaff;
    if (candidatePool.length === 0) {
        console.log(`[ASSIGNMENT FAILED] No eligible staff can arrive on time for appointment slot ${appointmentTime} on ${dateStr}.`);
        return {
            success: false,
            message: `No eligible staff can arrive on time for appointment slot ${appointmentTime} on ${dateStr}.`
        };
    }


    // 5. Step 3: Filter by device specialization (For inspection only)
    if (isInspection && candidatePool.length > 1) {
        let deviceBrand = "";
        let deviceModel = "";

        if (tradeInRequestID) {
            const reqSnap = await db.collection("tradeInRequests").doc(tradeInRequestID).get();
            if (reqSnap.exists) {
                const rData = reqSnap.data();
                deviceBrand = rData.deviceBrand || rData.brand || "";
                deviceModel = rData.deviceModel || rData.model || "";
                if (!deviceBrand && rData.deviceID) {
                    const devDoc = await db.collection("devices").doc(rData.deviceID).get();
                    if (devDoc.exists) {
                        deviceBrand = devDoc.data().brand || "";
                        deviceModel = devDoc.data().model || devDoc.data().name || "";
                    }
                }
            }
        }

        console.log(`[DEVICE SPECIALIZATION FILTER] Target Device: '${deviceBrand}' '${deviceModel}'`);
        const specializationMatches = candidatePool.filter(c =>
            staffMatchesDeviceSpecialization(c.staff.specialization, deviceBrand, deviceModel)
        );

        // "if it filter until zero staff then ignore this step"
        if (specializationMatches.length > 0) {
            console.log(`[SPECIALIZATION MATCH] Found ${specializationMatches.length} staff specializing in ${deviceBrand || deviceModel}.`);
            candidatePool = specializationMatches;
        } else {
            console.log(`[SPECIALIZATION IGNORED] 0 staff matched specialization -> ignoring specialization filter.`);
        }
    }

    // 6. Step 4: Filter shortest distance to task location.
    // If the shortest distance is the same for multiple staff,
    // take the staff that have the lowest task count on that day.
    // If still same, just choose either one.
    if (candidatePool.length > 1) {
        candidatePool.sort((a, b) => {
            const distDiff = a.distanceKm - b.distanceKm;
            if (Math.abs(distDiff) > 0.01) {
                return distDiff;
            }
            // Same shortest distance -> tie-break by lowest task count on that day
            const taskDiff = (a.taskCount || 0) - (b.taskCount || 0);
            if (taskDiff !== 0) {
                return taskDiff;
            }
            return 0; // If still same, choose either one
        });
    }

    const bestCandidate = candidatePool[0];
    const bestStaff = bestCandidate.staff;
    console.log(`[BEST STAFF SELECTED] ${bestStaff.fullName} (${bestStaff.position}) - Distance: ${bestCandidate.distanceKm} km, Travel Duration: ${bestCandidate.durationMinutes} mins, Tasks Today: ${bestCandidate.taskCount || 0}`);

    // 7. Reuse existing record IDs or generate only for first-time booking (DO NOT create new appointment/task on reassign)
    const appointmentID = existingAppointmentID || (await generateAppointmentID(parsedDate));
    const taskID = existingTaskID || `TSK-${appointmentID}`;
    // Schedule ID format: SCH-<appointmentID>-<4 chars>
    // On reassignment, change only the back 4 characters; do NOT keep adding extra segments to the ID
    const staffSuffix = (bestStaff && bestStaff.staffID) ? bestStaff.staffID.slice(-4) : "0001";
    let scheduleID = `SCH-${appointmentID}-${staffSuffix}`;
    try {
        let sSnap = await db.collection("schedule").doc(scheduleID).get();
        if (sSnap.exists) {
            let attempt = 0;
            while (sSnap.exists && attempt < 5) {
                const random4 = Math.floor(1000 + Math.random() * 9000).toString();
                scheduleID = `SCH-${appointmentID}-${random4}`;
                sSnap = await db.collection("schedule").doc(scheduleID).get();
                attempt++;
            }
        }
    } catch (_) {}

    const totalEstimatedDuration = Math.round(bestCandidate.durationMinutes + taskDurationMinutes);
    const totalEstimatedDistance = Number(bestCandidate.distanceKm.toFixed(2));
    const formattedStartTime = formatTimeOnly(slotStartTime);
    const formattedEndTime = formatTimeOnly(slotEndTime);

    // 8. Previous schedule(s) for this appointment/task: mark as 'reassigned' (DO NOT delete)
    const prevSchedIDs = new Set();
    try {
        if (existingTaskID) {
            const curTaskDoc = await db.collection("task").doc(existingTaskID).get();
            if (curTaskDoc.exists && curTaskDoc.data().scheduleID) {
                prevSchedIDs.add(curTaskDoc.data().scheduleID);
            }
        }
        if (appointmentID) {
            const sByAppSnap = await db.collection("schedule")
                .where("appointmentID", "==", appointmentID)
                .get();
            for (const sDoc of sByAppSnap.docs) {
                prevSchedIDs.add(sDoc.id);
            }
            const allScheds = await db.collection("schedule").get();
            for (const sDoc of allScheds.docs) {
                if (sDoc.id.startsWith(`SCH-${appointmentID}`) && sDoc.id !== scheduleID) {
                    prevSchedIDs.add(sDoc.id);
                }
            }
        }
    } catch (_) {}

    for (const prevSchedID of prevSchedIDs) {
        if (prevSchedID === scheduleID) continue;
        try {
            const psDoc = await db.collection("schedule").doc(prevSchedID).get();
            if (psDoc.exists) {
                const sData = psDoc.data();
                if (sData.scheduleStatus !== "rejected" && sData.scheduleStatus !== "absent") {
                    console.log(`[SCHEDULE REASSIGNED] Marking previous schedule [${prevSchedID}] as 'reassigned'.`);
                    await psDoc.ref.update({
                        scheduleStatus: "reassigned",
                        reassignedAt: new Date(),
                        updatedAt: new Date()
                    });
                }
            }
        } catch (err) {
            console.error(`Error marking previous schedule ${prevSchedID} as reassigned:`, err);
        }
    }

    // 9. Update/exchange data into existing tradeInAppointment record & return to Scheduled/Confirmed (clear onHold attributes)
    await db.collection("tradeInAppointment").doc(appointmentID).set({
        appointmentID,
        appointmentType,
        scheduledAt: Timestamp.fromDate(slotStartTime),
        appointmentStatus: "Scheduled",
        bookingStatus: "Confirmed",
        addressID: effectiveAddressID || null,
        tradeInRequestID: tradeInRequestID || null,
        // Ensure no unnecessary attributes are added
        appointmentDate: FieldValue.delete(),
        appointmentTime: FieldValue.delete(),
        appointmentLocation: FieldValue.delete(),
        address: FieldValue.delete(),
        onHoldReason: FieldValue.delete(),
        onHoldAt: FieldValue.delete(),
        holdReason: FieldValue.delete(),
        reassignedAt: FieldValue.delete(),
        reassignReason: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp()
    }, { merge: true });

    // 10. Update/exchange data into existing task record & return to Assigned status attributes (clear onHold attributes)
    await db.collection("task").doc(taskID).set({
        taskID,
        taskType,
        taskStatus: "Assigned",
        taskStartTime: formattedStartTime,
        estimatedDuration: totalEstimatedDuration,
        estimatedDistance: totalEstimatedDistance,
        scheduleID,
        orderID: null,
        appointmentID,
        tradeInRequestID: tradeInRequestID || null,
        staffID: bestStaff.staffID,
        staffName: FieldValue.delete(),
        // Ensure no unnecessary attributes are added
        taskDate: FieldValue.delete(),
        taskEndTime: FieldValue.delete(),
        scheduledAt: FieldValue.delete(),
        appointmentLocation: FieldValue.delete(),
        addressID: FieldValue.delete(),
        address: FieldValue.delete(),
        onHoldReason: FieldValue.delete(),
        onHoldAt: FieldValue.delete(),
        holdReason: FieldValue.delete(),
        reassignedAt: FieldValue.delete(),
        reassignReason: FieldValue.delete(),
        rejectionReason: FieldValue.delete(),
        rejectionNotes: FieldValue.delete(),
        staffLat: FieldValue.delete(),
        staffLng: FieldValue.delete(),
        staffHeading: FieldValue.delete(),
        lastGpsUpdate: FieldValue.delete(),
        updatedAt: new Date()
    }, { merge: true });

    // 11. Create new schedule record with scheduleStatus: "assigned"
    await db.collection("schedule").doc(scheduleID).set({
        scheduleID,
        scheduleDate: dateStr,
        scheduleStartTime: formattedStartTime,
        scheduleEndTime: formattedEndTime,
        scheduleStatus: "assigned",
        staffID: bestStaff.staffID,
        createdAt: new Date(),
        updatedAt: new Date()
    });

    if (tradeInRequestID) {
        await db.collection("tradeInRequests").doc(tradeInRequestID).update({
            requestStatus: "Scheduled",
            bookingStatus: "Confirmed",
            appointmentID,
            appointmentDate: dateStr,
            appointmentTime: appointmentTime || formattedStartTime,
            addressID: effectiveAddressID || null,
            appointmentLocation: formattedLocationStr || null,
            inspectionAddress: formattedLocationStr || null,
            inspectionMethod: appointmentType === "Collect" ? "Doorstep Collection" : "On-Site Inspection",
            onHoldReason: FieldValue.delete(),
            onHoldAt: FieldValue.delete(),
            holdReason: FieldValue.delete(),
            reassignedAt: FieldValue.delete(),
            updatedAt: new Date()
        }).catch(() => {});
    }

    return {
        success: true,
        appointmentID,
        taskID,
        scheduleID,
        staffID: bestStaff.staffID,
        staffName: bestStaff.fullName,
        appointmentType,
        scheduledAt: slotStartTime,
        scheduleDate: dateStr,
        scheduleStartTime: formattedStartTime,
        scheduleEndTime: formattedEndTime,
        estimatedDistance: totalEstimatedDistance,
        estimatedDuration: totalEstimatedDuration,
        message: `${appointmentType} task successfully assigned to ${bestStaff.fullName}.`
    };
}

const INSPECTION_SLOTS = [
    '09:30 AM',
    '11:00 AM',
    '01:00 PM',
    '01:30 PM',
    '02:30 PM',
    '03:00 PM',
];

const COLLECTION_SLOTS = [
    '09:30 AM',
    '10:00 AM',
    '10:30 AM',
    '11:00 AM',
    '11:30 AM',
    '01:00 PM',
    '01:30 PM',
    '02:00 PM',
    '02:30 PM',
    '03:00 PM',
    '03:30 PM',
    '04:00 PM',
];

/**
 * Check availability of appointment slots for a given date and method.
 * If all eligible staff have a task during a slot's time period, that slot is disabled (slashed).
 */
async function checkSlotAvailabilityForDate({ method = "On-Site Inspection", dateStr }) {
    if (!dateStr) return { disabledSlots: [], availableSlots: [] };

    const isInspection = String(method).toLowerCase().includes("inspect");
    const taskDurationMinutes = isInspection ? 90 : 30; // 1hr 30m for inspect, 30m for collect
    const allSlots = isInspection ? INSPECTION_SLOTS : COLLECTION_SLOTS;

    // 1. Get eligible staff for this role who are not on approved leave on dateStr
    const staffOnLeave = await getStaffIDsOnApprovedLeave(dateStr);
    const usersSnap = await db.collection("users")
        .where("role", "in", ["Staff", "staff"])
        .get();

    const eligibleStaffIds = [];
    for (const doc of usersSnap.docs) {
        const data = doc.data();
        const staffID = doc.id;
        const status = String(data.status || data.staffStatus || "active").toLowerCase().trim();
        if (status === "archived" || status === "inactive") continue;
        if (staffOnLeave.has(staffID)) continue;

        const pos = String(data.position || data.roleType || "").toLowerCase().trim();
        if (isInspection) {
            // Inspector or Inspector & Collector
            if (pos === "inspector" || pos.includes("inspector")) {
                eligibleStaffIds.push(staffID);
            }
        } else {
            // Inspector & Collector ONLY
            if (pos === "inspector & collector" || (pos.includes("collector") && pos.includes("inspector"))) {
                eligibleStaffIds.push(staffID);
            }
        }
    }

    // If no eligible staff exist on this day, all slots are disabled
    if (eligibleStaffIds.length === 0) {
        return {
            date: dateStr,
            method,
            allSlots,
            disabledSlots: allSlots,
            availableSlots: []
        };
    }

    // 2. Fetch all active schedules on dateStr for eligible staff
    const schedSnap = await db.collection("schedule")
        .where("scheduleDate", "==", dateStr)
        .where("scheduleStatus", "in", ["assigned", "ongoing"])
        .get();

    const staffSchedules = {};
    for (const sid of eligibleStaffIds) {
        staffSchedules[sid] = [];
    }

    for (const sDoc of schedSnap.docs) {
        const sData = sDoc.data();
        const staffID = sData.staffID;
        if (!staffSchedules[staffID]) continue;

        const sStart = parseScheduleDate(sData.scheduleStartTime, dateStr);
        const sEnd = parseScheduleDate(sData.scheduleEndTime, dateStr);
        if (sStart && sEnd) {
            staffSchedules[staffID].push({ startTime: sStart, endTime: sEnd });
        }
    }

    // 3. For each slot, check whether any eligible staff is available (free from conflicting tasks)
    const parsedDate = parseLeaveDate(dateStr) || new Date(dateStr);
    const disabledSlots = [];
    const availableSlots = [];

    for (const slot of allSlots) {
        const { hours, minutes } = parseSlotTimeToHoursMinutes(slot);
        const slotStart = new Date(parsedDate.getFullYear(), parsedDate.getMonth(), parsedDate.getDate(), hours, minutes, 0);
        const slotEnd = new Date(slotStart.getTime() + (taskDurationMinutes * 60 * 1000));

        let availableStaffCount = 0;
        for (const sid of eligibleStaffIds) {
            const existingTasks = staffSchedules[sid] || [];
            // Check if this staff has a task that overlaps [slotStart, slotEnd]
            const hasConflict = existingTasks.some(t => {
                return (slotStart < t.endTime && slotEnd > t.startTime);
            });

            if (!hasConflict) {
                availableStaffCount++;
            }
        }

        // If all eligible staff have a task during this period, slot cannot be chosen -> disabled
        if (availableStaffCount === 0) {
            disabledSlots.push(slot);
        } else {
            availableSlots.push(slot);
        }
    }

    return {
        date: dateStr,
        method,
        allSlots,
        disabledSlots,
        availableSlots
    };
}

/**
 * Check slot availability for all days of a given month (e.g. "2026-10").
 * Returns an array of disabled/fully booked dates where 0 slots are available.
 */
async function checkMonthAvailabilityForTradeIn({ method = "On-Site Inspection", monthStr }) {
    if (!monthStr) {
        const now = new Date();
        monthStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
    }

    const [yearStr, mStr] = monthStr.split("-");
    const year = parseInt(yearStr, 10);
    const month = parseInt(mStr, 10);
    const daysInMonth = new Date(year, month, 0).getDate();

    const isInspection = String(method).toLowerCase().includes("inspect");
    const taskDurationMinutes = isInspection ? 90 : 30;
    const allSlots = isInspection ? INSPECTION_SLOTS : COLLECTION_SLOTS;

    // 1. Get eligible staff
    const usersSnap = await db.collection("users")
        .where("role", "in", ["Staff", "staff"])
        .get();

    const eligibleStaffIds = [];
    for (const doc of usersSnap.docs) {
        const data = doc.data();
        const staffID = doc.id;
        const status = String(data.status || data.staffStatus || "active").toLowerCase().trim();
        if (status === "archived" || status === "inactive") continue;

        const pos = String(data.position || data.roleType || "").toLowerCase().trim();
        if (isInspection) {
            if (pos === "inspector" || pos.includes("inspector")) {
                eligibleStaffIds.push(staffID);
            }
        } else {
            if (pos === "inspector & collector" || (pos.includes("collector") && pos.includes("inspector"))) {
                eligibleStaffIds.push(staffID);
            }
        }
    }

    const disabledDates = [];
    if (eligibleStaffIds.length === 0) {
        for (let d = 1; d <= daysInMonth; d++) {
            disabledDates.push(`${yearStr}-${mStr.padStart(2, "0")}-${String(d).padStart(2, "0")}`);
        }
        return {
            success: true,
            month: monthStr,
            disabledDates,
            firstAvailableDate: null
        };
    }

    // 2. Fetch all approved leaves
    const leaveSnap = await db.collection("leaveApplication")
        .where("leaveStatus", "in", ["Approved", "approved"])
        .get();

    const approvedLeaves = [];
    for (const doc of leaveSnap.docs) {
        const data = doc.data();
        const staffId = data.applicantStaffID;
        if (!staffId || !eligibleStaffIds.includes(staffId)) continue;
        const sDate = parseLeaveDate(data.startDate);
        const eDate = parseLeaveDate(data.endDate);
        if (sDate && eDate) {
            approvedLeaves.push({
                staffId,
                start: new Date(sDate.getFullYear(), sDate.getMonth(), sDate.getDate(), 0, 0, 0),
                end: new Date(eDate.getFullYear(), eDate.getMonth(), eDate.getDate(), 23, 59, 59, 999)
            });
        }
    }

    // 3. Fetch all active schedules in that month (query by date range only to avoid requiring composite index)
    const startMonthStr = `${yearStr}-${mStr.padStart(2, "0")}-01`;
    const endMonthStr = `${yearStr}-${mStr.padStart(2, "0")}-${String(daysInMonth).padStart(2, "0")}`;

    const schedSnap = await db.collection("schedule")
        .where("scheduleDate", ">=", startMonthStr)
        .where("scheduleDate", "<=", endMonthStr)
        .get();

    // Group schedules by date and staffID
    const schedulesByDate = {};
    for (const sDoc of schedSnap.docs) {
        const sData = sDoc.data();
        const schedStatus = String(sData.scheduleStatus || "").toLowerCase().trim();
        if (schedStatus !== "assigned" && schedStatus !== "ongoing") continue;

        const sDate = sData.scheduleDate;
        const staffID = sData.staffID;
        if (!sDate || !eligibleStaffIds.includes(staffID)) continue;

        if (!schedulesByDate[sDate]) schedulesByDate[sDate] = {};
        if (!schedulesByDate[sDate][staffID]) schedulesByDate[sDate][staffID] = [];

        const sStart = parseScheduleDate(sData.scheduleStartTime, sDate);
        const sEnd = parseScheduleDate(sData.scheduleEndTime, sDate);
        if (sStart && sEnd) {
            schedulesByDate[sDate][staffID].push({ startTime: sStart, endTime: sEnd });
        }
    }

    // 4. For each day in the month, check if there is at least one open slot
    for (let day = 1; day <= daysInMonth; day++) {
        const dayStr = String(day).padStart(2, "0");
        const dateStr = `${yearStr}-${mStr.padStart(2, "0")}-${dayStr}`;
        const dayDate = new Date(year, month - 1, day, 0, 0, 0);

        // Filter eligible staff not on leave on this date
        const staffAvailableOnDay = eligibleStaffIds.filter(sid => {
            const onLeave = approvedLeaves.some(l => l.staffId === sid && dayDate >= l.start && dayDate <= l.end);
            return !onLeave;
        });

        if (staffAvailableOnDay.length === 0) {
            disabledDates.push(dateStr);
            continue;
        }

        const dayScheds = schedulesByDate[dateStr] || {};
        let dayHasAvailableSlot = false;

        for (const slot of allSlots) {
            const { hours, minutes } = parseSlotTimeToHoursMinutes(slot);
            const slotStart = new Date(year, month - 1, day, hours, minutes, 0);
            const slotEnd = new Date(slotStart.getTime() + (taskDurationMinutes * 60 * 1000));

            const hasFreeStaff = staffAvailableOnDay.some(sid => {
                const existingTasks = dayScheds[sid] || [];
                const conflict = existingTasks.some(t => slotStart < t.endTime && slotEnd > t.startTime);
                return !conflict;
            });

            if (hasFreeStaff) {
                dayHasAvailableSlot = true;
                break;
            }
        }

        if (!dayHasAvailableSlot) {
            disabledDates.push(dateStr);
        }
    }

    // Compute first available date starting from tomorrow (24h advance)
    const now = new Date();
    const minBookDate = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 0);
    let firstAvailableDate = null;

    for (let day = 1; day <= daysInMonth; day++) {
        const dayDate = new Date(year, month - 1, day, 0, 0, 0);
        const dayStr = String(day).padStart(2, "0");
        const dateStr = `${yearStr}-${mStr.padStart(2, "0")}-${dayStr}`;

        if (dayDate >= minBookDate && !disabledDates.includes(dateStr)) {
            firstAvailableDate = dateStr;
            break;
        }
    }

    return {
        success: true,
        month: monthStr,
        disabledDates,
        firstAvailableDate
    };
}

module.exports = {
    assignDeliveryTask,
    assignTradeInTask,
    generateAppointmentID,
    checkSlotAvailabilityForDate,
    checkMonthAvailabilityForTradeIn,
    reassignStaffTasksOnRoleChange,
    reassignDelivererTasksOnRoleChange: reassignStaffTasksOnRoleChange,
    handleFailedTradeInReassignment,
    sendTradeInOnHoldEmail,
    getEligibleDeliveryStaff,
    getStaffIDsOnApprovedLeave,
    parseLeaveDate,
    WORKING_HOUR_CONFIG
};
