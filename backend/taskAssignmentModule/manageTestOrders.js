const db = require("../config/firebase");
const { assignDeliveryTask } = require("./taskAssignmentService");

/**
 * Manage 10 Test Order Records (Format: TEST_2110_XXXXX)
 * - 5 orders created BEFORE 9:00 AM on 21/10 (e.g. 06:30, 07:15, 07:50, 08:20, 08:45)
 * - 5 orders created AFTER 9:00 AM on 21/10 (e.g. 09:30, 11:15, 13:40, 15:10, 16:25)
 * - Linked to real existing product records in `product` collection
 * - Exact same attribute schema as real orders in Firestore
 *
 * Usage:
 *   1. Create the 10 test orders:
 *      node manageTestOrders.js create
 *
 *   2. Run assignment for a SPECIFIC order:
 *      node manageTestOrders.js assign TEST_2110_00001
 *
 *   3. Run assignment for ALL 10 test orders:
 *      node manageTestOrders.js assign-all
 *
 *   4. View all test records and their linked Task, Delivery, Schedule:
 *      node manageTestOrders.js list
 *
 *   5. Remove all 10 test records and linked Task/Delivery/Schedule:
 *      node manageTestOrders.js clean
 */

const EXISTING_PRODUCTS = [
    { id: "2610000A", price: 899.00 },
    { id: "2610000B", price: 806.50 },
    { id: "2610000C", price: 714.00 },
    { id: "2610000D", price: 521.50 },
    { id: "2610000E", price: 429.00 },
    { id: "2610000F", price: 986.50 },
    { id: "2610000G", price: 694.00 },
    { id: "2610000H", price: 651.50 },
    { id: "2610000I", price: 509.00 },
    { id: "2610000J", price: 596.50 }
];

// 5 distinct test addresses across George Town, Bayan Lepas, and Perak
const TEST_ADDRESSES = [
    { id: "TEST_ADDR_00001", name: "Pangsapuri Pelangi, George Town" },
    { id: "TEST_ADDR_00002", name: "Lorong Mahsuri 7, Bayan Baru" },
    { id: "TEST_ADDR_00003", name: "Gurney Drive, George Town" },
    { id: "TEST_ADDR_00004", name: "Queensbay Mall, Bayan Lepas" },
    { id: "TEST_ADDR_PERAK", name: "Concubine Lane, Ipoh, Perak" }
];

const CUSTOMER_ID = "f22GBPMZgNb5nPrkJm1SVH0I57l1";

