const db = require("../config/firebase");
const { FieldValue } = require("firebase-admin/firestore");
const { COMPANY_LOCATION, getOsrmRoute } = require("./osrmService");

// Configurable working hours & constraints (Non-hardcoded, easily adjustable)
const WORKING_HOUR_CONFIG = {
    startHour: 9,      // 9:00 AM
    endHour: 17,       // 5:00 PM (17:00)
    slotIntervalHours: 1, // 1 hour step
    bufferMinutes: 15, // 15 min buffer between tasks
    defaultMaxTasks: 5  // Maximum active/assigned tasks per staff if unspecified
};

/**
 * Generate candidate slots starting from requested time
 * Uses variable loop with + slotIntervalHours (no hardcoded if 9 else if 10)
 */
function generateCandidateSlots(startDateTime, daysToCheck = 7) {
    const slots = [];
    let currentDay = new Date(startDateTime);

    for (let dayOffset = 0; dayOffset < daysToCheck; dayOffset++) {
        const dateObj = new Date(currentDay);
        dateObj.setDate(dateObj.getDate() + dayOffset);

        const year = dateObj.getFullYear();
        const month = dateObj.getMonth();
        const day = dateObj.getDate();

        // Determine starting hour for candidate slots
        let initialHour = WORKING_HOUR_CONFIG.startHour;

        if (dayOffset === 0) {
            // Same day checking
            const reqHour = startDateTime.getHours();
            const reqMinute = startDateTime.getMinutes();

            if (reqHour < WORKING_HOUR_CONFIG.startHour) {
                // Before opening: start at opening
                initialHour = WORKING_HOUR_CONFIG.startHour;
            } else if (reqHour >= WORKING_HOUR_CONFIG.endHour) {
                // After closing: no slots today, move to next day
                continue;
            } else {
                // Within working hours: next hourly slot
                initialHour = reqMinute > 0 ? reqHour + 1 : reqHour;
                if (initialHour >= WORKING_HOUR_CONFIG.endHour) {
                    continue;
                }
            }
        }

        // Loop from startHour to endHour using configurable interval
        for (let hour = initialHour; hour < WORKING_HOUR_CONFIG.endHour; hour += WORKING_HOUR_CONFIG.slotIntervalHours) {
            const slotStart = new Date(year, month, day, hour, 0, 0, 0);
            const slotEnd = new Date(year, month, day, hour + WORKING_HOUR_CONFIG.slotIntervalHours, 0, 0, 0);

            slots.push({
                slotStart,
                slotEnd,
                dateString: `${year}-${String(month + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`
            });
        }
    }

    return slots;
}

/**
 * Resolve customer coordinate {lat, lng} from addressID or order
 */
async function resolveCustomerCoordinates(addressID) {
    if (!addressID) {
        return { lat: 5.3542, lng: 100.3015 };
    }

    try {
        const aDoc = await db.collection("address").doc(addressID).get();
        if (aDoc.exists) {
            const aData = aDoc.data();
            if (aData.lat && aData.lng) {
                return { lat: Number(aData.lat), lng: Number(aData.lng) };
            }
            if (aData.latitude && aData.longitude) {
                return { lat: Number(aData.latitude), lng: Number(aData.longitude) };
            }

            // Build full address string to geocode exact coordinates
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
                                // Cache coordinates back to address document so future calls are instant
                                await db.collection("address").doc(addressID).update({
                                    lat: exactLat,
                                    lng: exactLng
                                }).catch(() => {});
                                return { lat: exactLat, lng: exactLng };
                            }
                        }
                    }
                } catch (geoErr) {
                    console.warn("Nominatim geocoding error:", geoErr.message);
                }
            }
        }
    } catch (err) {
        console.warn("Failed to fetch address doc for coordinates:", err);
    }

    // Default nearby coordinate for testing
    return { lat: 5.4045, lng: 100.3333 };
}

