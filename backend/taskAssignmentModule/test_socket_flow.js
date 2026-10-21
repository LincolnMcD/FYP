const http = require("http");
const { Server } = require("socket.io");
const { io: Client } = require("socket.io-client");
const { setupDeliverySocket } = require("./deliverySocket");

async function runSocketVerification() {
    console.log("=== Testing Real-Time Socket.IO Delivery Tracking ===");

    // 1. Start a temporary test server on port 3099
    const testServer = http.createServer();
    const io = new Server(testServer, {
        cors: { origin: "*" }
    });
    setupDeliverySocket(io);

    await new Promise((resolve) => testServer.listen(3099, resolve));
    console.log("[Test Server] Running on http://localhost:3099");

    const TEST_ORDER = "DEL001";
    let locationReceived = false;
    let completionReceived = false;

    // 2. Connect Staff Socket
    const staffSocket = Client("http://localhost:3099", { transports: ["websocket"] });
    // 3. Connect Customer Socket
    const customerSocket = Client("http://localhost:3099", { transports: ["websocket"] });

    await new Promise((resolve) => {
        let connectedCount = 0;
        const checkDone = () => {
            connectedCount++;
            if (connectedCount === 2) resolve();
        };
        staffSocket.on("connect", checkDone);
        customerSocket.on("connect", checkDone);
    });
    console.log("✅ Step 1: Staff & Customer connected to Socket.IO successfully");

    // 4. Staff joins room: delivery:DEL001
    staffSocket.emit("join-delivery", { orderID: TEST_ORDER, role: "staff" });
    // Customer joins room: delivery:DEL001
    customerSocket.emit("join-delivery", { orderID: TEST_ORDER, role: "customer" });

    await new Promise((r) => setTimeout(r, 200));
    console.log("✅ Step 2: Both clients joined room: delivery:" + TEST_ORDER);

    // 5. Customer listens for live GPS updates
    customerSocket.on("staff-location-update", (data) => {
        console.log("📡 [Customer] Received real-time GPS:", data);
        if (data.lat === 5.40314 && data.lng === 100.33501) {
            locationReceived = true;
        }
    });

    // Customer listens for completion event
    customerSocket.on("delivery-completed", (data) => {
        console.log("🏁 [Customer] Received delivery-completed:", data);
        if (data.orderID === TEST_ORDER && data.status === "Delivered") {
            completionReceived = true;
        }
    });

    // 6. Staff sends live GPS coordinates
    console.log("🚚 Step 3: Staff sending live GPS update...");
    staffSocket.emit("send-location", {
        orderID: TEST_ORDER,
        lat: 5.40314,
        lng: 100.33501,
        heading: 90.0,
        speed: 35.5
    });

    await new Promise((r) => setTimeout(r, 400));

    // Inspect rooms and participants
    const { getDeliveryRoomsStatus } = require("./deliverySocket");
    const status = getDeliveryRoomsStatus(io);
    console.log("🔍 [Inspector Test] Active Rooms Count:", status.activeRoomsCount);
    console.log("🔍 [Inspector Test] Room Info:", JSON.stringify(status.rooms, null, 2));

    // 7. Staff emits delivery completed
    console.log("📦 Step 4: Staff emitting delivery completed...");
    staffSocket.emit("delivery-completed", {
        orderID: TEST_ORDER,
        proofOfDeliveryUrl: "https://example.com/proof.jpg"
    });

    await new Promise((r) => setTimeout(r, 400));

    // 8. Cleanup
    staffSocket.disconnect();
    customerSocket.disconnect();
    await new Promise((r) => testServer.close(r));

    console.log("\n=== Test Results ===");
    console.log("1. Staff Location Received by Customer:", locationReceived ? "PASSED ✅" : "FAILED ❌");
    console.log("2. Completion Event Received by Customer:", completionReceived ? "PASSED ✅" : "FAILED ❌");

    if (locationReceived && completionReceived) {
        console.log("\n🎉 ALL SOCKET.IO TESTS PASSED PERFECTLY!");
    } else {
        process.exit(1);
    }
}

runSocketVerification().catch(err => {
    console.error("Test failed with error:", err);
    process.exit(1);
});
