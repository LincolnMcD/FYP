/**
 * Task Schedule Delay & Auto-Reassignment Monitor Service
 * 
 * Rules:
 * 1. For each active delivery task with scheduleDate and scheduleStartTime / scheduleEndTime:
 * 2. Start Time Delay Check:
 *    - If staff has NOT clicked "Start Delivery" (task still 'Packaging' or schedule still 'assigned')
 *      at or after scheduleStartTime:
 *      - Delay current task scheduleStartTime and scheduleEndTime by 10 minutes.
 *      - Delay all following tasks of that staff on that day by 10 minutes (start and end times).
 *      - Increment handled staff's `mistake` attribute in users collection by +1.
 *      - Increment delayCount on schedule.
 *      - After 10 min, if still not started, repeat delay (+10 min) and mistake +1.
 *      - If delay occurs 3 times (30 min delay total):
 *        * handled staff gets mistake +3 total
 *        * Mark current scheduleStatus as 'absent'
 *        * Automatically reassign the task to another eligible delivery staff in the same state
 *          following the exact same assignment algorithm.
 * 
 * 3. End Time Delay Check:
 *    - If task has started ('Shipping' / 'ongoing') but at or after scheduleEndTime staff has NOT clicked
 *      "Complete Delivery" (task is still not 'Delivered' / 'Completed'):
 *      - Delay current task scheduleEndTime by 15 minutes.
 *      - Delay following tasks on that day by 15 minutes (start and end times).
 *      - Increment handled staff's `mistake` attribute by +1.
 *      - If occurs 3 times (45 min delay total):
 *        * handled staff gets mistake +3 total
 *        * Mark current scheduleStatus as 'absent'
 *        * Automatically reassign the task to another eligible delivery staff in the same state.
 * 
 * Architecture:
 * - Event-driven exact-time setTimeout timers + startup recovery scanner
 * - Lightweight periodic health-check interval (runs every 60s) to catch any drift or missed timers.
 */

const db = require("../config/firebase");
const { FieldValue } = require("firebase-admin/firestore");
const { assignDeliveryTask } = require("./taskAssignmentService");

// Map of scheduled timers in memory: scheduleID -> { startTimer, endTimer }
const activeScheduleTimers = new Map();

// Configurable Delay Intervals
const START_DELAY_MINS = 10; // Default production: 10
const END_DELAY_MINS = 15;   // Default production: 15

/**
 * Format Date to HH:mm string
 */
function formatTime(d) {
    return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}

/**
 * Add minutes to "HH:mm" string and return updated "HH:mm" string
 */
function addMinutesToTimeString(timeStr, minsToAdd) {
    if (!timeStr) return "09:00";
    const parts = timeStr.split(":");
    const h = parseInt(parts[0], 10) || 0;
    const m = parseInt(parts[1], 10) || 0;
    const totalMins = h * 60 + m + minsToAdd;
    const newH = Math.floor(totalMins / 60) % 24;
    const newM = totalMins % 60;
    return `${String(newH).padStart(2, "0")}:${String(newM).padStart(2, "0")}`;
}

/**
 * Parse a date and time string into a valid Date object
 */
function parseScheduleDateTime(dateStr, timeStr) {
    if (!dateStr || !timeStr) return null;
    const dParts = dateStr.split("-");
    if (dParts.length < 3) return null;
    const year = parseInt(dParts[0], 10);
    const month = parseInt(dParts[1], 10) - 1;
    const day = parseInt(dParts[2], 10);

    const tParts = timeStr.split(":");
    const hours = parseInt(tParts[0], 10) || 0;
    const minutes = parseInt(tParts[1], 10) || 0;

    return new Date(year, month, day, hours, minutes, 0);
}

/**
 * Check and reset monthly mistakes for all staff on the 1st of each month.
 * Also stores `mistakeResetMonth` ("YYYY-MM") in system_config or on user doc.
 */
