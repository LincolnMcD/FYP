require("dotenv").config();
const express = require("express");
const cors = require("cors");
const accountManagementRouter = require("./accountManagementModule/server");
const paymentRouter = require("./accountManagementModule/paymentServer");
const addressRouter = require("./accountManagementModule/addressServer");
const deviceTradeInRouter = require("./deviceTradeInModule/server");
const shopRouter = require("./accountManagementModule/shopServer");
const taskAssignmentRouter = require("./taskAssignmentModule/server");
const rentalManagementRouter = require("./rentalManagementModule/server");
const transactionManagementRouter = require("./transactionManagementModule/server");
const path = require("path");
const { runWithRequest, recordRequest } = require("./config/firestoreMetrics");

const app = express();

app.use(express.json({ limit: "50mb" }));
app.use(express.urlencoded({ extended: true, limit: "50mb" }));
app.use(cors());
app.use(express.static(path.join(__dirname, "../reByteWebsite")));
app.use((req, res, next) => {
    const safePath = String(req.path || "/").replace(/(^|\/)([^/]{20,}|[^/]*@[^/]*)/g, "$1:id");
    const path = `${req.method} ${safePath}`;
    recordRequest(path);
    runWithRequest(req, next);
});

// Mount the modular routers exactly at the root so existing endpoints (e.g., /login) remain perfectly unchanged
app.use("/", accountManagementRouter);
app.use("/api/payment", paymentRouter);
app.use("/payment", paymentRouter);
app.use("/api/address", addressRouter);
app.use("/address", addressRouter);
app.use("/api/tradein", deviceTradeInRouter);
app.use("/tradein", deviceTradeInRouter);
app.use("/api/shop", shopRouter);
app.use("/shop", shopRouter);
app.use("/api/task-assignment", taskAssignmentRouter);
app.use("/task-assignment", taskAssignmentRouter);
app.use("/api/rental", rentalManagementRouter);
app.use("/rental", rentalManagementRouter);
app.use("/api/transaction-management", transactionManagementRouter);
app.use("/transaction-management", transactionManagementRouter);

const http = require("http");
const { Server } = require("socket.io");
const { setupDeliverySocket } = require("./taskAssignmentModule/deliverySocket");

const server = http.createServer(app);
const io = new Server(server, {
    cors: {
        origin: "*",
        methods: ["GET", "POST"]
    }
});

// Setup real-time delivery tracking via Socket.IO
setupDeliverySocket(io);

// Expose io instance to express app if needed
app.set("io", io);

// Event-driven Task Schedule Delay & Auto-Reassign Monitoring
const { initializeScheduleMonitoring } = require("./taskAssignmentModule/taskDelayMonitorService");
initializeScheduleMonitoring().catch(err => console.error("Error starting schedule monitoring:", err));
rentalManagementRouter.startRentalExpiryMonitor();

const PORT = 3000;
server.listen(PORT, "0.0.0.0", () => {
    console.log(`Global ReByte Server (with Socket.IO) running on port ${PORT}`);
});