// 16 Orders on 2026-10-21, distributed across the test addresses
const TEST_ORDERS_CONFIG = [
    // --- Orders BEFORE 9:00 AM on 21/10 ---
    { id: "TEST_2110_00001", time: "2026-10-21T06:30:00", prodIdx: 0, addrIdx: 0, tag: "Before 9am" }, // Pangsapuri Pelangi
    { id: "TEST_2110_00002", time: "2026-10-21T07:15:00", prodIdx: 1, addrIdx: 1, tag: "Before 9am" }, // Bayan Baru (~14 km away)
    { id: "TEST_2110_PERAK", time: "2026-10-21T07:30:00", prodIdx: 0, addrIdx: 4, tag: "Before 9am" }, // Ipoh, Perak (~164 km away)
    { id: "TEST_2110_00003", time: "2026-10-21T07:50:00", prodIdx: 2, addrIdx: 2, tag: "Before 9am" }, // Gurney Drive (~5 km away)
    { id: "TEST_2110_00004", time: "2026-10-21T08:20:00", prodIdx: 3, addrIdx: 3, tag: "Before 9am" }, // Queensbay Mall (~12 km away)
    { id: "TEST_2110_00005", time: "2026-10-21T08:45:00", prodIdx: 4, addrIdx: 0, tag: "Before 9am" }, // Pangsapuri Pelangi (< 500m to Order 1)

    // --- Orders AFTER 9:00 AM on 21/10 ---
    { id: "TEST_2110_00006", time: "2026-10-21T09:30:00", prodIdx: 5, addrIdx: 1, tag: "After 9am" }, // Bayan Baru
    { id: "TEST_2110_00007", time: "2026-10-21T11:15:00", prodIdx: 6, addrIdx: 2, tag: "After 9am" }, // Gurney Drive
    { id: "TEST_2110_00008", time: "2026-10-21T13:40:00", prodIdx: 7, addrIdx: 3, tag: "After 9am" }, // Queensbay Mall
    { id: "TEST_2110_00009", time: "2026-10-21T15:10:00", prodIdx: 8, addrIdx: 0, tag: "After 9am" }, // Pangsapuri Pelangi
    { id: "TEST_2110_00010", time: "2026-10-21T16:25:00", prodIdx: 9, addrIdx: 1, tag: "After 9am" }, // Bayan Baru
    { id: "TEST_2110_00011", time: "2026-10-21T17:05:00", prodIdx: 0, addrIdx: 2, tag: "After 9am" }, // Gurney Drive
    { id: "TEST_2110_00012", time: "2026-10-21T18:15:00", prodIdx: 1, addrIdx: 3, tag: "After 9am" }, // Queensbay Mall
    { id: "TEST_2110_00013", time: "2026-10-21T19:30:00", prodIdx: 2, addrIdx: 0, tag: "After 9am" }, // Pangsapuri Pelangi
    { id: "TEST_2110_00014", time: "2026-10-21T20:45:00", prodIdx: 3, addrIdx: 1, tag: "After 9am" }, // Bayan Baru
    { id: "TEST_2110_00015", time: "2026-10-21T21:50:00", prodIdx: 4, addrIdx: 2, tag: "After 9am" }  // Gurney Drive
];

async function createOrders() {
    console.log("================================================================================");
    console.log(`📦 [CREATING ${TEST_ORDERS_CONFIG.length} TEST ORDERS WITH REAL PRODUCT & SCHEMA ATTR]`);
    console.log("================================================================================\n");

    for (const item of TEST_ORDERS_CONFIG) {
        const prod = EXISTING_PRODUCTS[item.prodIdx];
        const addr = TEST_ADDRESSES[item.addrIdx];
        const orderDateObj = new Date(item.time);

        // Matches the EXACT Firestore order schema of ReByte:
        const orderDoc = {
            orderID: item.id,
            customerID: CUSTOMER_ID,
            addressID: addr.id,
            productIDs: [prod.id],
            subtotal: prod.price,
            shippingFee: 0,
            totalAmount: prod.price,
            orderStatus: "Processing",
            orderDate: orderDateObj,
            createdAt: orderDateObj,
            updatedAt: orderDateObj,
            isTestRecord: true
        };

        await db.collection("order").doc(item.id).set(orderDoc);
        console.log(`✅ [CREATED] Order: ${item.id} | Product: ${prod.id} (RM ${prod.price}) | Addr: ${addr.name} | Time: ${item.time.replace("T", " ")} (${item.tag})`);
    }

    console.log("\n================================================================================");
    console.log("🎉 All 10 test orders created successfully!");
    console.log("================================================================================");
    console.log("Next steps:");
    console.log("  • Assign a specific order:  node manageTestOrders.js assign TEST_2110_00001");
    console.log("  • Assign all 10 orders:    node manageTestOrders.js assign-all");
    console.log("  • View records status:     node manageTestOrders.js list");
    console.log("  • Clean test data:         node manageTestOrders.js clean\n");
}