async function checkAndResetMonthlyMistakes(force = false) {
    try {
        const now = new Date();
        const currentMonthKey = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
        const isFirstDay = now.getDate() === 1;

        if (!isFirstDay && !force) {
            return;
        }

        const configRef = db.collection("system_config").doc("staff_mistakes");
        const configSnap = await configRef.get();
        const lastResetMonth = configSnap.exists ? configSnap.data().lastResetMonth : null;

        if (lastResetMonth === currentMonthKey && !force) {
            return; // Already reset for this month
        }

        console.log(`[MONTHLY RESET] 1st of month reached (${currentMonthKey}). Resetting all staff mistakes to 0...`);
        const staffSnap = await db.collection("users")
            .where("role", "in", ["Staff", "staff", "admin", "Admin"])
            .get();

        const batch = db.batch();
        let count = 0;
        for (const doc of staffSnap.docs) {
            const data = doc.data();
            if (Number(data.mistake || 0) > 0) {
                batch.update(doc.ref, {
                    mistake: 0,
                    mistakeResetMonth: currentMonthKey,
                    lastMistakeResetAt: new Date(),
                    updatedAt: new Date()
                });
                count++;
            }
        }

        if (count > 0) {
            await batch.commit();
            console.log(`[MONTHLY RESET] Successfully reset mistakes for ${count} staff members to 0.`);
        }

        await configRef.set({
            lastResetMonth: currentMonthKey,
            lastResetAt: new Date(),
            updatedAt: new Date()
        }, { merge: true });

    } catch (err) {
        console.error("[MONTHLY RESET ERROR] Failed to reset staff mistakes:", err);
    }
}

/**
 * Increment mistake counter for a staff member in 'users' collection.
 * Automatically verifies if the staff's mistakes need a month rollover first.
 */
async function incrementStaffMistake(staffID, count = 1) {
    if (!staffID) return;
    try {
        const now = new Date();
        const currentMonthKey = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;

        const staffRef = db.collection("users").doc(staffID);
        const snap = await staffRef.get();
        if (snap.exists) {
            const sData = snap.data();
            const staffResetMonth = sData.mistakeResetMonth || null;
            let currentMistakes = Number(sData.mistake || 0);

            // If staff has mistakes from a prior month and hasn't been reset yet, start from 0 for the new month
            if (staffResetMonth && staffResetMonth !== currentMonthKey) {
                currentMistakes = 0;
            }

            await staffRef.set({
                mistake: currentMistakes + count,
                mistakeResetMonth: currentMonthKey,
                updatedAt: new Date()
            }, { merge: true });
            console.log(`[STAFF MISTAKE] Staff [${staffID}] mistake count incremented by +${count} (New Total: ${currentMistakes + count}) for ${currentMonthKey}`);
        }
    } catch (err) {
        console.error(`[STAFF MISTAKE ERROR] Failed to increment mistake for ${staffID}:`, err);
    }
}

/**
 * Delay all following tasks of a staff member on the given date by specified minutes
 */
async function delayFollowingTasks(staffID, scheduleDate, cutoffStartTimeStr, minsToAdd, currentScheduleID) {
    if (!staffID || !scheduleDate) return;
    try {
        const schedSnap = await db.collection("schedule")
            .where("staffID", "==", staffID)
            .where("scheduleDate", "==", scheduleDate)
            .get();

        const cutoffMins = (parseInt(cutoffStartTimeStr.split(":")[0], 10) * 60) + parseInt(cutoffStartTimeStr.split(":")[1], 10);

        for (const sDoc of schedSnap.docs) {
            if (sDoc.id === currentScheduleID) continue; // Skip current task (already delayed)
            const sData = sDoc.data();
            // Delivery Delay Monitor ONLY affects delivery tasks (never alter inspection/collection appointments)
            if (!sData.orderID) continue;

            const status = String(sData.scheduleStatus || "").toLowerCase();
            if (status === "completed" || status === "rejected" || status === "absent" || status === "cancelled") {
                continue;
            }

            const sTimeStr = sData.scheduleStartTime || "00:00";
            const sParts = sTimeStr.split(":");
            const taskStartMins = (parseInt(sParts[0], 10) * 60) + parseInt(sParts[1], 10);

            // If task is scheduled at or after cutoff, delay it
            if (taskStartMins >= cutoffMins) {
                const newStart = addMinutesToTimeString(sData.scheduleStartTime, minsToAdd);
                const newEnd = addMinutesToTimeString(sData.scheduleEndTime, minsToAdd);

                await sDoc.ref.set({
                    scheduleStartTime: newStart,
                    scheduleEndTime: newEnd,
                    updatedAt: new Date()
                }, { merge: true });

                // Synchronize task document taskStartTime
                if (sData.orderID) {
                    await db.collection("task").doc(`TSK-${sData.orderID}`).set({
                        taskStartTime: newStart,
                        updatedAt: new Date()
                    }, { merge: true }).catch(() => {});
                }

                console.log(`[FOLLOWING TASK DELAYED] Staff [${staffID}] Task [${sDoc.id}] delayed by ${minsToAdd}m -> New Time: ${newStart} - ${newEnd}`);
                // Re-register timers for the shifted following task
                await registerScheduleTimer(sDoc.id);
            }
        }
    } catch (err) {
        console.error(`[DELAY FOLLOWING ERROR]`, err);
    }
}