/**
 * Fetch all eligible delivery staff from users collection
 * Criteria:
 * - role / systemRole includes 'Staff'
 * - position = 'Deliverer' or 'Delivery' or 'Both'
 * - staffStatus / status != 'archived'
 */
async function getEligibleDeliveryStaff() {
    const usersSnap = await db.collection("users")
        .where("role", "in", ["Staff", "staff"])
        .get();

    const staffList = [];

    for (const doc of usersSnap.docs) {
        const data = doc.data();
        const status = String(data.status || data.staffStatus || "active").toLowerCase().trim();
        if (status === "archived") continue;

        const pos = String(data.position || data.roleType || "").toLowerCase().trim();
        // role = Delivery, Deliverer, or Both
        const isDeliveryRole = pos.includes("deliver") || pos.includes("both");
        if (!isDeliveryRole) continue;

        const staffID = doc.id;
        const staffNo = data.staffNo || doc.id;
        const maxTask = Number(data.maxTask || WORKING_HOUR_CONFIG.defaultMaxTasks);

        // Fetch current active tasks for staff count check
        const activeSchedulesSnap = await db.collection("schedule")
            .where("staffID", "==", staffID)
            .where("scheduleStatus", "in", ["assigned", "ongoing"])
            .get();

        const currentTaskCount = activeSchedulesSnap.size;

        if (currentTaskCount >= maxTask) {
            // Staff reached maxTask limit
            continue;
        }

        // Current location of staff (Work Base Location or default to company hub)
        let currentLocation = COMPANY_LOCATION;
        if (data.workLocation && data.workLocation.lat && data.workLocation.lng) {
            currentLocation = { lat: Number(data.workLocation.lat), lng: Number(data.workLocation.lng) };
        } else if (data.currentLat && data.currentLng) {
            currentLocation = { lat: Number(data.currentLat), lng: Number(data.currentLng) };
        }

        staffList.push({
            staffID,
            staffNo,
            fullName: data.fullName || "Delivery Staff",
            phoneNumber: data.phoneNumber || "",
            email: data.email || "",
            position: data.position,
            currentTaskCount,
            maxTask,
            currentLocation
        });
    }

    return staffList;
}

/**
 * Main Algorithm: Assign delivery task automatically using OSRM & hourly slots
 *
 * @param {Object} params
 * @param {string} params.orderID
 * @param {string} params.addressID
 * @param {Date} [params.requestedDate]
 */