async function assignSpecificOrder(orderID) {
    if (!orderID) {
        console.error("❌ Please provide an order ID (e.g. node manageTestOrders.js assign TEST_2110_00001)");
        return;
    }

    const orderDoc = await db.collection("order").doc(orderID).get();
    if (!orderDoc.exists) {
        console.error(`❌ Order ${orderID} does not exist in Firestore!`);
        return;
    }

    const oData = orderDoc.data();
    const orderDate = oData.orderDate ? (oData.orderDate.toDate ? oData.orderDate.toDate() : new Date(oData.orderDate)) : new Date();

    const formatLocalDisplay = (d) => {
        const yr = d.getFullYear();
        const mo = String(d.getMonth() + 1).padStart(2, "0");
        const da = String(d.getDate()).padStart(2, "0");
        const hr = String(d.getHours()).padStart(2, "0");
        const mi = String(d.getMinutes()).padStart(2, "0");
        const se = String(d.getSeconds()).padStart(2, "0");
        return `${yr}-${mo}-${da} ${hr}:${mi}:${se}`;
    };

    console.log(`\n🚀 Assigning task for Order: ${orderID} (Created at: ${formatLocalDisplay(orderDate)})...`);
    const result = await assignDeliveryTask({
        orderID,
        addressID: oData.addressID || ADDRESS_ID,
        requestedDate: orderDate
    });

    if (result.success) {
        console.log("\n================================================================================");
        console.log(`✅ [ASSIGNMENT SUCCESS]`);
        console.log(`• Order ID:       ${orderID}`);
        console.log(`• Assigned Staff: [${result.staffID}] ${result.staffName}`);
        console.log(`• Schedule Date:  ${result.scheduleDate}`);
        console.log(`• Scheduled Slot: ${result.scheduleStartTime} - ${result.scheduleEndTime}`);
        console.log(`• Task ID:        ${result.taskID}`);
        console.log(`• Schedule ID:    ${result.scheduleID}`);
        console.log(`• Delivery ID:    ${result.deliveryID}`);
        console.log(`• Duration:       ${result.estimatedDuration}`);
        console.log(`• Distance:       ${result.estimatedDistance}`);
        console.log("================================================================================\n");
    } else {
        console.error("❌ Task assignment failed:", result.reason);
    }
}

async function assignAllOrders() {
    console.log("================================================================================");
    console.log("🚀 [ASSIGNING ALL 10 TEST ORDERS SEQUENTIALLY]");
    console.log("================================================================================\n");

    for (const item of TEST_ORDERS_CONFIG) {
        await assignSpecificOrder(item.id);
    }
}

async function listRecords() {
    console.log("================================================================================");
    console.log("📋 [CURRENT TEST ORDERS AND LINKED RECORDS]");
    console.log("================================================================================\n");

    const ordSnap = await db.collection("order").get();
    const testOrders = [];
    ordSnap.forEach(d => {
        if (d.id.startsWith("TEST_2110_")) testOrders.push(d.data());
    });

    testOrders.sort((a, b) => a.orderID.localeCompare(b.orderID));

    if (testOrders.length === 0) {
        console.log("No test orders found. Run 'node manageTestOrders.js create' first.");
        return;
    }

    for (const ord of testOrders) {
        const orderID = ord.orderID;
        const taskSnap = await db.collection("task").doc(`TSK-${orderID}`).get();
        const delSnap = await db.collection("delivery").doc(`DEL-${orderID}`).get();
        const schedSnap = await db.collection("schedule").get();

        let schedDoc = null;
        schedSnap.forEach(s => {
            if (s.id.includes(orderID)) schedDoc = s.data();
        });

        console.log(`• Order: ${orderID} | Status: ${ord.orderStatus} | Total: RM ${ord.totalAmount}`);
        console.log(`  Product: ${ord.productIDs ? ord.productIDs.join(", ") : "N/A"}`);
        if (taskSnap.exists && schedDoc) {
            console.log(`  Task: ${taskSnap.id} | Schedule: ${schedDoc.scheduleDate} (${schedDoc.scheduleStartTime} - ${schedDoc.scheduleEndTime}) | Staff ID: ${schedDoc.staffID}`);
        } else {
            console.log("  Task/Schedule: Not yet assigned");
        }
        if (delSnap.exists) {
            console.log(`  Delivery: ${delSnap.id} | Status: ${delSnap.data().deliveryStatus} | Destination: ${delSnap.data().destinationLat}, ${delSnap.data().destinationLng}`);
        }
        console.log("--------------------------------------------------------------------------------");
    }
}