/**
 * Handle Start Time Violation:
 * If staff didn't click start delivery at or before start time:
 * - delay current task by 10 min
 * - delay following tasks by 10 min
 * - staff mistake +1
 * - if 3rd time: scheduleStatus = 'absent', reassign to another staff 1 by 1
 */
// Track schedules currently being processed to avoid duplicate concurrent triggers
const processingSchedules = new Set();
let scheduleViolationQueue = Promise.resolve();

function enqueueScheduleViolation(work) {
    const queuedWork = scheduleViolationQueue.catch(() => {}).then(work);
    scheduleViolationQueue = queuedWork.catch((err) => {
        console.error("[SCHEDULE VIOLATION QUEUE ERROR] Delay processing failed:", err);
    });
    return queuedWork;
}

// Serialize automatic absent-task reassignments in arrival order. Each assignment
// must finish writing its schedule before the next one calculates availability.
let deliveryReassignmentQueue = Promise.resolve();

function enqueueDeliveryReassignment(assignmentOptions) {
    const queuedAssignment = deliveryReassignmentQueue.then(async () => {
        const result = await assignDeliveryTask(assignmentOptions);
        if (result && result.scheduleID) {
            await registerScheduleTimer(result.scheduleID);
        }
        return result;
    });

    // Keep the queue usable if one assignment unexpectedly rejects, while still
    // returning that rejection to the handler that submitted this assignment.
    deliveryReassignmentQueue = queuedAssignment.catch((err) => {
        console.error("[AUTO-REASSIGN QUEUE ERROR] Delivery reassignment failed:", err);
    });

    return queuedAssignment;
}

function handleStartTimeViolation(scheduleID) {
    return enqueueScheduleViolation(() => processStartTimeViolation(scheduleID));
}

async function processStartTimeViolation(scheduleID) {
    if (processingSchedules.has(`start_${scheduleID}`)) return;
    processingSchedules.add(`start_${scheduleID}`);

    try {
        const schedRef = db.collection("schedule").doc(scheduleID);
        const schedSnap = await schedRef.get();
        if (!schedSnap.exists) return;

        const sData = schedSnap.data();
        // Delivery Delay Monitor ONLY applies to delivery tasks with orderID
        if (!sData.orderID) return;

        const schedStatus = String(sData.scheduleStatus || "").toLowerCase();
        // If already started, completed, rejected, or absent, do nothing
        if (schedStatus === "ongoing" || schedStatus === "completed" || schedStatus === "rejected" || schedStatus === "absent" || schedStatus === "cancelled") {
            return;
        }

        const scheduledStart = parseScheduleDateTime(sData.scheduleDate, sData.scheduleStartTime);
        if (scheduledStart && Date.now() < scheduledStart.getTime()) {
            console.log(`[START TIME CHECK SKIPPED] Schedule [${scheduleID}] was moved to ${sData.scheduleStartTime}; its new start time has not arrived.`);
            return;
        }

        // COOLDOWN CHECK: If this schedule was already delayed recently, do not trigger again until the delay interval has passed!
        const nowMs = Date.now();
        if (sData.lastDelayedAt) {
            const lastDelayedMs = sData.lastDelayedAt.toDate ? sData.lastDelayedAt.toDate().getTime() : new Date(sData.lastDelayedAt).getTime();
            const minIntervalMs = (START_DELAY_MINS * 60 * 1000) - 5000; // allow 5s buffer
            if (nowMs - lastDelayedMs < minIntervalMs) {
                console.log(`[START TIME VIOLATION SKIPPED] Schedule [${scheduleID}] was already delayed ${Math.round((nowMs - lastDelayedMs) / 1000)}s ago. Waiting for cooldown.`);
                return;
            }
        }

        const taskID = `TSK-${sData.orderID}`;
        const taskSnap = await db.collection("task").doc(taskID).get();
        if (taskSnap.exists) {
            const tStatus = String(taskSnap.data().taskStatus || "").toLowerCase();
            if (tStatus === "shipping" || tStatus === "delivered" || tStatus === "completed") {
                return;
            }
        }

        const currentStartDelays = Number(sData.startDelayCount || 0) + 1;
        const staffID = sData.staffID;
        const orderID = sData.orderID;

        // If it already completed 3 delays, this 4th check means staff still didn't start delivery after 3 delays -> absent & reassign 1 by 1
        if (currentStartDelays > 3) {
            console.log(`[START TIME VIOLATION] Schedule [${scheduleID}] staff [${staffID}] still not started after 3 delays. Marking absent and reassigning Order #${orderID} 1 by 1 to next day...`);

            // Mark schedule record as absent
            await schedRef.set({
                scheduleStatus: "absent",
                startDelayCount: currentStartDelays,
                absentReason: "Staff did not start delivery after 3 consecutive delays",
                absentAt: new Date(),
                updatedAt: new Date()
            }, { merge: true });

            // Clear timers for this schedule
            clearScheduleTimers(scheduleID);

            // Reassign ONLY this task 1 by 1 to another eligible delivery staff on the NEXT day
            const reassignResult = await enqueueDeliveryReassignment({
                orderID,
                requestedDate: sData.scheduleDate ? new Date(sData.scheduleDate) : new Date(),
                forceNextDay: true,
                excludeStaffIDs: [staffID]
            });

            console.log(`[AUTO-REASSIGN RESULT] Order #${orderID} reassign result:`, reassignResult.message || reassignResult.reason || "Done");
        } else {
            console.log(`[START TIME VIOLATION] Schedule [${scheduleID}] staff [${staffID}] did not start on time. Delay count: ${currentStartDelays}/3`);

            // Add 1 mistake to handled staff record for each of the 3 delays
            await incrementStaffMistake(staffID, 1);

            // Delay current task by START_DELAY_MINS minutes
            const oldStartTime = sData.scheduleStartTime || "09:00";
            const newStartTime = addMinutesToTimeString(oldStartTime, START_DELAY_MINS);
            const newEndTime = addMinutesToTimeString(sData.scheduleEndTime || oldStartTime, START_DELAY_MINS);

            await schedRef.set({
                scheduleStartTime: newStartTime,
                scheduleEndTime: newEndTime,
                startDelayCount: currentStartDelays,
                lastDelayedAt: new Date(),
                updatedAt: new Date()
            }, { merge: true });

            // Update task document start time
            await db.collection("task").doc(taskID).set({
                taskStartTime: newStartTime,
                updatedAt: new Date()
            }, { merge: true }).catch(() => {});

            console.log(`[SCHEDULE DELAYED +${START_DELAY_MINS}m] Schedule [${scheduleID}] shifted to ${newStartTime} - ${newEndTime}`);

            // Delay following tasks of this staff by START_DELAY_MINS minutes
            await delayFollowingTasks(staffID, sData.scheduleDate, oldStartTime, START_DELAY_MINS, scheduleID);

            // Schedule the next check after START_DELAY_MINS minutes
            scheduleExactTimer(`start_${scheduleID}_delay_${currentStartDelays}`, START_DELAY_MINS * 60 * 1000, () => {
                handleStartTimeViolation(scheduleID);
            });
        }
    } catch (err) {
        console.error(`[START TIME VIOLATION ERROR]`, err);
    } finally {
        processingSchedules.delete(`start_${scheduleID}`);
    }
}

