const express = require("express");
const cors = require("cors");
const accountManagementRouter = require("./accountManagementModule/server");
const deviceTradeInRouter = require("./deviceTradeInModule/server");

const app = express();

app.use(express.json());
app.use(cors());

// Mount the modular routers exactly at the root so existing endpoints (e.g., /login) remain perfectly unchanged
app.use("/", accountManagementRouter);
app.use("/api/tradein", deviceTradeInRouter);
app.use("/tradein", deviceTradeInRouter);

const PORT = 3000;
app.listen(PORT, "0.0.0.0", () => {
    console.log(`Global ReByte Server running on port ${PORT}`);
});
