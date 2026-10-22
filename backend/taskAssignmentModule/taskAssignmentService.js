const db = require("../config/firebase");
const { FieldValue } = require("firebase-admin/firestore");
const { COMPANY_LOCATION, getOsrmRoute } = require("./osrmService");

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
    const str = String(timeVal).trim();
    if (str.includes("T") || (str.includes("-") && str.length > 8)) return new Date(str);

    // Normalize HH:mm or H:mm to two-digit HH:mm:00
    const parts = str.split(":");
    if (parts.length >= 2) {
        const hh = parts[0].padStart(2, "0");
        const mm = parts[1].padStart(2, "0");
        const ss = parts[2] ? parts[2].padStart(2, "0") : "00";
        const baseDate = dateStr || formatDateKey(new Date());
        const d = new Date(`${baseDate}T${hh}:${mm}:${ss}`);
        return isNaN(d.getTime()) ? null : d;
    }

    const baseDate = dateStr || formatDateKey(new Date());
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
 * Fetch all active delivery staff
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
        const isDeliveryRole = pos.includes("deliver") || pos.includes("both");
        if (!isDeliveryRole) continue;

        const staffID = doc.id;
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
async function assignDeliveryTask({ orderID, addressID, requestedDate, specificStaffID, excludeStaffIDs = [] }) {
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

    const now = requestedDate ? new Date(requestedDate) : new Date();
    let candidateDate = new Date(now);

    const todayCutoff = new Date(now.getFullYear(), now.getMonth(), now.getDate(), WORKING_HOUR_CONFIG.startHour, 0, 0);
    if (now >= todayCutoff) {
        candidateDate.setDate(candidateDate.getDate() + 1);
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

        const allStaffRaw = await getEligibleDeliveryStaff();
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

        // If old schedule(s) existed, delete non-rejected schedules so they do not remain on staff calendar.
        // Old rejected schedules must remain intact with status 'rejected'.
        for (const sId of matchedScheduleIDs) {
            const sDoc = await db.collection("schedule").doc(sId).get();
            if (sDoc.exists && (sDoc.data().scheduleStatus === "rejected" || sDoc.data().scheduleStatus === "absent")) {
                continue; // Preserve rejected and absent schedules
            }
            logStep(`[SCHEDULE DELETED] Deleting schedule document [${sId}] because order is Unassigned (out of state or no staff).`);
            await db.collection("schedule").doc(sId).delete().catch((err) => {
                console.error(`Failed to delete schedule ${sId}:`, err);
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

    // Delete any previous active/assigned schedule for this order so the previous staff does not keep a duplicate assignment!
    // (Preserve only schedules that have scheduleStatus === "rejected")
    for (const sId of matchedScheduleIDs) {
        if (sId === newScheduleID) continue;
        const sDoc = await db.collection("schedule").doc(sId).get();
        if (sDoc.exists && sDoc.data().scheduleStatus !== "rejected" && sDoc.data().scheduleStatus !== "absent") {
            logStep(`[OLD SCHEDULE REMOVED] Deleting superseded schedule [${sId}] for previous staff [${sDoc.data().staffID}] to avoid duplicate assignment.`);
            await db.collection("schedule").doc(sId).delete().catch((err) => {
                console.error(`Failed to delete superseded schedule ${sId}:`, err);
            });
        }
    }

    const prevOrderScheds = await db.collection("schedule").where("orderID", "==", orderID).get();
    for (const sDoc of prevOrderScheds.docs) {
        if (sDoc.id === newScheduleID) continue;
        if (sDoc.data().scheduleStatus !== "rejected" && sDoc.data().scheduleStatus !== "absent") {
            logStep(`[OLD SCHEDULE REMOVED] Deleting superseded schedule [${sDoc.id}] for previous staff [${sDoc.data().staffID}] to avoid duplicate assignment.`);
            await sDoc.ref.delete().catch(() => {});
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
        staffName: selectedStaff.fullName,
        orderID,
        rejectionReason: null,
        rejectionNotes: null,
        staffLat: FieldValue.delete(),
        staffLng: FieldValue.delete(),
        staffHeading: FieldValue.delete(),
        lastGpsUpdate: FieldValue.delete(),
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

module.exports = {
    assignDeliveryTask,
    getEligibleDeliveryStaff,
    WORKING_HOUR_CONFIG
};