/**
 * Handle End Time Violation:
 * If task has started but staff didn't complete delivery at or before end time:
 * - delay current task end time by 15 min
 * - delay following tasks start & end by 15 min
 * - staff mistake +1
 * - if 3rd time: scheduleStatus = 'absent', reassign to another staff
 */
function handleEndTimeViolation(scheduleID) {
    return enqueueScheduleViolation(() => processEndTimeViolation(scheduleID));
}

async function processEndTimeViolation(scheduleID) {
    if (processingSchedules.has(`end_${scheduleID}`)) return;
    processingSchedules.add(`end_${scheduleID}`);

    try {
        const schedRef = db.collection("schedule").doc(scheduleID);
        const schedSnap = await schedRef.get();
        if (!schedSnap.exists) return;

        const sData = schedSnap.data();
        // Delivery Delay Monitor ONLY applies to delivery tasks with orderID
        if (!sData.orderID) return;

        const schedStatus = String(sData.scheduleStatus || "").toLowerCase();
        // If already completed, rejected, or absent, do nothing
        if (schedStatus !== "ongoing") {
            return;
        }

        const scheduledEnd = parseScheduleDateTime(sData.scheduleDate, sData.scheduleEndTime);
        if (scheduledEnd && Date.now() < scheduledEnd.getTime()) {
            console.log(`[END TIME CHECK SKIPPED] Schedule [${scheduleID}] was moved to ${sData.scheduleEndTime}; its new end time has not arrived.`);
            return;
        }

        // COOLDOWN CHECK: If this schedule's end time was already delayed recently, wait for cooldown!
        const nowMs = Date.now();
        if (sData.lastEndDelayedAt) {
            const lastDelayedMs = sData.lastEndDelayedAt.toDate ? sData.lastEndDelayedAt.toDate().getTime() : new Date(sData.lastEndDelayedAt).getTime();
            const minIntervalMs = (END_DELAY_MINS * 60 * 1000) - 5000; // allow 5s buffer
            if (nowMs - lastDelayedMs < minIntervalMs) {
                console.log(`[END TIME VIOLATION SKIPPED] Schedule [${scheduleID}] was already delayed ${Math.round((nowMs - lastDelayedMs) / 1000)}s ago. Waiting for cooldown.`);
                return;
            }
        }

        const taskID = `TSK-${sData.orderID}`;
        const taskSnap = await db.collection("task").doc(taskID).get();
        if (taskSnap.exists) {
            const tStatus = String(taskSnap.data().taskStatus || "").toLowerCase();
            if (tStatus === "delivered" || tStatus === "completed") {
                return;
            }
        }

        const currentEndDelays = Number(sData.endDelayCount || 0) + 1;
        const staffID = sData.staffID;
        const orderID = sData.orderID;

        // If it already completed 3 delays, this 4th check means staff still hasn't completed delivery after 3 delays -> absent & reassign 1 by 1
        if (currentEndDelays > 3) {
            console.log(`[END TIME VIOLATION] Schedule [${scheduleID}] delivery still not completed after 3 delays. Marking absent and reassigning Order #${orderID} 1 by 1 to next day...`);

            // Mark schedule record as absent
            await schedRef.set({
                scheduleStatus: "absent",
                endDelayCount: currentEndDelays,
                absentReason: "Staff did not complete delivery after 3 consecutive delays",
                absentAt: new Date(),
                updatedAt: new Date()
            }, { merge: true });

            clearScheduleTimers(scheduleID);

            // Reassign ONLY this task 1 by 1 to another eligible delivery staff on the NEXT day
            const reassignResult = await enqueueDeliveryReassignment({
                orderID,
                requestedDate: sData.scheduleDate ? new Date(sData.scheduleDate) : new Date(),
                forceNextDay: true,
                excludeStaffIDs: [staffID]
            });

            console.log(`[AUTO-REASSIGN RESULT] Order #${orderID} reassign result:`, reassignResult.message || reassignResult.reason || "Done");
        } else {
            console.log(`[END TIME VIOLATION] Schedule [${scheduleID}] delivery not completed on time. Delay count: ${currentEndDelays}/3`);

            // Add 1 mistake to handled staff record for each of the 3 delays
            await incrementStaffMistake(staffID, 1);

            // Delay current task end time by END_DELAY_MINS minutes
            const oldEndTime = sData.scheduleEndTime || "10:00";
            const newEndTime = addMinutesToTimeString(oldEndTime, END_DELAY_MINS);

            await schedRef.set({
                scheduleEndTime: newEndTime,
                endDelayCount: currentEndDelays,
                lastEndDelayedAt: new Date(),
                updatedAt: new Date()
            }, { merge: true });

            console.log(`[SCHEDULE END TIME DELAYED +${END_DELAY_MINS}m] Schedule [${scheduleID}] end time extended to ${newEndTime}`);

            // Delay following tasks of this staff by END_DELAY_MINS minutes
            await delayFollowingTasks(staffID, sData.scheduleDate, oldEndTime, END_DELAY_MINS, scheduleID);

            // Schedule the next check after END_DELAY_MINS minutes
            scheduleExactTimer(`end_${scheduleID}_delay_${currentEndDelays}`, END_DELAY_MINS * 60 * 1000, () => {
                handleEndTimeViolation(scheduleID);
            });
        }
    } catch (err) {
        console.error(`[END TIME VIOLATION ERROR]`, err);
    } finally {
        processingSchedules.delete(`end_${scheduleID}`);
    }
}

