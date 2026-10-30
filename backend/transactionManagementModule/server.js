const express = require("express");
const router = express.Router();
const db = require("../config/firebase");
const cloudinary = require("../config/cloudinary");
const { FieldValue } = require("firebase-admin/firestore");
const axios = require("axios");

function timestampMillis(value) {
    if (!value) return 0;
    if (typeof value.toDate === "function") return value.toDate().getTime() || 0;
    if (typeof value._seconds === "number") return value._seconds * 1000;
    const time = new Date(value).getTime();
    return Number.isFinite(time) ? time : 0;
}

function normalizedRefundStatus(value) {
    const status = String(value || "").trim().toUpperCase();
    if (["SUCCESS", "SUCCEEDED", "COMPLETED"].includes(status)) return "SUCCEEDED";
    if (status === "PENDING") return "PENDING";
    if (["FAIL", "FAILED"].includes(status)) return "FAILED";
    return "UNKNOWN";
}

const xenditRefundStatusCache = new Map();

async function refreshPendingRefundStatus(refundRecord) {
    const localStatus = normalizedRefundStatus(refundRecord?.data?.transactionStatus);
    const refundID = refundRecord?.data?.gatewayTransactionID;
    const xenditKey = process.env.XENDIT_SECRET_KEY || "";
    if (localStatus !== "PENDING" || !refundID || !xenditKey) return localStatus;

    const cached = xenditRefundStatusCache.get(refundID);
    if (cached && cached.expiresAt > Date.now()) return cached.promise || cached.status;
    const request = axios.get(`https://api.xendit.co/refunds/${encodeURIComponent(refundID)}`, {
        headers: { Authorization: `Basic ${Buffer.from(`${xenditKey}:`).toString("base64")}` }
    }).then(async response => {
        const providerStatus = normalizedRefundStatus(response.data?.status);
        if (["SUCCEEDED", "FAILED"].includes(providerStatus)) {
            await refundRecord.ref.update({ transactionStatus: providerStatus === "SUCCEEDED" ? "Success" : "Fail" });
        }
        return providerStatus;
    }).catch(err => {
        console.warn("Could not refresh Xendit refund status:", err.response?.data || err.message);
        return localStatus;
    });
    xenditRefundStatusCache.set(refundID, { status: localStatus, expiresAt: Date.now() + 30000, promise: request });
    const status = await request;
    xenditRefundStatusCache.set(refundID, { status, expiresAt: Date.now() + 30000 });
    return status;
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

async function generateTransactionID() {
    const now = new Date();
    const yy = String(now.getFullYear()).slice(-2);
    const mm = String(now.getMonth() + 1).padStart(2, "0");
    const dd = String(now.getDate()).padStart(2, "0");
    const prefix = `${yy}${mm}${dd}TRAN`;
    const snapshot = await db.collection("transaction")
        .where("transactionID", ">=", prefix)
        .where("transactionID", "<=", `${prefix}\uf8ff`)
        .get();

    let maxSequence = 0;
    snapshot.forEach(doc => {
        const transactionID = String(doc.data().transactionID || doc.id || "");
        if (!transactionID.startsWith(prefix)) return;
        const sequence = Number.parseInt(transactionID.slice(prefix.length), 10);
        if (Number.isInteger(sequence) && sequence > maxSequence) maxSequence = sequence;
    });

    return `${prefix}${String(maxSequence + 1).padStart(5, "0")}`;
}

function roundMoney(value) {
    const amount = Number(value);
    return Number.isFinite(amount) ? Number(amount.toFixed(2)) : 0;
}

/**
 * GET /api/transaction-management/transactions or /transaction-management/transactions
 * Returns all transactions from 'transaction' collection enriched with customer,
 * payment method, and related order/rental/trade-in info.
 * Query params:
 *   - category: 'all' | 'purchase' | 'trade-in' | 'rental' | 'deposit' | 'refund'
 *   - search: string (matches transactionID, customer name/email, orderID, rentalID, tradeInRequestID, payment method)
 *   - page: number (1-indexed, default 1)
 *   - limit: number (default 10)
 */
router.get("/transactions", async (req, res) => {
    try {
        const { category = "all", search = "", page = 1, limit = 10 } = req.query;

        const pNum = Math.max(1, parseInt(page, 10) || 1);
        const lNum = Math.max(1, parseInt(limit, 10) || 10);

        // 1. Fetch transactions
        const tranSnap = await db.collection("transaction").get();
        if (tranSnap.empty) {
            return res.json({
                success: true,
                transactions: [],
                total: 0,
                page: pNum,
                limit: lNum,
                totalPages: 0,
                counts: { all: 0, purchase: 0, rental: 0, tradeIn: 0, deposit: 0, refund: 0 }
            });
        }

        // 2. Fetch reference collections for fast in-memory joins
        const [usersSnap, ordersSnap, tradeInsSnap, rentalsSnap, paymentAccSnap] = await Promise.all([
            db.collection("users").get(),
            db.collection("order").get(),
            db.collection("tradeInRequests").get(),
            db.collection("rental").get(),
            db.collection("paymentAccount").get()
        ]);

        // Build lookup maps
        const usersByUid = new Map();
        const usersByEmail = new Map();
        usersSnap.forEach(doc => {
            const u = doc.data();
            const id = doc.id;
            const uid = u.userId || u.uid || id;
            const email = (u.email || "").toLowerCase().trim();
            const record = {
                id,
                uid,
                name: u.fullName || u.name || (email ? email.split("@")[0] : "Customer"),
                email: u.email || ""
            };
            if (uid) usersByUid.set(uid, record);
            if (id) usersByUid.set(id, record);
            if (email) usersByEmail.set(email, record);
        });

        const ordersMap = new Map();
        ordersSnap.forEach(doc => ordersMap.set(doc.id, doc.data()));

        const tradeInsMap = new Map();
        tradeInsSnap.forEach(doc => {
            const data = doc.data();
            tradeInsMap.set(doc.id, data);
            if (data.tradeInRequestID) tradeInsMap.set(data.tradeInRequestID, data);
        });

        const rentalsMap = new Map();
        rentalsSnap.forEach(doc => {
            const data = doc.data();
            rentalsMap.set(doc.id, data);
            if (data.rentalID) rentalsMap.set(data.rentalID, data);
        });

        const paymentAccMap = new Map();
        paymentAccSnap.forEach(doc => {
            const data = doc.data();
            paymentAccMap.set(doc.id, data);
            if (data.paymentAccountID) paymentAccMap.set(data.paymentAccountID, data);
        });

        // 3. Process and normalize transactions
        const allTransactions = [];

        for (const doc of tranSnap.docs) {
            const t = doc.data() || {};
            const txId = t.transactionID || doc.id;
            const rawType = String(t.transactionType || "").trim();
            const txTypeLower = rawType.toLowerCase();

            // Categorize
            let categoryKey = "purchase";
            if (txTypeLower === "payout" || txTypeLower === "trade-in" || txTypeLower === "tradein") {
                categoryKey = "trade-in";
            } else if (txTypeLower === "deposit") {
                categoryKey = "deposit";
            } else if (txTypeLower === "refund") {
                categoryKey = "refund";
            } else if (txTypeLower === "rental") {
                categoryKey = "rental";
            } else if (txTypeLower === "purchase") {
                categoryKey = "purchase";
            } else {
                // Infer from related IDs if generic
                if (t.orderID) categoryKey = "purchase";
                else if (t.tradeInRequestID) categoryKey = "trade-in";
                else if (t.rentalID) categoryKey = "rental";
                else categoryKey = "purchase";
            }

            // Resolve Customer Info
            let customerName = "Unknown Customer";
            let customerEmail = "";

            // Check direct customerID on transaction
            if (t.customerID && usersByUid.has(t.customerID)) {
                const u = usersByUid.get(t.customerID);
                customerName = u.name;
                customerEmail = u.email;
            } else if (t.email && usersByEmail.has(t.email.toLowerCase().trim())) {
                const u = usersByEmail.get(t.email.toLowerCase().trim());
                customerName = u.name;
                customerEmail = u.email;
            }

            // Check linked order
            if (!customerEmail && t.orderID && ordersMap.has(t.orderID)) {
                const ord = ordersMap.get(t.orderID);
                if (ord.email && usersByEmail.has(ord.email.toLowerCase().trim())) {
                    const u = usersByEmail.get(ord.email.toLowerCase().trim());
                    customerName = u.name;
                    customerEmail = u.email;
                } else if (ord.customerID && usersByUid.has(ord.customerID)) {
                    const u = usersByUid.get(ord.customerID);
                    customerName = u.name;
                    customerEmail = u.email;
                } else if (ord.email) {
                    customerEmail = ord.email;
                    customerName = ord.fullName || ord.name || ord.email.split("@")[0];
                }
            }

            // Check linked trade-in
            if (!customerEmail && t.tradeInRequestID && tradeInsMap.has(t.tradeInRequestID)) {
                const tr = tradeInsMap.get(t.tradeInRequestID);
                if (tr.userEmail && usersByEmail.has(tr.userEmail.toLowerCase().trim())) {
                    const u = usersByEmail.get(tr.userEmail.toLowerCase().trim());
                    customerName = u.name;
                    customerEmail = u.email;
                } else if (tr.customerID && usersByUid.has(tr.customerID)) {
                    const u = usersByUid.get(tr.customerID);
                    customerName = u.name;
                    customerEmail = u.email;
                } else if (tr.userEmail) {
                    customerEmail = tr.userEmail;
                    customerName = tr.userEmail.split("@")[0];
                }
            }

            // Check linked rental
            if (!customerEmail && t.rentalID && rentalsMap.has(t.rentalID)) {
                const r = rentalsMap.get(t.rentalID);
                if (r.customerID && usersByUid.has(r.customerID)) {
                    const u = usersByUid.get(r.customerID);
                    customerName = u.name;
                    customerEmail = u.email;
                } else if (r.email && usersByEmail.has(r.email.toLowerCase().trim())) {
                    const u = usersByEmail.get(r.email.toLowerCase().trim());
                    customerName = u.name;
                    customerEmail = u.email;
                } else if (r.email) {
                    customerEmail = r.email;
                    customerName = r.email.split("@")[0];
                }
            }

            // Check paymentAccount
            if (!customerEmail && t.paymentAccountID && paymentAccMap.has(t.paymentAccountID)) {
                const pa = paymentAccMap.get(t.paymentAccountID);
                if (pa.email && usersByEmail.has(pa.email.toLowerCase().trim())) {
                    const u = usersByEmail.get(pa.email.toLowerCase().trim());
                    customerName = u.name;
                    customerEmail = u.email;
                } else if (pa.customerID && usersByUid.has(pa.customerID)) {
                    const u = usersByUid.get(pa.customerID);
                    customerName = u.name;
                    customerEmail = u.email;
                } else if (pa.email) {
                    customerEmail = pa.email;
                    customerName = pa.email.split("@")[0];
                }
            }

            // Fallback for customer display if only email found
            if (!customerName || customerName === "Unknown Customer") {
                customerName = customerEmail ? customerEmail.split("@")[0] : "Customer";
            }

            // Resolve Payment Method display
            let method = "FPX";
            const payAccId = t.paymentAccountID;
            if (payAccId) {
                if (payAccId === "fpx_online_banking") {
                    method = "FPX";
                } else if (payAccId === "ewallet_all") {
                    method = "E-Wallet";
                } else if (payAccId.startsWith("pm_") || payAccId.startsWith("card_")) {
                    method = "Card";
                } else if (paymentAccMap.has(payAccId)) {
                    const pa = paymentAccMap.get(payAccId);
                    if (pa.providerName) {
                        method = pa.providerName;
                    } else if (pa.cardNumber) {
                        method = `Card •••• ${pa.cardNumber.slice(-4)}`;
                    } else {
                        method = "Card";
                    }
                } else {
                    method = "Card";
                }
            }

            // Date formatting
            let dateObj = new Date();
            if (t.transactionDate) {
                if (t.transactionDate._seconds) {
                    dateObj = new Date(t.transactionDate._seconds * 1000);
                } else if (typeof t.transactionDate.toDate === "function") {
                    dateObj = t.transactionDate.toDate();
                } else {
                    const parsed = new Date(t.transactionDate);
                    if (!isNaN(parsed.getTime())) dateObj = parsed;
                }
            } else if (t.createdAt) {
                if (t.createdAt._seconds) {
                    dateObj = new Date(t.createdAt._seconds * 1000);
                } else {
                    const parsed = new Date(t.createdAt);
                    if (!isNaN(parsed.getTime())) dateObj = parsed;
                }
            }

            // Status normalization (Success, Fail, Pending)
            const rawStatus = String(t.transactionStatus || "Success").toLowerCase().trim();
            let status = "Success";
            if (rawStatus === "fail" || rawStatus === "failed") {
                status = "Failed";
            } else if (rawStatus === "pending") {
                status = "Pending";
            } else {
                status = "Success";
            }

            // Amount formatting
            const rawAmount = Number(t.transactionAmount || 0);
            const isNegative = categoryKey === "trade-in" || categoryKey === "refund";
            const amountPrefix = isNegative ? "-RM" : "+RM";
            const formattedAmount = `${amountPrefix}${rawAmount.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

            // Display type label
            let typeLabel = "Purchase";
            if (categoryKey === "trade-in") typeLabel = "Trade-In";
            else if (categoryKey === "deposit") typeLabel = "Deposit";
            else if (categoryKey === "rental") typeLabel = "Rental";
            else if (categoryKey === "refund") typeLabel = "Refund";

            allTransactions.push({
                id: txId,
                transactionID: txId,
                type: typeLabel,
                category: categoryKey,
                rawType,
                customer: {
                    name: customerName,
                    email: customerEmail || "—"
                },
                dateTime: dateObj.toISOString(),
                rawAmount,
                formattedAmount,
                isNegative,
                method,
                status,
                orderID: t.orderID || null,
                tradeInRequestID: t.tradeInRequestID || null,
                rentalID: t.rentalID || null,
                gatewayTransactionID: t.gatewayTransactionID || null
            });
        }

        // Sort by date descending (newest first)
        allTransactions.sort((a, b) => new Date(b.dateTime) - new Date(a.dateTime));

        // Compute tab counts
        const counts = {
            all: allTransactions.length,
            purchase: allTransactions.filter(t => t.category === "purchase").length,
            rental: allTransactions.filter(t => t.category === "rental").length,
            tradeIn: allTransactions.filter(t => t.category === "trade-in").length,
            deposit: allTransactions.filter(t => t.category === "deposit").length,
            refund: allTransactions.filter(t => t.category === "refund").length
        };

        // Filter by category
        let filtered = allTransactions;
        const catClean = String(category).toLowerCase().trim();
        if (catClean && catClean !== "all") {
            if (catClean === "purchase") filtered = filtered.filter(t => t.category === "purchase");
            else if (catClean === "rental") filtered = filtered.filter(t => t.category === "rental");
            else if (catClean === "trade-in" || catClean === "tradein" || catClean === "payout") filtered = filtered.filter(t => t.category === "trade-in");
            else if (catClean === "deposit") filtered = filtered.filter(t => t.category === "deposit");
            else if (catClean === "refund") filtered = filtered.filter(t => t.category === "refund");
        }

        // Filter by search query
        const q = String(search || "").toLowerCase().trim();
        if (q.length > 0) {
            filtered = filtered.filter(t => {
                const idMatch = t.transactionID.toLowerCase().includes(q) ||
                    (t.orderID && t.orderID.toLowerCase().includes(q)) ||
                    (t.rentalID && t.rentalID.toLowerCase().includes(q)) ||
                    (t.tradeInRequestID && t.tradeInRequestID.toLowerCase().includes(q));
                const custMatch = t.customer.name.toLowerCase().includes(q) || t.customer.email.toLowerCase().includes(q);
                const methodMatch = t.method.toLowerCase().includes(q);
                const statusMatch = t.status.toLowerCase().includes(q);
                const typeMatch = t.type.toLowerCase().includes(q);
                return idMatch || custMatch || methodMatch || statusMatch || typeMatch;
            });
        }

        // Paginate
        const total = filtered.length;
        const totalPages = Math.ceil(total / lNum) || 1;
        const offset = (pNum - 1) * lNum;
        const paged = filtered.slice(offset, offset + lNum);

        return res.json({
            success: true,
            transactions: paged,
            total,
            page: pNum,
            limit: lNum,
            totalPages,
            counts
        });
    } catch (err) {
        console.error("Error in GET /api/transaction-management/transactions:", err);
        return res.status(500).json({ success: false, error: err.message || "Failed to fetch transaction records." });
    }
});

/**
 * GET /api/transaction-management/rental-deposits
 * Retrieves rental records with depositStatus, calculates the 3 top metric blocks
 * based on rentalDeposit/depositAmount, and supports status filtering (all, active, pending, returned, forfeited).
 */
router.get("/rental-deposits", async (req, res) => {
    try {
        const { status = "all", search = "", page = 1, limit = 10 } = req.query;
        const pNum = Math.max(1, parseInt(page, 10) || 1);
        const lNum = Math.max(1, parseInt(limit, 10) || 10);

        // Fetch rentals, users, products, and devices
        const [rentalsSnap, usersSnap, productsSnap, devicesSnap] = await Promise.all([
            db.collection("rental").get(),
            db.collection("users").get(),
            db.collection("product").get(),
            db.collection("devices").get()
        ]);

        const usersMap = new Map();
        usersSnap.forEach(doc => {
            const u = doc.data();
            const uid = u.userId || u.uid || doc.id;
            const name = u.fullName || u.name || (u.email ? u.email.split("@")[0] : "Customer");
            usersMap.set(uid, { name, email: u.email || "" });
            usersMap.set(doc.id, { name, email: u.email || "" });
        });

        const devicesMap = new Map();
        devicesSnap.forEach(doc => {
            const d = doc.data();
            devicesMap.set(doc.id, d.model || d.deviceName || d.brand || "");
        });

        const productsMap = new Map();
        productsSnap.forEach(doc => {
            const p = doc.data();
            let deviceName = p.listingTitle || p.title || p.productName || "";
            if (!deviceName && p.deviceID && devicesMap.has(p.deviceID)) {
                deviceName = devicesMap.get(p.deviceID);
            }
            productsMap.set(doc.id, deviceName || "Rental Device");
            if (p.productID) productsMap.set(p.productID, deviceName || "Rental Device");
        });

        // Current month bounds for RETURNED (THIS MONTH)
        const now = new Date();
        const currentYear = now.getFullYear();
        const currentMonth = now.getMonth();

        let activeDepositsTotal = 0;
        let pendingReturnTotal = 0;
        let returnedThisMonthTotal = 0;

        const allDeposits = [];

        rentalsSnap.forEach(doc => {
            const r = doc.data();
            const rentalId = r.rentalID || doc.id;

            // Deposit value resolution: check rentalDeposit first, fallback to depositAmount
            const depositVal = Number(r.rentalDeposit !== undefined ? r.rentalDeposit : (r.depositAmount || 0));

            // Status resolution:
            // "if paid mean active, if pending mean pending, if returned mean returned"
            const rawDepStatus = String(r.depositStatus || "").toLowerCase().trim();
            let normStatus = "Active"; // default for paid or active
            if (rawDepStatus === "forfeited") {
                normStatus = "Forfeited";
            } else if (rawDepStatus === "returned" || rawDepStatus === "refunded") {
                normStatus = "Returned";
            } else if (rawDepStatus === "pending" || rawDepStatus === "pending_return" || rawDepStatus === "pending return") {
                normStatus = "Pending";
            } else {
                normStatus = "Active";
            }

            // Metric aggregations
            if (normStatus === "Active") {
                activeDepositsTotal += depositVal;
            } else if (normStatus === "Pending") {
                pendingReturnTotal += depositVal;
            } else if (normStatus === "Returned") {
                // Check if returned in this month
                let returnedDate = null;
                if (r.depositReturnedAt) {
                    if (r.depositReturnedAt._seconds) returnedDate = new Date(r.depositReturnedAt._seconds * 1000);
                    else returnedDate = new Date(r.depositReturnedAt);
                } else if (r.updatedAt) {
                    if (r.updatedAt._seconds) returnedDate = new Date(r.updatedAt._seconds * 1000);
                    else returnedDate = new Date(r.updatedAt);
                }
                if (returnedDate && !isNaN(returnedDate.getTime())) {
                    if (returnedDate.getFullYear() === currentYear && returnedDate.getMonth() === currentMonth) {
                        returnedThisMonthTotal += depositVal;
                    }
                } else {
                    // Fallback to counting if returned recently
                    returnedThisMonthTotal += depositVal;
                }
            }

            // Customer info
            let customerName = "Unknown Customer";
            if (r.customerID && usersMap.has(r.customerID)) {
                customerName = usersMap.get(r.customerID).name;
            } else if (r.email) {
                customerName = r.email.split("@")[0];
            }

            // Device info
            let deviceName = "Rental Device";
            if (r.productID && productsMap.has(r.productID)) {
                deviceName = productsMap.get(r.productID);
            } else if (r.productName) {
                deviceName = r.productName;
            }

            allDeposits.push({
                rentalID: rentalId,
                customer: customerName,
                device: deviceName,
                depositAmount: depositVal,
                formattedDeposit: depositVal.toFixed(2),
                status: normStatus, // 'Active' | 'Pending' | 'Returned'
                rawDepositStatus: r.depositStatus || "paid",
                createdAt: r.createdAt || r.startDate || null
            });
        });

        // Filter counts
        const counts = {
            all: allDeposits.length,
            active: allDeposits.filter(d => d.status === "Active").length,
            pending: allDeposits.filter(d => d.status === "Pending").length,
            returned: allDeposits.filter(d => d.status === "Returned").length,
            forfeited: allDeposits.filter(d => d.status === "Forfeited").length
        };

        // Filter by status tab
        let filtered = allDeposits;
        const stClean = String(status).toLowerCase().trim();
        if (stClean && stClean !== "all") {
            if (stClean === "active") filtered = filtered.filter(d => d.status === "Active");
            else if (stClean === "pending") filtered = filtered.filter(d => d.status === "Pending");
            else if (stClean === "returned") filtered = filtered.filter(d => d.status === "Returned");
            else if (stClean === "forfeited") filtered = filtered.filter(d => d.status === "Forfeited");
        }

        // Filter by search
        const q = String(search || "").toLowerCase().trim();
        if (q.length > 0) {
            filtered = filtered.filter(d => {
                return d.rentalID.toLowerCase().includes(q) ||
                    d.customer.toLowerCase().includes(q) ||
                    d.device.toLowerCase().includes(q) ||
                    d.status.toLowerCase().includes(q);
            });
        }

        // Paginate
        const total = filtered.length;
        const totalPages = Math.ceil(total / lNum) || 1;
        const offset = (pNum - 1) * lNum;
        const paged = filtered.slice(offset, offset + lNum);

        return res.json({
            success: true,
            deposits: paged,
            total,
            page: pNum,
            limit: lNum,
            totalPages,
            counts,
            metrics: {
                activeDeposits: activeDepositsTotal,
                pendingReturn: pendingReturnTotal,
                returnedThisMonth: returnedThisMonthTotal
            }
        });
    } catch (err) {
        console.error("Error in GET /api/transaction-management/rental-deposits:", err);
        return res.status(500).json({ success: false, error: err.message || "Failed to fetch rental deposits." });
    }
});

/**
 * GET /api/transaction-management/rental-deposits/:rentalID
 * Returns detailed rental deposit info, device details, assessment records,
 * and refund calculation breakdown for the Deposit Return Assessment page.
 */
router.get("/rental-deposits/:rentalID", async (req, res) => {
    try {
        const { rentalID } = req.params;
        if (!rentalID) return res.status(400).json({ success: false, error: "rentalID is required." });

        let rentalDoc = await db.collection("rental").doc(rentalID).get();
        if (!rentalDoc.exists) {
            const snap = await db.collection("rental").where("rentalID", "==", rentalID).limit(1).get();
            if (!snap.empty) rentalDoc = snap.docs[0];
        }
        if (!rentalDoc || !rentalDoc.exists) {
            return res.status(404).json({ success: false, error: "Rental record not found." });
        }

        const r = rentalDoc.data() || {};
        const resolvedRentalID = r.rentalID || rentalDoc.id;

        // Customer details
        let customer = { name: "Unknown Customer", email: r.email || "", initials: "CU", id: r.customerID || "" };
        if (r.customerID) {
            try {
                let uDoc = await db.collection("users").doc(r.customerID).get();
                if (!uDoc.exists) {
                    const uSnap = await db.collection("users").where("userId", "==", r.customerID).limit(1).get();
                    if (!uSnap.empty) uDoc = uSnap.docs[0];
                }
                if (uDoc && uDoc.exists) {
                    const ud = uDoc.data() || {};
                    const name = ud.fullName || ud.name || (ud.email ? ud.email.split("@")[0] : "Customer");
                    const email = ud.email || "";
                    const parts = name.trim().split(" ");
                    const initials = (parts[0] ? parts[0][0] : "") + (parts.length > 1 && parts[parts.length - 1] ? parts[parts.length - 1][0] : "");
                    customer = { name, email, initials: initials.toUpperCase() || "CU", id: r.customerID };
                }
            } catch (_) {}
        } else if (r.email) {
            const name = r.email.split("@")[0];
            customer = { name, email: r.email, initials: name.substring(0, 2).toUpperCase(), id: "" };
        }

        // Product & Device details
        let product = {
            productID: r.productID || "",
            model: "Rental Phone",
            color: "Standard",
            storage: "128 GB",
            chipset: "Standard",
            ram: "8GB",
            imageUrl: ""
        };

        if (r.productID) {
            try {
                let pDoc = await db.collection("product").doc(r.productID).get();
                if (!pDoc.exists) {
                    const pSnap = await db.collection("product").where("productID", "==", r.productID).limit(1).get();
                    if (!pSnap.empty) pDoc = pSnap.docs[0];
                }
                if (pDoc && pDoc.exists) {
                    const pd = pDoc.data() || {};
                    product.model = pd.listingTitle || pd.title || pd.model || product.model;
                    product.color = pd.color || pd.colour || "Space Gray";
                    product.storage = pd.storage || pd.storageCapacity || "128 GB";
                    product.chipset = pd.processor || pd.chipset || "A-Series";
                    product.ram = pd.ram || "8GB RAM";
                    product.imageUrl = pd.imageUrl || "";

                    // If deviceID exists, pull specs from devices collection
                    if (pd.deviceID) {
                        try {
                            const devDoc = await db.collection("devices").doc(pd.deviceID).get();
                            if (devDoc.exists) {
                                const dd = devDoc.data() || {};
                                product.model = product.model || dd.model || dd.deviceName || "Rental Phone";
                                product.color = dd.color || dd.colour || product.color;
                                product.storage = dd.storage || dd.storageCapacity || product.storage;
                                product.chipset = dd.processor || dd.chipset || product.chipset;
                                product.ram = dd.ram || product.ram;
                                product.imageUrl = product.imageUrl || dd.imageUrl || "";
                            }
                        } catch (_) {}
                    }
                }
            } catch (_) {}
        }

        const depositVal = Number(r.rentalDeposit !== undefined ? r.rentalDeposit : (r.depositAmount || 0));

        // Find actual deposit transaction ID from 'transaction' collection
        let depositTransactionID = r.depositTransactionID || r.transactionID || "";
        if (!depositTransactionID) {
            try {
                const txSnap = await db.collection("transaction")
                    .where("rentalID", "==", resolvedRentalID)
                    .get();
                if (!txSnap.empty) {
                    // Find transaction with type Deposit or Success
                    const depositTx = txSnap.docs.find(d => {
                        const tt = String(d.data().transactionType || "").toLowerCase();
                        return tt === "deposit";
                    }) || txSnap.docs[0];
                    if (depositTx) {
                        depositTransactionID = depositTx.data().transactionID || depositTx.id;
                    }
                }
            } catch (_) {}
        }
        if (!depositTransactionID) {
            depositTransactionID = r.recurringPlanID || `TXN-${resolvedRentalID}`;
        }

        // Dates
        const startStr = r.startDate || "";
        const endStr = r.endDate || r.rentalExpiryDate || "";
        let durationDays = 0;
        if (startStr && endStr) {
            try {
                const s = new Date(startStr);
                const e = new Date(endStr);
                const diffTime = Math.abs(e - s);
                durationDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
            } catch (_) {}
        }

        // Return date formatted
        let returnedDateText = "";
        if (r.returnConfirmedAt) {
            try {
                const d = r.returnConfirmedAt._seconds ? new Date(r.returnConfirmedAt._seconds * 1000) : new Date(r.returnConfirmedAt);
                returnedDateText = d.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
            } catch (_) {}
        } else if (r.updatedAt) {
            try {
                const d = r.updatedAt._seconds ? new Date(r.updatedAt._seconds * 1000) : new Date(r.updatedAt);
                returnedDateText = d.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
            } catch (_) {}
        }
        if (!returnedDateText) {
            returnedDateText = new Date().toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
        }

        // Check if there is an assessment in the subcollection returnAssessment
        let assessmentData = null;
        let assessmentImages = [];
        let assessmentDocs = [];
        try {
            const assessCol = await rentalDoc.ref.collection("returnAssessment").get();
            assessmentDocs = assessCol.docs;
            if (!assessCol.empty) {
                const docs = assessCol.docs;
                const canonicalDoc = docs.find(item => item.id === "assessment");
                const isAssessmentRecord = data => data && (
                    data.condition || data.conditions || data.notes !== undefined || data.note !== undefined
                    || data.inspectorNotes !== undefined || data.totalDepositRefund !== undefined
                    || data.totalRefundAmount !== undefined || data.totalRefund !== undefined
                    || data.finalRefund !== undefined || data.finalRefundAmount !== undefined || data.deductions
                    || data.assessment
                );
                const assessmentDoc = canonicalDoc || docs.find(item => isAssessmentRecord(item.data()));
                const assessmentRecords = docs.filter(item => isAssessmentRecord(item.data()));
                assessmentData = canonicalDoc
                    ? { ...(assessmentRecords.reduce((merged, item) => ({ ...merged, ...(item.data() || {}) }), {})), ...(canonicalDoc.data() || {}) }
                    : assessmentRecords.reduce((merged, item) => ({ ...merged, ...(item.data() || {}) }), null);

                // Read legacy fields nested under an assessment map as well
                // as the current flat returnAssessment/assessment document.
                const nestedAssessment = assessmentData?.assessment
                    || assessmentData?.returnAssessment
                    || assessmentData?.evaluation;
                if (nestedAssessment && typeof nestedAssessment === "object") {
                    assessmentData = { ...nestedAssessment, ...assessmentData };
                }

                // Older saves placed image records directly in the
                // returnAssessment collection. Include those as well as the
                // current returnAssessment/assessment/image subcollection.
                for (const recordDoc of docs) {
                    const record = recordDoc.data() || {};
                    const imageUrl = record.imageUrl || record.imageURL || record.photoUrl || record.url
                        || record.secureUrl || record.secure_url || record.downloadURL || record.downloadUrl;
                    if (imageUrl && !assessmentImages.includes(imageUrl)) assessmentImages.push(imageUrl);
                }
                const legacyImages = assessmentData?.images || assessmentData?.photos || assessmentData?.imageUrls
                    || assessmentData?.assessment?.images || assessmentData?.assessment?.photos
                    || assessmentData?.returnAssessment?.images || assessmentData?.returnAssessment?.photos
                    || r.returnAssessment?.images || r.returnAssessment?.photos;
                for (const image of (Array.isArray(legacyImages) ? legacyImages : [])) {
                    const imageUrl = typeof image === "string" ? image : (image?.imageUrl || image?.imageURL || image?.photoUrl || image?.url || image?.secureUrl || image?.secure_url || image?.downloadURL || image?.downloadUrl);
                    if (imageUrl && !assessmentImages.includes(imageUrl)) assessmentImages.push(imageUrl);
                }
            }

            // Some older return records kept evidence in a subcollection
            // directly under the rental document instead of the assessment.
            const imageParents = [rentalDoc.ref, ...assessmentDocs.map(item => item.ref)];
            for (const imageParent of imageParents) {
                for (const imageCollectionName of ["image", "images"]) {
                    const imgCol = await imageParent.collection(imageCollectionName).get();
                    imgCol.forEach(imgDoc => {
                        const idata = imgDoc.data() || {};
                        const imageUrl = idata.imageUrl || idata.imageURL || idata.photoUrl || idata.url
                            || idata.secureUrl || idata.secure_url || idata.downloadURL || idata.downloadUrl;
                        if (imageUrl && !assessmentImages.includes(imageUrl)) assessmentImages.push(imageUrl);
                    });
                }
            }
        } catch (_) {}

        const storedRefundAmount = assessmentData?.totalDepositRefund
            ?? assessmentData?.totalRefundAmount
            ?? assessmentData?.totalRefund
            ?? assessmentData?.finalRefund
            ?? assessmentData?.finalRefundAmount
            ?? assessmentData?.assessment?.totalDepositRefund
            ?? assessmentData?.returnAssessment?.totalDepositRefund
            ?? r.returnAssessment?.totalDepositRefund
            ?? r.totalDepositRefund;
        let refundStatus = Number(storedRefundAmount ?? -1) === 0 ? "NOT_REQUIRED" : "UNKNOWN";
        let refundTransactionAmount = null;
        try {
            const refundSnap = await db.collection("transaction")
                .where("rentalID", "==", resolvedRentalID)
                .get();
            const refundRecords = refundSnap.docs
                .map(doc => ({ ref: doc.ref, data: doc.data() || {} }))
                .filter(record => String(record.data.transactionType || "").toLowerCase() === "refund");
            const refund = refundRecords.find(record => normalizedRefundStatus(record.data.transactionStatus) === "SUCCEEDED")
                || refundRecords.sort((a, b) => timestampMillis(b.data.transactionDate || b.data.createdAt) - timestampMillis(a.data.transactionDate || a.data.createdAt))[0];
            if (refund) {
                refundStatus = await refreshPendingRefundStatus(refund);
                const amount = Number(refund.data.transactionAmount);
                if (Number.isFinite(amount) && amount > 0) refundTransactionAmount = amount;
            }
        } catch (err) {
            console.warn("Could not read rental deposit refund status:", err.message);
        }

        const savedFinalRefundValue =
            assessmentData?.totalDepositRefund
            ?? assessmentData?.totalRefundAmount
            ?? assessmentData?.totalRefund
            ?? assessmentData?.finalRefund
            ?? assessmentData?.finalRefundAmount
            ?? assessmentData?.assessment?.totalDepositRefund
            ?? assessmentData?.assessment?.totalRefundAmount
            ?? assessmentData?.assessment?.totalRefund
            ?? assessmentData?.assessment?.finalRefund
            ?? assessmentData?.assessment?.finalRefundAmount
            ?? assessmentData?.returnAssessment?.totalDepositRefund
            ?? assessmentData?.returnAssessment?.totalRefundAmount
            ?? assessmentData?.returnAssessment?.finalRefund
            ?? r.finalRefundAmount
            ?? r.totalDepositRefund
            ?? r.totalRefundAmount
            ?? r.totalRefund
            ?? r.finalRefund
            ?? r.returnAssessment?.totalDepositRefund
            ?? r.returnAssessment?.totalRefundAmount
            ?? r.returnAssessment?.totalRefund
            ?? r.returnAssessment?.finalRefundAmount;
        const savedFinalRefund = savedFinalRefundValue === undefined || savedFinalRefundValue === null
            ? null
            : Number(savedFinalRefundValue);
        const displayFinalRefund = savedFinalRefund === 0 && refundTransactionAmount > 0
            ? refundTransactionAmount
            : (Number.isFinite(savedFinalRefund) ? savedFinalRefund : (refundTransactionAmount ?? depositVal));

        return res.json({
            success: true,
            depositDetail: {
                rentalID: resolvedRentalID,
                rawStatus: r.depositStatus || "pending",
                refundStatus,
                displayStatus: "Pending Return",
                originalDeposit: depositVal,
                transactionID: depositTransactionID,
                returnedDateText,
                durationText: startStr && endStr ? `${startStr} - ${endStr} (${durationDays} Days)` : (durationDays ? `${durationDays} Days` : "—"),
                customer,
                product,
                notes: String(assessmentData?.notes ?? assessmentData?.note ?? assessmentData?.inspectorNotes ?? assessmentData?.assessment?.notes ?? assessmentData?.returnAssessment?.notes ?? r.depositReturnNotes ?? r.returnAssessmentNotes ?? r.notes ?? r.note ?? r.returnAssessment?.notes ?? ""),
                assessment: assessmentData?.conditions || assessmentData?.condition || assessmentData?.assessment?.conditions || assessmentData?.assessment?.condition || assessmentData?.returnAssessment?.condition || r.returnAssessment?.condition || r.condition || r.conditions || r.returnAssessment || null,
                deductions: assessmentData?.deductions || assessmentData?.assessment?.deductions || assessmentData?.returnAssessment?.deductions || r.returnAssessment?.deductions || r.deductions || [],
                finalRefund: displayFinalRefund,
                images: assessmentImages
            }
        });
    } catch (err) {
        console.error("Error in GET /api/transaction-management/rental-deposits/:rentalID:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

/**
 * POST /api/transaction-management/rental-deposits/complete-action
 * Completes the return action: records deduction breakdown, marks depositStatus as 'returned',
 * and creates a refund transaction record.
 */
router.post("/rental-deposits/complete-action", async (req, res) => {
    try {
        const { rentalID, deductions, finalRefund, assessment, conditions, notes, photos } = req.body;
        if (!rentalID) return res.status(400).json({ success: false, error: "rentalID is required" });

        let rentalRef = db.collection("rental").doc(rentalID);
        let doc = await rentalRef.get();
        if (!doc.exists) {
            const snap = await db.collection("rental").where("rentalID", "==", rentalID).limit(1).get();
            if (!snap.empty) {
                doc = snap.docs[0];
                rentalRef = doc.ref;
            }
        }
        if (!doc || !doc.exists) {
            return res.status(404).json({ success: false, error: "Rental record not found" });
        }

        const rData = doc.data() || {};
        const refundAmt = roundMoney(finalRefund !== undefined ? finalRefund : (rData.rentalDeposit || rData.depositAmount || 0));
        const resolvedRentalID = rData.rentalID || rentalRef.id;
        const depositAmount = Number(rData.rentalDeposit !== undefined ? rData.rentalDeposit : (rData.depositAmount || 0));
        if (!Number.isFinite(refundAmt) || refundAmt < 0 || refundAmt > depositAmount) {
            return res.status(400).json({ success: false, error: "Refund amount must be between RM 0 and the original deposit amount." });
        }
        if (String(rData.depositStatus || "").toLowerCase() === "returned") {
            return res.status(409).json({ success: false, error: "This rental deposit has already been returned." });
        }

        // Resolve condition of each part (Screen, Back, Camera, Frame)
        const partConditions = conditions || assessment || {
            screen: "none",
            back: "none",
            camera: "none",
            frame: "none"
        };
        const normalizedDeductions = Array.isArray(deductions)
            ? deductions.map(item => ({
                ...item,
                ...(item && Object.prototype.hasOwnProperty.call(item, "amount")
                    ? { amount: roundMoney(item.amount) }
                    : {})
            }))
            : [];

        const assessedAt = new Date();
        const assessDocRef = rentalRef.collection("returnAssessment").doc("assessment");
        // Older versions stored the provider refund state in this document.
        // Read it once so legacy successful or pending refunds cannot be sent again.
        const previousAssessmentSnap = await assessDocRef.get();
        const previousRefundStatus = String(previousAssessmentSnap.data()?.refundStatus || "").toUpperCase();
        if (["PENDING", "SUCCEEDED", "PENDING_RECONCILIATION"].includes(previousRefundStatus)) {
            return res.status(409).json({
                success: false,
                error: "A refund was already submitted for this rental. Check the refund transaction before trying again."
            });
        }
        const assessmentRecord = {
            condition: partConditions,
            deductions: normalizedDeductions,
            notes: notes || "",
            totalDepositRefund: refundAmt
        };

        // Refund the assessed amount against the Xendit invoice that collected
        // the deposit and the first rental month. Refunds go to the original
        // payment method through Xendit.
        let xenditRefund = null;
        let refundStatus = "NOT_REQUIRED";
        let originalInvoiceID = "";
        let refundTxnId = "";
        if (refundAmt > 0) {
            const depositTxSnap = await db.collection("transaction")
                .where("rentalID", "==", resolvedRentalID)
                .get();
            const depositTransactions = depositTxSnap.docs
                .map(txDoc => ({ id: txDoc.id, data: txDoc.data() || {} }))
                .filter(tx => String(tx.data.transactionType || "").toLowerCase() === "deposit"
                    && String(tx.data.transactionStatus || "").toLowerCase() === "success"
                    && (tx.data.gatewayTransactionID || tx.data.invoiceID || tx.data.invoiceId))
                .sort((a, b) => {
                    const timeValue = value => {
                        const raw = value?.toDate ? value.toDate() : value;
                        const time = new Date(raw || 0).getTime();
                        return Number.isFinite(time) ? time : 0;
                    };
                    return timeValue(b.data.transactionDate || b.data.createdAt)
                        - timeValue(a.data.transactionDate || a.data.createdAt);
                });
            const depositTransaction = depositTransactions[0];
            originalInvoiceID = depositTransaction?.data.gatewayTransactionID
                || depositTransaction?.data.invoiceID
                || depositTransaction?.data.invoiceId
                || rData.gatewayTransactionID
                || rData.invoiceID
                || rData.invoiceId
                || "";
            if (!originalInvoiceID) {
                return res.status(409).json({
                    success: false,
                    error: "The original Xendit payment reference for this rental was not found, so the deposit refund was not submitted."
                });
            }

            const xenditKey = process.env.XENDIT_SECRET_KEY || "";
            if (!xenditKey) {
                return res.status(503).json({ success: false, error: "Xendit refunds are not configured on the backend." });
            }
            const xenditHeaders = {
                Authorization: `Basic ${Buffer.from(`${xenditKey}:`).toString("base64")}`,
                "Content-Type": "application/json"
            };

            let invoiceData;
            try {
                const invoiceRes = await axios.get(
                    `https://api.xendit.co/v2/invoices/${encodeURIComponent(originalInvoiceID)}`,
                    { headers: xenditHeaders }
                );
                invoiceData = invoiceRes.data || {};
            } catch (invoiceErr) {
                console.error("Could not verify original Xendit rental payment:", invoiceErr.response?.data || invoiceErr.message);
                return res.status(502).json({ success: false, error: "Could not verify the original Xendit payment. No refund was submitted." });
            }
            const invoiceStatus = String(invoiceData.status || "").toUpperCase();
            if (!["PAID", "SETTLED", "COMPLETED"].includes(invoiceStatus)) {
                return res.status(409).json({ success: false, error: `The original Xendit payment is ${invoiceStatus || "not paid"}; no refund was submitted.` });
            }
            const paidAmount = Number(invoiceData.paid_amount ?? invoiceData.amount ?? 0);
            if (!Number.isFinite(paidAmount) || refundAmt > paidAmount) {
                return res.status(400).json({ success: false, error: "The assessed refund exceeds the amount collected by Xendit." });
            }

            const existingRefunds = await db.collection("transaction")
                .where("rentalID", "==", resolvedRentalID)
                .get();
            const refundRecords = existingRefunds.docs
                .map(refundDoc => ({ id: refundDoc.id, data: refundDoc.data() || {} }))
                .filter(refund => String(refund.data.transactionType || "").toLowerCase() === "refund");
            let matchingExistingRefund = refundRecords.find(refund =>
                String(refund.data.originalGatewayTransactionID || "") === originalInvoiceID
                && roundMoney(refund.data.transactionAmount) === refundAmt
                && ["pending", "success"].includes(String(refund.data.transactionStatus || "").toLowerCase())
            );
            // A previous attempt may have reached Xendit, then failed while
            // saving the assessment. Reuse its confirmed provider refund and
            // finish the Firestore writes instead of sending a second refund.
            if (matchingExistingRefund && matchingExistingRefund.data.gatewayTransactionID) {
                refundTxnId = matchingExistingRefund.id;
                refundStatus = String(matchingExistingRefund.data.transactionStatus).toLowerCase() === "success"
                    ? "SUCCEEDED" : "PENDING";
                xenditRefund = {
                    id: matchingExistingRefund.data.gatewayTransactionID,
                    status: refundStatus
                };
            } else if (matchingExistingRefund) {
                // Older versions wrote the local transaction before calling
                // Xendit, but only saved Xendit's refund ID after the rental
                // assessment batch. Look up that invoice's refund history to
                // recover a refund accepted by Xendit before that batch failed.
                try {
                    const providerRefundsRes = await axios.get("https://api.xendit.co/refunds", {
                        headers: xenditHeaders,
                        params: { invoice_id: originalInvoiceID, limit: 100 }
                    });
                    const providerRefundsData = providerRefundsRes.data || {};
                    const providerRefunds = Array.isArray(providerRefundsData)
                        ? providerRefundsData
                        : (providerRefundsData.data || providerRefundsData.refunds || []);
                    const recoveredRefund = providerRefunds.find(refund =>
                        roundMoney(refund.amount) === refundAmt
                        && ["SUCCEEDED", "SUCCESS", "COMPLETED", "PENDING"].includes(String(refund.status || "").toUpperCase())
                    );
                    if (recoveredRefund && (recoveredRefund.id || recoveredRefund.refund_id)) {
                        const recoveredStatus = String(recoveredRefund.status || "").toUpperCase();
                        refundStatus = ["SUCCEEDED", "SUCCESS", "COMPLETED"].includes(recoveredStatus)
                            ? "SUCCEEDED" : "PENDING";
                        xenditRefund = recoveredRefund;
                        refundTxnId = matchingExistingRefund.id;
                        await db.collection("transaction").doc(refundTxnId).update({
                            transactionStatus: refundStatus === "SUCCEEDED" ? "Success" : "Pending",
                            gatewayTransactionID: recoveredRefund.id || recoveredRefund.refund_id
                        });
                        matchingExistingRefund = {
                            ...matchingExistingRefund,
                            data: {
                                ...matchingExistingRefund.data,
                                transactionStatus: refundStatus === "SUCCEEDED" ? "Success" : "Pending",
                                gatewayTransactionID: recoveredRefund.id || recoveredRefund.refund_id
                            }
                        };
                    }
                } catch (reconcileErr) {
                    console.warn("Could not reconcile prior Xendit rental refund:", reconcileErr.response?.data || reconcileErr.message);
                }
                if (!matchingExistingRefund.data.gatewayTransactionID) {
                    return res.status(409).json({
                        success: false,
                        error: "Xendit may have received the previous refund request, but its result is not confirmed yet. Check the Xendit refund history before retrying to avoid a duplicate refund."
                    });
                }
            }
            const previousIdenticalFailure = refundRecords.some(refund =>
                String(refund.data.transactionStatus || "").toLowerCase() === "fail"
                && String(refund.data.originalGatewayTransactionID || "") === originalInvoiceID
                && roundMoney(refund.data.transactionAmount) === refundAmt
            );
            if (previousIdenticalFailure && !matchingExistingRefund) {
                return res.status(409).json({
                    success: false,
                    error: "Xendit already rejected this refund amount for the original payment. Check the refundable balance in Xendit before submitting another amount."
                });
            }

            if (!matchingExistingRefund) {
                // Save the pending refund transaction as the retry guard and
                // audit record before contacting Xendit.
                refundTxnId = await generateTransactionID();
                const refundTxnRef = db.collection("transaction").doc(refundTxnId);
                await refundTxnRef.create({
                    transactionID: refundTxnId,
                    transactionType: "Refund",
                    transactionStatus: "Pending",
                    transactionAmount: refundAmt,
                    transactionDate: assessedAt,
                    rentalID: resolvedRentalID,
                    gatewayTransactionID: "",
                    originalGatewayTransactionID: originalInvoiceID,
                    createdAt: assessedAt.toISOString()
                });

                try {
                    const refundRes = await axios.post("https://api.xendit.co/refunds", {
                        invoice_id: originalInvoiceID,
                        amount: refundAmt,
                        reason: "REQUESTED_BY_CUSTOMER"
                    }, { headers: xenditHeaders });
                    xenditRefund = refundRes.data || {};
                    const providerState = String(xenditRefund.status || "PENDING").toUpperCase();
                    if (["SUCCEEDED", "SUCCESS", "COMPLETED"].includes(providerState)) {
                        refundStatus = "SUCCEEDED";
                    } else if (providerState === "FAILED") {
                        await refundTxnRef.update({ transactionStatus: "Fail", gatewayTransactionID: xenditRefund.id || xenditRefund.refund_id || "" });
                        return res.status(502).json({ success: false, error: "Xendit could not process the deposit refund." });
                    } else {
                        refundStatus = "PENDING";
                    }
                    // Persist Xendit's acknowledgement before the assessment
                    // write. If that later write fails, a retry can safely
                    // finalize the assessment without refunding twice.
                    await refundTxnRef.update({
                        transactionStatus: refundStatus === "SUCCEEDED" ? "Success" : "Pending",
                        gatewayTransactionID: xenditRefund.id || xenditRefund.refund_id || ""
                    });
                } catch (refundErr) {
                    const providerError = refundErr.response?.data || refundErr.message;
                    console.error("Xendit rental deposit refund failed:", providerError);
                    const knownRejection = Boolean(refundErr.response && refundErr.response.status < 500);
                    if (knownRejection) await refundTxnRef.update({ transactionStatus: "Fail" });
                    const providerErrorCode = String(providerError?.error_code || "").toUpperCase();
                    if (["MAXIMUM_REFUND_AMOUNT_REACHED", "REFUND_AMOUNT_EXCEEDED"].includes(providerErrorCode)) {
                        return res.status(409).json({
                            success: false,
                            error: "Xendit reports that this payment has no refundable balance left for this amount. A previous refund may already have used the balance. Check the invoice refund history in Xendit before retrying."
                        });
                    }
                    return res.status(502).json({
                        success: false,
                        error: knownRejection
                            ? (providerError.message || "Xendit rejected the deposit refund.")
                            : "Xendit did not confirm the refund result. Check Xendit before retrying to avoid a duplicate refund."
                    });
                }
            }
        }

        // Only mark the deposit returned after Xendit has accepted the refund
        // (or when the assessment has no refund due).
        const batch = db.batch();
        batch.update(rentalRef, {
            depositStatus: "returned",
            depositReturnedAt: assessedAt,
            updatedAt: assessedAt.toISOString(),
            // Remove assessment details previously duplicated on the rental root.
            deductions: FieldValue.delete(),
            finalRefundAmount: FieldValue.delete(),
            depositReturnNotes: FieldValue.delete(),
            returnAssessment: FieldValue.delete()
        });
        batch.set(assessDocRef, {
            ...assessmentRecord
        });
        await batch.commit();

        // Store uploaded photos in subcollection 'image' under returnAssessment
        const uploadedImages = [];
        if (Array.isArray(photos) && photos.length > 0) {
            for (let i = 0; i < photos.length; i++) {
                const photoItem = photos[i];
                let finalUrl = "";

                if (typeof photoItem === "string") {
                    if (photoItem.startsWith("data:image")) {
                        // Base64 data URL: upload to Cloudinary
                        try {
                            const matches = photoItem.match(/^data:image\/([a-zA-Z0-9]+);base64,(.+)$/);
                            if (matches && matches[2]) {
                                const buffer = Buffer.from(matches[2], "base64");
                                const folder = `rebyte/return_assessment/${resolvedRentalID}`;
                                const publicName = `assessment_${Date.now()}_${i + 1}`;
                                const cloudResult = await uploadBufferToCloudinary(buffer, folder, publicName);
                                finalUrl = cloudResult.secure_url || cloudResult.url || "";
                            }
                        } catch (uErr) {
                            console.error(`Failed to upload assessment photo #${i + 1} to Cloudinary:`, uErr);
                        }
                    } else if (photoItem.startsWith("http://") || photoItem.startsWith("https://")) {
                        finalUrl = photoItem;
                    }
                } else if (photoItem && typeof photoItem === "object") {
                    finalUrl = photoItem.imageUrl || photoItem.url || "";
                }

                if (finalUrl) {
                    const imgDocRef = assessDocRef.collection("image").doc();
                    await imgDocRef.set({
                        imageID: imgDocRef.id,
                        imageUrl: finalUrl,
                        uploadedAt: new Date().toISOString()
                    });
                    uploadedImages.push(finalUrl);
                }
            }
        }

        return res.json({
            success: true,
            message: `Deposit refund action completed for rental #${resolvedRentalID}.`,
            finalRefund: refundAmt,
            refundTxnId,
            refundStatus,
            refundID: xenditRefund?.id || xenditRefund?.refund_id || null,
            originalInvoiceID: originalInvoiceID || null,
            images: uploadedImages
        });
    } catch (err) {
        console.error("Error in POST /api/transaction-management/rental-deposits/complete-action:", err);
        return res.status(500).json({ success: false, error: err.message });
    }
});

/**
 * POST /api/transaction-management/rental-deposits/return
 * Action endpoint for clicking the "Return" button on a Pending rental deposit
 */
router.post("/rental-deposits/return", async (req, res) => {
    return res.status(409).json({
        success: false,
        error: "Use the return assessment workflow so the refund is processed through Xendit before the deposit is marked returned."
    });
});

module.exports = router;

