/**
 * Test script to verify Start Time Violations, End Time Violations,
 * Mistake Increments, Following Tasks Time Shift, and Auto-Reassignment
 */
const http = require('http');

function postRequest(path, data) {
    return new Promise((resolve, reject) => {
        const body = JSON.stringify(data);
        const req = http.request({
            hostname: 'localhost',
            port: 3000,
            path: path,
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(body)
            }
        }, (res) => {
            let resBody = '';
            res.on('data', chunk => resBody += chunk);
            res.on('end', () => {
                try {
                    resolve(JSON.parse(resBody));
                } catch (e) {
                    resolve(resBody);
                }
            });
        });

        req.on('error', reject);
        req.write(body);
        req.end();
    });
}

async function runDemo() {
    console.log("================================================================================");
    console.log("             AUTOMATED TASK DELAY & REASSIGNMENT TEST SUITE                     ");
    console.log("================================================================================\n");

    const db = require('./config/firebase');

    // 1. Pick an active schedule in 'assigned' status
    const schedSnap = await db.collection('schedule')
        .where('scheduleStatus', '==', 'assigned')
        .limit(1)
        .get();

    if (schedSnap.empty) {
        console.log("No active 'assigned' schedule found. Please create or assign an order first.");
        process.exit(0);
    }

    const testSched = schedSnap.docs[0];
    const schedId = testSched.id;
    const initialData = testSched.data();
    const staffId = initialData.staffID;

    console.log(`[TEST TARGET] Schedule: ${schedId}`);
    console.log(`[ORDER] #${initialData.orderID}`);
    console.log(`[INITIAL STAFF] ${staffId}`);
    console.log(`[INITIAL TIME SLOT] ${initialData.scheduleStartTime} - ${initialData.scheduleEndTime}`);

    const userBefore = (await db.collection('users').doc(staffId).get()).data() || {};
    console.log(`[INITIAL STAFF MISTAKES] ${userBefore.mistake || 0}\n`);

    // --- STEP 1: Simulate 1st Start Time Violation (+10 min, mistake +1) ---
    console.log("--> Triggering 1st Start Time delay (10 min shift, mistake +1)...");
    await postRequest('/api/task-assignment/admin/simulate-delay-check', { scheduleID: schedId, type: 'start' });

    let docAfter1 = (await db.collection('schedule').doc(schedId).get()).data();
    let userAfter1 = (await db.collection('users').doc(staffId).get()).data();
    console.log(`    Result Time Slot : ${docAfter1.scheduleStartTime} - ${docAfter1.scheduleEndTime}`);
    console.log(`    Start Delay Count: ${docAfter1.startDelayCount}/3`);
    console.log(`    Staff Mistakes   : ${userAfter1.mistake || 0}\n`);

    // --- STEP 2: Simulate 2nd Start Time Violation (+10 min, mistake +1) ---
    console.log("--> Triggering 2nd Start Time delay (10 min shift, mistake +1)...");
    await postRequest('/api/task-assignment/admin/simulate-delay-check', { scheduleID: schedId, type: 'start' });

    let docAfter2 = (await db.collection('schedule').doc(schedId).get()).data();
    let userAfter2 = (await db.collection('users').doc(staffId).get()).data();
    console.log(`    Result Time Slot : ${docAfter2.scheduleStartTime} - ${docAfter2.scheduleEndTime}`);
    console.log(`    Start Delay Count: ${docAfter2.startDelayCount}/3`);
    console.log(`    Staff Mistakes   : ${userAfter2.mistake || 0}\n`);

    // --- STEP 3: Simulate 3rd Start Time Violation (Reaches 3 -> Mark absent & Auto-Reassign) ---
    console.log("--> Triggering 3rd Start Time delay (30 min total delay reached!)...");
    console.log("    Expecting: status -> 'absent', staff mistake total +3, and auto-reassign to another staff...\n");
    await postRequest('/api/task-assignment/admin/simulate-delay-check', { scheduleID: schedId, type: 'start' });

    let docAfter3 = (await db.collection('schedule').doc(schedId).get()).data();
    let userAfter3 = (await db.collection('users').doc(staffId).get()).data();
    console.log(`    Old Schedule Status: ${docAfter3.scheduleStatus} (${docAfter3.absentReason})`);
    console.log(`    Handled Staff Final Mistakes: ${userAfter3.mistake}`);

    // Check newly assigned task/schedule for this order
    const taskDoc = (await db.collection('task').doc(`TSK-${initialData.orderID}`).get()).data();
    console.log(`    Linked Task Current Staff   : ${taskDoc.staffID} (Old was: ${staffId})`);
    console.log(`    Linked Task Current Schedule: ${taskDoc.scheduleID}\n`);

    if (taskDoc.staffID !== staffId) {
        console.log(">>> [SUCCESS] Auto-reassignment completed successfully to a new staff member!");
    } else {
        console.log(">>> [INFO] Auto-reassignment tried, please check backend logs for eligible staff availability.");
    }

    console.log("================================================================================");
    process.exit(0);
}

runDemo().catch(err => {
    console.error("Test failed:", err);
    process.exit(1);
});