/**
 * Schedule a timer with maximum safe setTimeout duration (up to 24 hours)
 */
function scheduleExactTimer(key, delayMs, callback) {
    if (delayMs <= 0) {
        setImmediate(callback);
        return null;
    }
    // Node.js setTimeout max is ~24.8 days (2147483647 ms)
    const safeMs = Math.min(delayMs, 2147483647);
    const timer = setTimeout(callback, safeMs);
    return timer;
}

/**
 * Register event-driven timers for a schedule document based on scheduledStartTime & scheduledEndTime
 */
async function registerScheduleTimer(scheduleID) {
    if (!scheduleID) return;
    try {
        const sDoc = await db.collection("schedule").doc(scheduleID).get();
        if (!sDoc.exists) return;
        const sData = sDoc.data();
        // Delivery Delay Monitor ONLY applies to delivery schedules with an orderID!
        if (!sData.orderID) return;

        const schedStatus = String(sData.scheduleStatus || "").toLowerCase();

        // Only monitor active schedules
        if (schedStatus !== "assigned" && schedStatus !== "ongoing") {
            clearScheduleTimers(scheduleID);
            return;
        }

        const dateStr = sData.scheduleDate;
        const startTimeStr = sData.scheduleStartTime;
        const endTimeStr = sData.scheduleEndTime;

        if (!dateStr || !startTimeStr) return;

        const startDateTime = parseScheduleDateTime(dateStr, startTimeStr);
        const endDateTime = endTimeStr ? parseScheduleDateTime(dateStr, endTimeStr) : null;
        const now = Date.now();

        // Clear existing timers for this schedule
        clearScheduleTimers(scheduleID);

        const timersObj = {};

        // 1. Timer for Start Time Check (only if still in 'assigned' status)
        if (schedStatus === "assigned" && startDateTime) {
            const diffStartMs = startDateTime.getTime() - now;
            if (diffStartMs <= 0) {
                // Already past start time! Trigger check immediately
                setImmediate(() => handleStartTimeViolation(scheduleID));
            } else {
                console.log(`[TIMER REGISTERED] Schedule [${scheduleID}] start timer set for ${diffStartMs}ms from now (${startDateTime.toLocaleTimeString()})`);
                timersObj.startTimer = setTimeout(() => {
                    handleStartTimeViolation(scheduleID);
                }, diffStartMs);
            }
        }

        // 2. Timer for End Time Check
        if (endDateTime) {
            const diffEndMs = endDateTime.getTime() - now;
            if (diffEndMs <= 0) {
                // If it is past end time and in 'ongoing' or 'assigned' status
                if (schedStatus === "ongoing") {
                    setImmediate(() => handleEndTimeViolation(scheduleID));
                }
            } else {
                console.log(`[TIMER REGISTERED] Schedule [${scheduleID}] end timer set for ${diffEndMs}ms from now (${endDateTime.toLocaleTimeString()})`);
                timersObj.endTimer = setTimeout(() => {
                    handleEndTimeViolation(scheduleID);
                }, diffEndMs);
            }
        }

        activeScheduleTimers.set(scheduleID, timersObj);
    } catch (err) {
        console.error(`[REGISTER TIMER ERROR] Schedule ${scheduleID}:`, err);
    }
}