async function assignDeliveryTask({ orderID, addressID, requestedDate }) {
    const taskID = `TSK-${orderID}`;
    const deliveryID = `DEL-${orderID}`;

    // 2. Resolve destination coordinates (Customer location)
    const customerLocation = await resolveCustomerCoordinates(addressID);
    const companyLocation = COMPANY_LOCATION;

    // 1. Create or ensure initial delivery record exists
    const deliveryDocRef = db.collection("delivery").doc(deliveryID);
    const delSnap = await deliveryDocRef.get();
    if (!delSnap.exists) {
        await deliveryDocRef.set({
            deliveryID,
            orderID,
            taskID,
            destinationLat: customerLocation.lat,
            destinationLng: customerLocation.lng,
            deliveryStatus: "ongoing",
            proofOfDeliveryUrl: null
        });
    }

    const processLogs = [];
    function logStep(msg) {
        console.log(msg);
        processLogs.push(msg);
    }

    logStep(`\n================================================================================`);
    logStep(`🚀 [TASK ASSIGNMENT STARTED] Order: ${orderID} | Task: ${taskID}`);
    logStep(`📍 Central Hub Location: ${companyLocation.lat}, ${companyLocation.lng}`);
    logStep(`📍 Customer Destination: ${customerLocation.lat}, ${customerLocation.lng}`);
    logStep(`🕒 Working Hours Config: ${WORKING_HOUR_CONFIG.startHour}:00 - ${WORKING_HOUR_CONFIG.endHour}:00 (Step: +${WORKING_HOUR_CONFIG.slotIntervalHours} hr, Buffer: ${WORKING_HOUR_CONFIG.bufferMinutes} min)`);
    logStep(`================================================================================\n`);

    // 3. Step 2 of OSRM requirement:
    // Leg 2: Central Hub (5.4532..., 100.2848...) -> Customer location
    const hubToCustomerRoute = await getOsrmRoute(companyLocation, customerLocation);
    logStep(`🛣️  [OSRM Leg 2: Central Hub ➔ Customer] Distance: ${hubToCustomerRoute.distanceKm} km | Duration: ${hubToCustomerRoute.durationMinutes} mins`);

    // 4. Generate candidate delivery time slots
    const now = requestedDate ? new Date(requestedDate) : new Date();
    const candidateSlots = generateCandidateSlots(now);

    if (candidateSlots.length === 0) {
        logStep(`❌ No available candidate time slots within working hours.`);
        throw new Error("No available candidate time slots within working hours.");
    }

    // 5. Get all Delivery Staff
    const eligibleStaffList = await getEligibleDeliveryStaff();
    logStep(`\n👥 [ALL ELIGIBLE DELIVERY STAFF] Found: ${eligibleStaffList.length} staff member(s):`);
    eligibleStaffList.forEach((s, idx) => {
        logStep(`   ${idx + 1}. [${s.staffNo}] ${s.fullName} (${s.position}) - Active Tasks: ${s.currentTaskCount}/${s.maxTask} | Location: ${s.currentLocation.lat.toFixed(4)}, ${s.currentLocation.lng.toFixed(4)}`);
    });

    if (eligibleStaffList.length === 0) {
        logStep(`⚠️  No active delivery staff available. Task remains pending assignment.`);
        return { success: false, reason: "No active delivery staff available", processLogs };
    }

    let assignedSlot = null;
    let selectedStaff = null;
    let totalEstimatedDurationMinutes = 0;
    let totalEstimatedDistanceKm = 0;

    logStep(`\n⏰ [EVALUATING CANDIDATE TIME SLOTS]`);

    // 6. Loop through candidate time slots (earliest valid slot)
    for (const slot of candidateSlots) {
        const slotTimeStr = `${slot.dateString} ${String(slot.slotStart.getHours()).padStart(2, "0")}:00`;
        logStep(`\n------------------------------------------------------------`);
        logStep(`🕒 Time Slot: ${slotTimeStr} to ${String(slot.slotEnd.getHours()).padStart(2, "0")}:00`);

        // Filter 1: All Delivery Staff available initially
        logStep(`   1. All Delivery Staff (${eligibleStaffList.length}): [${eligibleStaffList.map(s => s.fullName).join(", ")}]`);

        const nonOverlappingStaff = [];
        const slotStaffCandidates = [];

        for (const staff of eligibleStaffList) {
            // Check existing assigned schedules for this staff on this date
            const existingSchedSnap = await db.collection("schedule")
                .where("staffID", "==", staff.staffID)
                .where("scheduleDate", "==", slot.dateString)
                .get();

            let hasOverlap = false;
            let lastTaskEndTime = null;
            let lastTaskLocation = staff.currentLocation || COMPANY_LOCATION;

            for (const sDoc of existingSchedSnap.docs) {
                const sData = sDoc.data();
                const parseScheduleDate = (timeVal, dateStr) => {
                    if (!timeVal) return null;
                    if (timeVal.toDate) return timeVal.toDate();
                    const str = String(timeVal).trim();
                    if (str.includes("T") || str.includes("-")) return new Date(str);
                    // Time string only e.g. "09:00" or "09:00:00"
                    const baseDate = dateStr || slot.dateString;
                    return new Date(`${baseDate}T${str.length === 5 ? str + ":00" : str}`);
                };

                const sStart = parseScheduleDate(sData.scheduleStartTime, sData.scheduleDate);
                const sEnd = parseScheduleDate(sData.scheduleEndTime, sData.scheduleDate);

                if (sStart && sEnd && !isNaN(sStart) && !isNaN(sEnd)) {
                    // Check if candidate slot overlaps
                    if (slot.slotStart < sEnd && slot.slotEnd > sStart) {
                        hasOverlap = true;
                        break;
                    }

                    // Keep track of the task directly preceding this slot
                    if (sEnd <= slot.slotStart) {
                        if (!lastTaskEndTime || sEnd > lastTaskEndTime) {
                            lastTaskEndTime = sEnd;
                            if (sData.destinationLat && sData.destinationLng) {
                                lastTaskLocation = { lat: sData.destinationLat, lng: sData.destinationLng };
                            } else {
                                // Destination coords moved to delivery; find task linked to this schedule
                                const taskSnap = await db.collection("task").where("scheduleID", "==", sDoc.id).limit(1).get();
                                if (!taskSnap.empty) {
                                    const linkedOrderID = taskSnap.docs[0].data().orderID;
                                    if (linkedOrderID) {
                                        const dSnap = await db.collection("delivery").doc(`DEL-${linkedOrderID}`).get();
                                        if (dSnap.exists && dSnap.data().destinationLat && dSnap.data().destinationLng) {
                                            lastTaskLocation = { lat: dSnap.data().destinationLat, lng: dSnap.data().destinationLng };
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if (hasOverlap) {
                // Overlaps another task -> removed
                continue;
            }

            nonOverlappingStaff.push(staff);

            // Step 1 of OSRM requirement:
            // Leg 1: Staff current location -> Company Central Hub
            const staffToHubRoute = await getOsrmRoute(lastTaskLocation, companyLocation);

            // Buffer time required: 15 MIN
            const totalTravelMinutes = staffToHubRoute.durationMinutes + WORKING_HOUR_CONFIG.bufferMinutes;

            // Check if staff can reach company hub before candidate slot start
            if (lastTaskEndTime) {
                const earliestArrival = new Date(lastTaskEndTime.getTime() + (totalTravelMinutes * 60 * 1000));
                if (earliestArrival > slot.slotStart) {
                    logStep(`   ⚠️  Staff ${staff.fullName} cannot reach hub before slot (Needs ${totalTravelMinutes}m with 15m buffer, arrives ${earliestArrival.toLocaleTimeString()}) ➔ Removed`);
                    continue;
                }
            }

            // Total route: Staff -> Hub -> Customer
            const totalDuration = staffToHubRoute.durationMinutes + hubToCustomerRoute.durationMinutes + WORKING_HOUR_CONFIG.bufferMinutes;
            const totalDistance = Number((staffToHubRoute.distanceKm + hubToCustomerRoute.distanceKm).toFixed(2));

            slotStaffCandidates.push({
                staff,
                staffToHubRoute,
                hubToCustomerRoute,
                totalDuration,
                totalDistance,
                // Score: prioritize less occupied staff, then shortest distance
                score: (staff.currentTaskCount * 100) + totalDistance
            });
        }

        // Filter 2: Non-overlapping / non-duplicated staff
        logStep(`   2. Non-duplicated / Non-overlapping Staff (${nonOverlappingStaff.length}): [${nonOverlappingStaff.map(s => s.fullName).join(", ")}]`);

        // Filter 3: Reachable Staff (can reach hub before slot with 15m buffer)
        logStep(`   3. Reachable Staff with Buffer & OSRM (${slotStaffCandidates.length}): [${slotStaffCandidates.map(c => `${c.staff.fullName} (${c.totalDuration} mins, ${c.totalDistance} km)`).join(", ")}]`);

        if (slotStaffCandidates.length > 0) {
            // Rank eligible staff (lowest score first)
            slotStaffCandidates.sort((a, b) => a.score - b.score);
            const bestCandidate = slotStaffCandidates[0];

            assignedSlot = slot;
            selectedStaff = bestCandidate.staff;
            totalEstimatedDurationMinutes = bestCandidate.totalDuration;
            totalEstimatedDistanceKm = bestCandidate.totalDistance;

            logStep(`   ✅ BEST MATCH SELECTED for ${slotTimeStr}:`);
            logStep(`      Staff: [${selectedStaff.staffNo}] ${selectedStaff.fullName}`);
            logStep(`      Total Estimated Duration: ${totalEstimatedDurationMinutes} mins (including 15m buffer)`);
            logStep(`      Total Estimated Distance: ${totalEstimatedDistanceKm} km`);
            logStep(`------------------------------------------------------------\n`);
            break; // Found earliest valid slot & best staff!
        } else {
            logStep(`   ❌ No eligible staff available for ${slotTimeStr} ➔ Moving to next hourly slot`);
        }
    }

    if (!assignedSlot || !selectedStaff) {
        logStep(`\n❌ [ASSIGNMENT FAILED] No staff could reach task within available candidate slots.`);
        return { success: false, reason: "No staff could reach tasks within available slots", processLogs };
    }

    // 7. Create Schedule record
    const scheduleID = `SCH-${orderID}-${Date.now().toString().slice(-4)}`;
    const scheduleStartTime = assignedSlot.slotStart;
    const scheduleEndTime = new Date(assignedSlot.slotStart.getTime() + (totalEstimatedDurationMinutes * 60 * 1000));

    // Format Start & End time as clean time strings without timestamp object (e.g. "09:00", "09:39")
    const formatTimeOnly = (d) => `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
    const startTimeStr = formatTimeOnly(scheduleStartTime);
    const endTimeStr = formatTimeOnly(scheduleEndTime);

    // Schedule: scheduled Start and End Time (not timestamp objects, stored as time strings)
    // No orderID, no staffName, no taskID, destinationLat/Lng moved to delivery
    await db.collection("schedule").doc(scheduleID).set({
        scheduleID,
        scheduleDate: assignedSlot.dateString,
        scheduleStartTime: startTimeStr,
        scheduleEndTime: endTimeStr,
        scheduleStatus: "assigned", // assigned, ongoing, completed
        staffID: selectedStaff.staffID
    });

    // 8. Update Task record:
    // estimatedDistance (number), estimatedDuration (number)
    // No appointmentID for deliver task
    // No staffID or staffName in task (retrieved from schedule -> staff)
    await db.collection("task").doc(taskID).set({
        taskID,
        taskType: "deliver",
        taskStatus: "Packaging",
        taskStartTime: startTimeStr,
        estimatedDistance: totalEstimatedDistanceKm,
        estimatedDuration: totalEstimatedDurationMinutes,
        scheduleID,
        orderID
    });

    // 9. Update Delivery record
    // Added 2 destination coordinates: destinationLat, destinationLng
    // deliveryStatus: 'ongoing' or 'completed' ONLY
    // No deliveredAt & pickedUpAt, no scheduleID and scheduledSlot, no staffID
    await db.collection("delivery").doc(deliveryID).set({
        deliveryID,
        orderID,
        taskID,
        destinationLat: customerLocation.lat,
        destinationLng: customerLocation.lng,
        deliveryStatus: "ongoing"
    }, { merge: true });

    return {
        success: true,
        orderID,
        taskID,
        deliveryID,
        scheduleID,
        staffID: selectedStaff.staffID,
        staffName: selectedStaff.fullName,
        slotStart: assignedSlot.slotStart.toISOString(),
        slotEnd: assignedSlot.slotEnd.toISOString(),
        estimatedDuration: `${totalEstimatedDurationMinutes} mins`,
        estimatedDistance: `${totalEstimatedDistanceKm} km`,
        processLogs
    };
}

module.exports = {
    assignDeliveryTask,
    getEligibleDeliveryStaff,
    WORKING_HOUR_CONFIG
};