async function cleanRecords() {
    console.log("🧹 [REMOVING ALL 10 TEST ORDERS AND LINKED RECORDS]...");

    let deletedOrders = 0;
    let deletedTasks = 0;
    let deletedDeliveries = 0;
    let deletedSchedules = 0;

    for (const item of TEST_ORDERS_CONFIG) {
        const orderID = item.id;
        // Delete order
        const ordRef = db.collection("order").doc(orderID);
        const oSnap = await ordRef.get();
        if (oSnap.exists) {
            await ordRef.delete();
            deletedOrders++;
        }

        // Delete task
        const tRef = db.collection("task").doc(`TSK-${orderID}`);
        const tSnap = await tRef.get();
        if (tSnap.exists) {
            await tRef.delete();
            deletedTasks++;
        }

        // Delete delivery
        const dRef = db.collection("delivery").doc(`DEL-${orderID}`);
        const dSnap = await dRef.get();
        if (dSnap.exists) {
            await dRef.delete();
            deletedDeliveries++;
        }
    }

    // Delete schedules matching test order IDs
    const sSnap = await db.collection("schedule").get();
    for (const s of sSnap.docs) {
        if (s.id.includes("TEST_2110_")) {
            await s.ref.delete();
            deletedSchedules++;
        }
    }

    console.log(`✅ Cleanup finished: Deleted ${deletedOrders} Orders, ${deletedTasks} Tasks, ${deletedDeliveries} Deliveries, ${deletedSchedules} Schedules.`);
}

async function unassignOrders() {
    console.log("🔄 [RESETTING ALL 10 TEST ORDERS TO UNASSIGNED STATUS]...");

    let resetTasks = 0;
    let resetDeliveries = 0;
    let resetSchedules = 0;
    let resetOrders = 0;

    for (const item of TEST_ORDERS_CONFIG) {
        const orderID = item.id;

        // 1. Reset Order Status to 'Processing'
        const ordRef = db.collection("order").doc(orderID);
        const oSnap = await ordRef.get();
        if (oSnap.exists) {
            await ordRef.update({
                orderStatus: "Processing",
                updatedAt: new Date()
            });
            resetOrders++;
        }

        // 2. Delete linked Task
        const tRef = db.collection("task").doc(`TSK-${orderID}`);
        const tSnap = await tRef.get();
        if (tSnap.exists) {
            await tRef.delete();
            resetTasks++;
        }

        // 3. Delete linked Delivery
        const dRef = db.collection("delivery").doc(`DEL-${orderID}`);
        const dSnap = await dRef.get();
        if (dSnap.exists) {
            await dRef.delete();
            resetDeliveries++;
        }
    }

    // 4. Delete linked Schedules
    const sSnap = await db.collection("schedule").get();
    for (const s of sSnap.docs) {
        if (s.id.includes("TEST_2110_")) {
            await s.ref.delete();
            resetSchedules++;
        }
    }

    console.log(`✅ Reset complete: ${resetOrders} orders are now UNASSIGNED (Deleted ${resetTasks} tasks, ${resetDeliveries} deliveries, ${resetSchedules} schedules).`);
    console.log(`   You can now assign them again individually or all together.`);
}

async function main() {
    const action = process.argv[2] || "list";

    if (action === "create") {
        await createOrders();
    } else if (action === "assign") {
        const orderID = process.argv[3];
        await assignSpecificOrder(orderID);
    } else if (action === "assign-all") {
        await assignAllOrders();
    } else if (action === "list") {
        await listRecords();
    } else if (action === "unassign") {
        await unassignOrders();
    } else if (action === "clean") {
        await cleanRecords();
    } else {
        console.log("Unknown action. Available: create | assign <orderID> | assign-all | list | unassign | clean");
    }

    process.exit(0);
}

main().catch(err => {
    console.error("Error in manageTestOrders:", err);
    process.exit(1);
});