/**
 * Clear timers for a schedule
 */
function clearScheduleTimers(scheduleID) {
    if (activeScheduleTimers.has(scheduleID)) {
        const { startTimer, endTimer } = activeScheduleTimers.get(scheduleID);
        if (startTimer) clearTimeout(startTimer);
        if (endTimer) clearTimeout(endTimer);
        activeScheduleTimers.delete(scheduleID);
    }
}

/**
 * Startup Recovery Scanner:
/**
 * Helper to check if a schedule or appointment date is strictly before today (reached 00:00 next day)
 */
function isDateBeforeToday(dateVal) {
    if (!dateVal) return false;
    let dStr = "";
    if (typeof dateVal === "string") {
        let s = dateVal.trim();
        if (s.includes("T")) s = s.split("T")[0];
        if (s.includes("/")) {
            const parts = s.split("/");
            if (parts.length === 3) {
                if (parts[0].length === 4) {
                    dStr = `${parts[0]}-${parts[1].padStart(2, "0")}-${parts[2].padStart(2, "0")}`;
                } else {
                    dStr = `${parts[2]}-${parts[1].padStart(2, "0")}-${parts[0].padStart(2, "0")}`;
                }
            }
        } else if (s.includes("-")) {
            const parts = s.split("-");
            if (parts.length === 3) {
                if (parts[0].length === 4) {
                    dStr = `${parts[0]}-${parts[1].padStart(2, "0")}-${parts[2].padStart(2, "0")}`;
                } else {
                    dStr = `${parts[2]}-${parts[1].padStart(2, "0")}-${parts[0].padStart(2, "0")}`;
                }
            }
        }
    } else {
        let d = null;
        if (dateVal.toDate && typeof dateVal.toDate === "function") d = dateVal.toDate();
        else if (dateVal._seconds) d = new Date(dateVal._seconds * 1000);
        else if (dateVal instanceof Date) d = dateVal;
        if (d && !isNaN(d.getTime())) {
            const y = d.getFullYear();
            const m = String(d.getMonth() + 1).padStart(2, "0");
            const day = String(d.getDate()).padStart(2, "0");
            dStr = `${y}-${m}-${day}`;
        }
    }

    if (!dStr || dStr.length < 10) return false;

    // Use current local date YYYY-MM-DD
    const now = new Date();
    const todayStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;

    return dStr < todayStr;
}

const overdueTradeInTypes = ["inspect", "collect", "inspection", "collection",
    "Inspect", "Collect", "Inspection", "Collection"];

function canCancelOverdueRecord(data) {
    const protectedStatuses = /^(completed?|inspecting|inspected|paid|accepted|collected|done|cancelled|canceled|declined|rejected)$/i;
    return !["taskStatus", "requestStatus", "appointmentStatus", "scheduleStatus",
        "bookingStatus", "status"].some(field => protectedStatuses.test(String(data[field] || "").trim()))
        && data.isPaid !== true;
}

/** Cancel unfinished trade-in bookings once their scheduled calendar date has passed. */
async function autoResolveOverdueTradeInTasks() {
    try {
        const [requests, appointments, tasks, schedules] = await Promise.all([
            db.collection("tradeInRequests").get(),
            db.collection("tradeInAppointment").get(),
            db.collection("task").where("taskType", "in", overdueTradeInTypes).get(),
            db.collection("schedule").where("scheduleStatus", "in", ["assigned", "ongoing"]).get()
        ]);
        const bookings = new Map();
        const appointmentKeys = new Map();
        const scheduleKeys = new Map();
        const keyForRequest = id => `request:${String(id).replace(/^#/, "")}`;
        const booking = key => {
            if (!bookings.has(key)) bookings.set(key, []);
            return bookings.get(key);
        };
        const add = (key, kind, doc) => {
            const data = doc.data();
            booking(key).push({ kind, doc });
            if (data.scheduleID) scheduleKeys.set(data.scheduleID, key);
        };
        for (const doc of requests.docs) {
            const key = keyForRequest(doc.id);
            add(key, "request", doc);
            if (doc.data().appointmentID) appointmentKeys.set(doc.data().appointmentID, key);
        }
        for (const doc of appointments.docs) {
            const data = doc.data();
            const key = data.tradeInRequestID ? keyForRequest(data.tradeInRequestID)
                : appointmentKeys.get(doc.id) || `appointment:${doc.id}`;
            appointmentKeys.set(doc.id, key);
            add(key, "appointment", doc);
        }
        for (const doc of tasks.docs) {
            const data = doc.data();
            const key = appointmentKeys.get(data.appointmentID)
                || (data.tradeInRequestID && keyForRequest(data.tradeInRequestID))
                || (data.appointmentID && `appointment:${data.appointmentID}`)
                || `task:${doc.id}`;
            add(key, "task", doc);
        }
        for (const doc of schedules.docs) {
            const data = doc.data();
            if (data.orderID) continue;
            const key = scheduleKeys.get(doc.id) || appointmentKeys.get(data.appointmentID)
                || (data.tradeInRequestID && keyForRequest(data.tradeInRequestID));
            if (key) add(key, "schedule", doc);
        }

        for (const records of bookings.values()) {
            const dateOf = (record, data) => record.kind === "schedule" || record.kind === "task"
                ? data.scheduleDate || data.scheduledAt
                : data.appointmentDate || data.scheduledAt;
            const dates = records.map(record => dateOf(record, record.doc.data())).filter(Boolean);
            if (!dates.length || !dates.every(isDateBeforeToday) ||
                records.some(record => !canCancelOverdueRecord(record.doc.data()))) continue;

            const cancelledSchedules = await db.runTransaction(async transaction => {
                const snapshots = await Promise.all(records.map(record => transaction.get(record.doc.ref)));
                if (snapshots.some(doc => !doc.exists || !canCancelOverdueRecord(doc.data()))) return [];
                const currentDates = snapshots.map((doc, index) => dateOf(records[index], doc.data())).filter(Boolean);
                if (!currentDates.length || !currentDates.every(isDateBeforeToday)) return [];
                const stamp = FieldValue.serverTimestamp();
                const cancellation = { cancelledAt: stamp, updatedAt: stamp };
                const cancelledSchedules = [];
                const deviceIDs = new Set();
                for (const [index, record] of records.entries()) {
                    const data = snapshots[index].data();
                    if (data.deviceID) deviceIDs.add(data.deviceID);
                    const fields = {
                        request: { requestStatus: "Cancelled", bookingStatus: "Cancelled", status: "Cancelled",
                            cancelledBy: "System", autoTransitionAt: stamp, autoTransitionReason: "Scheduled date passed" },
                        appointment: { appointmentStatus: "Cancelled", bookingStatus: "Cancelled", status: "Cancelled" },
                        task: { taskStatus: "Cancelled", status: "Cancelled" },
                        schedule: { scheduleStatus: "cancelled" }
                    };
                    transaction.update(record.doc.ref, { ...fields[record.kind], ...cancellation });
                    if (record.kind === "schedule") cancelledSchedules.push(record.doc.id);
                }
                for (const deviceID of deviceIDs) {
                    transaction.set(db.collection("devices").doc(deviceID), {
                        status: "cancelled", deviceStatus: "cancelled", updatedAt: stamp
                    }, { merge: true });
                }
                return cancelledSchedules;
            });
            for (const scheduleID of cancelledSchedules) clearScheduleTimers(scheduleID);
        }
    } catch (err) {
        console.error("[AUTO-RESOLVE OVERDUE TRADE-IN ERROR]:", err);
    }
}

/**
 * Startup Recovery & Ongoing Scanner
 * Runs when backend starts or recovers to scan all active schedules and set up timers
 */
async function initializeScheduleMonitoring() {
    console.log(`\n================================================================================`);
    console.log(`[SCHEDULE MONITOR] Initializing event-driven delay & auto-reassign monitor...`);
    try {
        const schedSnap = await db.collection("schedule")
            .where("scheduleStatus", "in", ["assigned", "ongoing"])
            .get();

        console.log(`[SCHEDULE MONITOR] Found ${schedSnap.size} active delivery schedules to monitor.`);

        const activeSchedules = [...schedSnap.docs].sort((a, b) => {
            const aData = a.data();
            const bData = b.data();
            const aKey = `${aData.scheduleDate || ""} ${aData.scheduleStartTime || ""}`;
            const bKey = `${bData.scheduleDate || ""} ${bData.scheduleStartTime || ""}`;
            return aKey.localeCompare(bKey);
        });

        for (const sDoc of activeSchedules) {
            const sData = sDoc.data();
            // Only delivery schedules have orderID and participate in delivery delay monitoring
            if (sData.orderID) {
                await registerScheduleTimer(sDoc.id);
            }
        }

        // Check if 1st of month reset is due on startup
        await checkAndResetMonthlyMistakes();

        // Check and auto-resolve any overdue trade-in tasks on startup
        await autoResolveOverdueTradeInTasks();

        // Also run a lightweight periodic sweep every 60 seconds as a safety net
        // to catch any drift, network pauses, or missed scheduled timers without heavy queries
        setInterval(async () => {
            try {
                // Check 1st of month rollover
                await checkAndResetMonthlyMistakes();

                // Auto-resolve overdue trade-in tasks (inspect/collect) that passed their scheduled date
                await autoResolveOverdueTradeInTasks();

                const activeSnap = await db.collection("schedule")
                    .where("scheduleStatus", "in", ["assigned", "ongoing"])
                    .get();

                const activeSchedules = [...activeSnap.docs].sort((a, b) => {
                    const aData = a.data();
                    const bData = b.data();
                    const aKey = `${aData.scheduleDate || ""} ${aData.scheduleStartTime || ""}`;
                    const bKey = `${bData.scheduleDate || ""} ${bData.scheduleStartTime || ""}`;
                    return aKey.localeCompare(bKey);
                });

                const now = Date.now();
                for (const doc of activeSchedules) {
                    const data = doc.data();
                    // Skip non-delivery tasks (trade-in inspection/collection)
                    if (!data.orderID) continue;

                    const sDate = data.scheduleDate;
                    const sStart = data.scheduleStartTime;
                    const sEnd = data.scheduleEndTime;
                    const sStatus = String(data.scheduleStatus || "").toLowerCase();

                    if (sDate && sStart && sStatus === "assigned") {
                        const startDt = parseScheduleDateTime(sDate, sStart);
                        if (startDt && now >= startDt.getTime()) {
                            await handleStartTimeViolation(doc.id);
                        }
                    } else if (sDate && sEnd && sStatus === "ongoing") {
                        const endDt = parseScheduleDateTime(sDate, sEnd);
                        if (endDt && now >= endDt.getTime()) {
                            await handleEndTimeViolation(doc.id);
                        }
                    }
                }
            } catch (_) {}
        }, 60000);

        console.log(`[SCHEDULE MONITOR] Initialization complete. Active monitoring running.`);
        console.log(`================================================================================\n`);
    } catch (err) {
        console.error("[SCHEDULE MONITOR INIT ERROR]:", err);
    }
}

module.exports = {
    initializeScheduleMonitoring,
    registerScheduleTimer,
    clearScheduleTimers,
    handleStartTimeViolation,
    handleEndTimeViolation,
    checkAndResetMonthlyMistakes,
    autoResolveOverdueTradeInTasks,
    isDateBeforeToday
};
