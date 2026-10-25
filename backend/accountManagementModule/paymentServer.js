const express = require("express");
const axios = require("axios");
const db = require("../config/firebase");

const router = express.Router();

const XENDIT_SECRET_KEY = process.env.XENDIT_SECRET_KEY || "";
const XENDIT_PUBLIC_KEY = process.env.XENDIT_PUBLIC_KEY || "";

const getXenditAuthHeader = () => {
    const authString = Buffer.from(`${XENDIT_SECRET_KEY}:`).toString("base64");
    return {
        Authorization: `Basic ${authString}`,
        "Content-Type": "application/json"
    };
};

/**
 * GET /config
 * Returns public key to mobile app safely
 */
router.get("/config", (req, res) => {
    return res.json({
        publicKey: XENDIT_PUBLIC_KEY
    });
});

/**
 * POST /check-duplicate
 * Checks if raw cardNumber is already registered under this customer before tokenizing/authenticating
 */
router.post("/check-duplicate", async (req, res) => {
    try {
        const { email, cardNumber } = req.body;
        if (!email || !cardNumber) {
            return res.json({ isDuplicate: false });
        }

        const rawCardNum = String(cardNumber).replace(/\s+/g, '');
        const { customerID } = await getCustomerInfo(email);
        const targetCustIds = [customerID];
        if (email && email !== customerID) {
            targetCustIds.push(email);
        }

        const existingCardSnap = await db.collection("paymentAccount")
            .where("customerID", "in", targetCustIds)
            .where("cardNumber", "==", rawCardNum)
            .get();

        const activeCard = existingCardSnap.docs.find(doc => {
            const status = doc.data().status;
            return status !== "delete" && status !== "Deleted";
        });

        if (activeCard) {
            return res.json({
                isDuplicate: true,
                message: "This card is already added to your account."
            });
        }

        return res.json({ isDuplicate: false });
    } catch (err) {
        console.error("Error checking duplicate card:", err);
        return res.json({ isDuplicate: false });
    }
});

/**
 * GET /methods?email=...
/**
 * Helper: Find customer record from users collection by email or uid
 */
async function getCustomerInfo(emailOrId) {
    if (!emailOrId) return { customerID: "", email: "" };
    
    // Check by doc ID first (if Firebase UID was passed)
    const docSnap = await db.collection("users").doc(emailOrId).get();
    if (docSnap.exists) {
        const u = docSnap.data();
        return {
            customerID: u.userId || docSnap.id,
            email: u.email || ""
        };
    }

    // Check by email in users collection
    const querySnap = await db.collection("users").where("email", "==", emailOrId).limit(1).get();
    if (!querySnap.empty) {
        const u = querySnap.docs[0].data();
        return {
            customerID: u.userId || querySnap.docs[0].id,
            email: u.email || emailOrId
        };
    }

    return { customerID: emailOrId, email: emailOrId };
}

/**
 * Helper: Generate next paymentAccountID for customer
 * Format: [first 5 characters of customerID] + "PA" + [sequence number] (e.g. GzsuGPA001)
 */
async function generatePaymentAccountId(customerID) {
    const custPrefix = String(customerID || "").slice(0, 5).trim();
    const idPrefix = `${custPrefix}PA`;

    // Query existing payment accounts for this customer to find the latest sequence number
    const snap = await db.collection("paymentAccount")
        .where("customerID", "==", customerID)
        .get();

    let maxSeq = 0;
    snap.forEach(doc => {
        const payId = doc.data().paymentAccountID || doc.id;
        if (payId && payId.startsWith(idPrefix)) {
            const numPart = payId.slice(idPrefix.length);
            const num = parseInt(numPart, 10);
            if (!isNaN(num) && num > maxSeq) {
                maxSeq = num;
            }
        }
    });

    const nextSeq = String(maxSeq + 1).padStart(3, "0");
    return `${idPrefix}${nextSeq}`;
}

/**
 * GET /methods?email=...
 * Retrieves all saved payment methods for this user directly from paymentAccount table
 */
router.get("/methods", async (req, res) => {
    try {
        const { email } = req.query;
        if (!email) {
            return res.status(400).json({ error: "Email is required" });
        }

        const { customerID } = await getCustomerInfo(email);

        // Query paymentAccount by customerID or email
        const targetIds = [customerID];
        if (email && email !== customerID) {
            targetIds.push(email);
        }

        const snap = await db.collection("paymentAccount")
            .where("customerID", "in", targetIds)
            .get();

        const methods = snap.docs
            .filter(doc => {
                const s = doc.data().status;
                return s !== "delete" && s !== "Deleted";
            })
            .map(doc => {
                const data = doc.data();
                const payId = data.paymentAccountID || doc.id;
                const fullNum = data.cardNumber || "";
                const masked = fullNum.length >= 4 ? `**** **** **** ${fullNum.slice(-4)}` : fullNum;

                return {
                    id: payId,
                    paymentAccountID: payId,
                    paymentAccountNo: payId, // backward-compat for mobile models expecting paymentAccountNo
                    customerID: data.customerID || customerID,
                    cardNumber: data.cardNumber || masked, // actual card number
                    rawCardNumber: data.cardNumber || "",
                    cvv: data.CVV || data.cvv || "",
                    maskedCardNumber: masked,
                    expiryDate: data.expiredDate || "",
                    expiredDate: data.expiredDate || "",
                    cardType: data.providerName || "Visa",
                    providerName: data.providerName || "Visa",
                    isDefault: data.isDefault || false,
                    status: data.status || "Active",
                    createdAt: data.createdAt
                };
            });

        // Sort: default first, then newest
        methods.sort((a, b) => (b.isDefault ? 1 : 0) - (a.isDefault ? 1 : 0));

        return res.json({ success: true, methods });
    } catch (err) {
        console.error("Error fetching payment methods:", err);
        return res.status(500).json({ error: "Failed to fetch payment methods" });
    }
});

/**
 * POST /save-card
 * Creates a record in table: paymentAccount
 * Fields: paymentAccountID, customerID, expiredDate, providerName, CVV, cardNumber (raw card number), isDefault, status, createdAt
 * Checks duplicate card for the same customer
 */
router.post("/save-card", async (req, res) => {
    try {
        const { email, tokenId, paymentAccountNo, cardNumber, expiryDate, cvv, providerName, isDefault } = req.body;

        if (!email || (!paymentAccountNo && !cardNumber)) {
            return res.status(400).json({ error: "Missing required card details" });
        }

        const rawCardNum = (paymentAccountNo || cardNumber).replace(/\s+/g, '');
        const cleanExpiry = expiryDate || '';
        const cleanCvv = cvv || '';

        // Only Visa and Mastercard are supported in Malaysia
        const detectBrandFromNumber = (numStr) => {
            if (!numStr) return null;
            if (numStr.startsWith('4')) return 'Visa';
            if (/^(5[1-5]|2[2-7])/.test(numStr)) return 'Mastercard';
            return null;
        };

        const resolvedBrand = (providerName === 'Visa' || providerName === 'Mastercard')
            ? providerName
            : (detectBrandFromNumber(rawCardNum) || 'Visa');
        const brand = resolvedBrand;

        // Resolve customerID from users collection
        const { customerID, email: resolvedEmail } = await getCustomerInfo(email);
        const targetCustIds = [customerID];
        if (email && email !== customerID) {
            targetCustIds.push(email);
        }

        // Duplicate Check: Check if this user already has an active card with this same card number
        const existingCardSnap = await db.collection("paymentAccount")
            .where("customerID", "in", targetCustIds)
            .where("cardNumber", "==", rawCardNum)
            .get();

        const activeDuplicate = existingCardSnap.docs.find(doc => {
            const s = doc.data().status;
            return s !== "delete" && s !== "Deleted";
        });

        if (activeDuplicate) {
            return res.status(409).json({
                success: false,
                error: "This card is already added to your account."
            });
        }

        // Check if user currently has active cards to determine default status
        const userExistingCards = await db.collection("paymentAccount")
            .where("customerID", "in", targetCustIds)
            .get();

        const userActiveCards = userExistingCards.docs.filter(doc => {
            const s = doc.data().status;
            return s !== "delete" && s !== "Deleted";
        });

        const shouldBeDefault = isDefault || userActiveCards.length === 0;

        // If setting this card as default, un-default other active cards for this customer
        if (shouldBeDefault && userActiveCards.length > 0) {
            const batch = db.batch();
            userActiveCards.forEach(doc => {
                if (doc.data().isDefault) {
                    batch.update(doc.ref, { isDefault: false });
                }
            });
            await batch.commit();
        }

        // Generate paymentAccountID: custID first 5 char + PA sequence number
        const paymentAccountID = await generatePaymentAccountId(customerID);
        const maskedNum = `**** **** **** ${rawCardNum.slice(-4)}`;
        const nowIso = new Date().toISOString();

        // Save to paymentAccount collection: raw card number stored in cardNumber attribute with status = "Active"
        const paymentAccountRef = db.collection("paymentAccount").doc(paymentAccountID);
        await paymentAccountRef.set({
            paymentAccountID: paymentAccountID,
            customerID: customerID,
            email: resolvedEmail || email,
            cardNumber: rawCardNum,
            expiredDate: cleanExpiry,
            providerName: brand,
            CVV: cleanCvv,
            tokenId: tokenId || "",
            isDefault: shouldBeDefault,
            status: "Active",
            createdAt: nowIso
        });

        return res.status(200).json({
            success: true,
            message: "Payment account created successfully",
            method: {
                id: paymentAccountID,
                paymentAccountID: paymentAccountID,
                paymentAccountNo: paymentAccountID,
                cardNumber: rawCardNum,
                maskedCardNumber: maskedNum,
                expiryDate: cleanExpiry,
                cardType: brand,
                isDefault: shouldBeDefault
            }
        });
    } catch (err) {
        console.error("Error saving payment account:", err);
        return res.status(500).json({ error: "Failed to save payment account" });
    }
});

/**
 * PUT /set-default
 * Sets a specific paymentAccountID as default for this customer
 */
router.put("/set-default", async (req, res) => {
    try {
        const { email, paymentId } = req.body;
        if (!email || !paymentId) {
            return res.status(400).json({ error: "Email and paymentId required" });
        }

        const { customerID } = await getCustomerInfo(email);
        const targetCustIds = [customerID];
        if (email && email !== customerID) {
            targetCustIds.push(email);
        }

        const userCards = await db.collection("paymentAccount")
            .where("customerID", "in", targetCustIds)
            .get();

        const batch = db.batch();
        userCards.forEach(doc => {
            const data = doc.data();
            const isMatch = (doc.id === paymentId) || (data.paymentAccountID === paymentId);
            batch.update(doc.ref, { isDefault: isMatch });
        });
        await batch.commit();

        return res.json({ success: true, message: "Default payment method updated" });
    } catch (err) {
        console.error("Error setting default payment:", err);
        return res.status(500).json({ error: "Failed to update default payment method" });
    }
});

/**
 * DELETE /methods/:id?email=...
 * Soft deletes the paymentAccount record by setting status = 'delete'
 */
router.delete("/methods/:id", async (req, res) => {
    try {
        const { id } = req.params;
        const { email } = req.query;

        if (!email || !id) {
            return res.status(400).json({ error: "Email and card ID required" });
        }

        const { customerID } = await getCustomerInfo(email);
        const targetCustIds = [customerID];
        if (email && email !== customerID) {
            targetCustIds.push(email);
        }

        const userCards = await db.collection("paymentAccount")
            .where("customerID", "in", targetCustIds)
            .get();

        let wasDefault = false;

        for (const doc of userCards.docs) {
            const data = doc.data();
            if (doc.id === id || data.paymentAccountID === id || data.cardNumber === id) {
                wasDefault = data.isDefault;
                // Soft delete: update status to delete
                await doc.ref.update({
                    status: "delete",
                    isDefault: false,
                    deletedAt: new Date().toISOString()
                });
                break;
            }
        }

        // If the deleted account was default, make another active one default
        if (wasDefault) {
            const remaining = await db.collection("paymentAccount")
                .where("customerID", "in", targetCustIds)
                .get();

            const nextActive = remaining.docs.find(doc => {
                const s = doc.data().status;
                return s !== "delete" && s !== "Deleted";
            });

            if (nextActive) {
                await nextActive.ref.update({ isDefault: true });
            }
        }

        return res.json({ success: true, message: "Payment method deleted successfully" });
    } catch (err) {
        console.error("Error deleting payment method:", err);
        return res.status(500).json({ error: "Failed to delete payment method" });
    }
});

/**
 * POST /create-invoice
 * Creates a Xendit Invoice for checkout payments (FPX, E-Wallets, Cards)
 */
router.post("/create-invoice", async (req, res) => {
    try {
        const { email, amount, description, paymentMethodType, productIDs } = req.body;
        if (!email || !amount) {
            return res.status(400).json({ success: false, error: "email and amount are required" });
        }

        const externalId = `order_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
        
        // Lookup user profile to prefill customer details (email, phone, name)
        let customerData = {
            email: email
        };
        try {
            const userSnap = await db.collection("users").where("email", "==", email).limit(1).get();
            if (!userSnap.empty) {
                const u = userSnap.docs[0].data();
                if (u.fullName) customerData.given_names = u.fullName;
                if (u.phoneNumber) {
                    // Remove +60 prefix from phone number as requested
                    let rawPhone = String(u.phoneNumber).trim();
                    if (rawPhone.startsWith("+60")) rawPhone = rawPhone.substring(3);
                    else if (rawPhone.startsWith("60")) rawPhone = rawPhone.substring(2);
                    else if (rawPhone.startsWith("0")) rawPhone = rawPhone.substring(1);
                    customerData.mobile_number = rawPhone;
                }
            }
        } catch (_) {}

        const invoicePayload = {
            external_id: externalId,
            amount: Number(amount),
            currency: "MYR",
            description: description || "ReByte Purchase",
            payer_email: email,
            customer: customerData,
            success_redirect_url: "https://rebyte.local/payment-success",
            failure_redirect_url: "https://rebyte.local/payment-failure",
        };

        // Filter payment channels based on selected payment method
        if (paymentMethodType === "ewallet") {
            invoicePayload.payment_methods = ["TOUCHNGO", "GRABPAY", "SHOPEEPAY"];
        } else if (paymentMethodType === "fpx") {
            invoicePayload.payment_methods = [
                "DD_PUBLIC_FPX", "DD_UOB_FPX", "DD_AFFIN_FPX", "DD_AGRO_FPX",
                "DD_ALLIANCE_FPX", "DD_AMBANK_FPX", "DD_ISLAM_FPX", "DD_MUAMALAT_FPX",
                "DD_BOC_FPX", "DD_RAKYAT_FPX", "DD_BSN_FPX", "DD_CIMB_FPX",
                "DD_HLB_FPX", "DD_HSBC_FPX", "DD_KFH_FPX", "DD_MAYB2U_FPX",
                "DD_OCBC_FPX", "DD_RHB_FPX", "DD_SCH_FPX", "DD_DUITNOW_PAY"
            ];
        } else if (paymentMethodType === "card") {
            invoicePayload.payment_methods = ["CREDIT_CARD"];
        }

        const response = await axios.post("https://api.xendit.co/v2/invoices", invoicePayload, {
            headers: getXenditAuthHeader()
        });

        return res.json({
            success: true,
            invoiceId: response.data.id,
            invoiceUrl: response.data.invoice_url,
            status: response.data.status,
            amount: response.data.amount
        });
    } catch (err) {
        console.error("Error creating Xendit invoice:", err.response ? err.response.data : err.message);
        return res.status(500).json({
            success: false,
            error: err.response?.data?.message || "Failed to create payment session with Xendit"
        });
    }
});

/**
 * POST /api/payment/refund-invoice
 * Automatically refunds or expires a payment session if item inventory was lost to another user
 */
router.post("/refund-invoice", async (req, res) => {
    try {
        const { invoiceId, reason } = req.body;
        if (!invoiceId) {
            return res.status(400).json({ success: false, error: "invoiceId is required" });
        }

        // Map reason to Xendit's strict enum: ["FRAUDULENT","DUPLICATE","REQUESTED_BY_CUSTOMER","CANCELLATION","OTHERS"]
        const validReasons = ["FRAUDULENT", "DUPLICATE", "REQUESTED_BY_CUSTOMER", "CANCELLATION", "OTHERS"];
        const xenditReason = validReasons.includes(reason) ? reason : "CANCELLATION";

        // Try refunding completed invoice
        try {
            const refundRes = await axios.post("https://api.xendit.co/refunds", {
                invoice_id: invoiceId,
                reason: xenditReason
            }, {
                headers: getXenditAuthHeader()
            });

            return res.json({
                success: true,
                action: "refunded",
                refund: refundRes.data
            });
        } catch (refundErr) {
            // If refund fails because invoice is not yet paid or still pending, expire it
            try {
                await axios.post(`https://api.xendit.co/invoices/${invoiceId}/expire!`, {}, {
                    headers: getXenditAuthHeader()
                });
                return res.json({ success: true, action: "expired" });
            } catch (expireErr) {
                console.error("Failed to expire or refund invoice:", expireErr.response ? expireErr.response.data : expireErr.message);
                return res.json({
                    success: false,
                    error: refundErr.response?.data?.message || "Could not process refund automatically"
                });
            }
        }
    } catch (err) {
        console.error("Refund error:", err);
        return res.status(500).json({ success: false, error: "Internal server error" });
    }
});

/**
 * GET /api/payment/get-invoice?invoiceId=...
 * Retrieves the current status of an invoice directly from Xendit
 */
router.get("/get-invoice", async (req, res) => {
    try {
        const { invoiceId } = req.query;
        if (!invoiceId) {
            return res.status(400).json({ success: false, error: "invoiceId is required" });
        }

        const response = await axios.get(`https://api.xendit.co/v2/invoices/${invoiceId}`, {
            headers: getXenditAuthHeader()
        });

        return res.json({
            success: true,
            invoice: response.data,
            status: response.data.status
        });
    } catch (err) {
        console.error("Error retrieving Xendit invoice:", err.response ? err.response.data : err.message);
        return res.status(500).json({
            success: false,
            error: err.response?.data?.message || "Failed to retrieve invoice status"
        });
    }
});
/**
 * GET /api/payment/transactions
 * Retrieves real user transaction records directly from Firestore 'transaction' collection.
 * Tracks back ownership via orderID (order), tradeInRequestID (tradeInRequests), or rentalID (rental).
 * Uses orderID, tradeInRequestID, or rentalID to identify purchase, trade-in, or rental.
 */
router.get("/transactions", async (req, res) => {
    try {
        const { email, type = "all", searchId = "" } = req.query;
        const limitNum = parseInt(req.query.limit, 10) || 5;
        const offsetNum = parseInt(req.query.offset, 10) || 0;

        if (!email) {
            return res.json({
                success: true,
                totalCount: 0,
                offset: offsetNum,
                limit: limitNum,
                hasMore: false,
                transactions: []
            });
        }

        const { customerID, email: userEmail } = await getCustomerInfo(email);
        const targetCustIds = [customerID].filter(Boolean);
        const targetEmails = [email, userEmail].filter(Boolean);

        // 1. Gather all user's orders to track back orderID
        const userOrdersMap = new Map();
        for (const cId of targetCustIds) {
            const snap = await db.collection("order").where("customerID", "==", cId).get();
            snap.forEach(d => {
                userOrdersMap.set(d.id, d.data());
                if (d.data().orderID) userOrdersMap.set(d.data().orderID, d.data());
            });
        }
        for (const em of targetEmails) {
            const snap = await db.collection("order").where("email", "==", em).get();
            snap.forEach(d => {
                userOrdersMap.set(d.id, d.data());
                if (d.data().orderID) userOrdersMap.set(d.data().orderID, d.data());
            });
        }

        // 2. Gather all user's trade-in requests to track back tradeInRequestID
        const userTradeInsMap = new Map();
        for (const em of targetEmails) {
            const snap = await db.collection("tradeInRequests").where("userEmail", "==", em).get();
            snap.forEach(d => {
                userTradeInsMap.set(d.id, d.data());
                if (d.data().tradeInRequestID) userTradeInsMap.set(d.data().tradeInRequestID, d.data());
            });
        }
        for (const cId of targetCustIds) {
            const snap = await db.collection("tradeInRequests").where("userId", "==", cId).get();
            snap.forEach(d => {
                userTradeInsMap.set(d.id, d.data());
                if (d.data().tradeInRequestID) userTradeInsMap.set(d.data().tradeInRequestID, d.data());
            });
        }

        // 3. Gather rentals if rental collection exists
        const userRentalsMap = new Map();
        try {
            for (const em of targetEmails) {
                const snap = await db.collection("rental").where("userEmail", "==", em).get();
                snap.forEach(d => {
                    userRentalsMap.set(d.id, d.data());
                    if (d.data().rentalID) userRentalsMap.set(d.data().rentalID, d.data());
                });
            }
        } catch (_) {}

        // 4. Query transaction collection from Firestore
        const tranSnap = await db.collection("transaction").get();

        // 5. Caches for product, devices, paymentAccount to avoid duplicate queries
        const productCache = new Map();
        const deviceCache = new Map();
        const paymentAccountCache = new Map();

        const allMatchedTransactions = [];

        for (const doc of tranSnap.docs) {
            const t = doc.data();

            let matchedType = null;
            let parentData = null;

            if (t.orderID && userOrdersMap.has(t.orderID)) {
                matchedType = "purchase";
                parentData = userOrdersMap.get(t.orderID);
            } else if (t.tradeInRequestID && userTradeInsMap.has(t.tradeInRequestID)) {
                matchedType = "trade-in";
                parentData = userTradeInsMap.get(t.tradeInRequestID);
            } else if (t.rentalID && userRentalsMap.has(t.rentalID)) {
                matchedType = "rental";
                parentData = userRentalsMap.get(t.rentalID);
            }

            // If not owned by this user, skip
            if (!matchedType) continue;

            const rawAmount = Number(t.transactionAmount || 0);
            const isTrade = matchedType === "trade-in";
            const isRefund = (t.transactionType || "").toLowerCase() === "refund";
            const isPayout = (t.transactionType || "").toLowerCase() === "payout";
            const isCredit = isTrade || isRefund || isPayout;

            // Normalize transaction status
            const rawStatus = (t.transactionStatus || "").toLowerCase();
            let status = "completed";
            if (rawStatus === "fail" || rawStatus === "failed") {
                status = "failed";
            } else if (rawStatus === "pending") {
                status = "pending";
            }

            // Parse date
            let isoDate = new Date().toISOString();
            if (t.transactionDate) {
                if (t.transactionDate._seconds) {
                    isoDate = new Date(t.transactionDate._seconds * 1000).toISOString();
                } else if (typeof t.transactionDate === "string") {
                    isoDate = t.transactionDate;
                }
            } else if (t.createdAt && t.createdAt._seconds) {
                isoDate = new Date(t.createdAt._seconds * 1000).toISOString();
            }

            const dateObj = new Date(isoDate);
            const formattedDate = !isNaN(dateObj.getTime())
                ? dateObj.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" })
                : "Recent";

            // Resolve Payment Method
            let paymentMethod = "Visa •••• 4242";
            const payAccId = t.paymentAccountID || "";
            if (payAccId === "fpx_online_banking") {
                paymentMethod = "FPX Online Banking";
            } else if (payAccId === "ewallet_all") {
                paymentMethod = "Touch 'n Go eWallet";
            } else if (isPayout || isTrade) {
                paymentMethod = "Bank Transfer";
            } else if (payAccId) {
                if (!paymentAccountCache.has(payAccId)) {
                    try {
                        const paSnap = await db.collection("paymentAccount").doc(payAccId).get();
                        paymentAccountCache.set(payAccId, paSnap.exists ? paSnap.data() : null);
                    } catch (_) {
                        paymentAccountCache.set(payAccId, null);
                    }
                }
                const paData = paymentAccountCache.get(payAccId);
                if (paData && paData.cardNumber) {
                    const brand = paData.providerName || "Card";
                    const last4 = paData.cardNumber.slice(-4);
                    paymentMethod = `${brand} •••• ${last4}`;
                }
            }

            // Resolve Title & Related Item
            // Resolve Title & Related Items (supports all products in multi-item orders)
            let title = "Transaction Item";
            const relatedItems = [];

            if (matchedType === "purchase" && parentData) {
                const prodIds = Array.isArray(parentData.productIDs) ? parentData.productIDs : [];
                for (const prodId of prodIds) {
                    if (!productCache.has(prodId)) {
                        try {
                            const pSnap = await db.collection("product").doc(prodId).get();
                            productCache.set(prodId, pSnap.exists ? pSnap.data() : null);
                        } catch (_) {
                            productCache.set(prodId, null);
                        }
                    }
                    const pData = productCache.get(prodId);
                    if (pData) {
                        let itemName = pData.description ? pData.description.split(" - ")[0] : (pData.productName || "Product");
                        let itemImageUrl = pData.imageUrl || "https://res.cloudinary.com/spyhcckw/image/upload/v1792084768/product/sample_iphone14.jpg";
                        let itemImei = "";
                        let itemDeviceId = pData.deviceID || "";
                        let itemStorage = "";
                        let itemColor = "";

                        if (pData.deviceID) {
                            if (!deviceCache.has(pData.deviceID)) {
                                try {
                                    const dSnap = await db.collection("devices").doc(pData.deviceID).get();
                                    deviceCache.set(pData.deviceID, dSnap.exists ? dSnap.data() : null);
                                } catch (_) {
                                    deviceCache.set(pData.deviceID, null);
                                }
                            }
                            const dData = deviceCache.get(pData.deviceID);
                            if (dData) {
                                itemName = [dData.brand, dData.model].filter(Boolean).join(" ") || itemName;
                                itemImei = dData.imeiNum || "";
                                itemDeviceId = dData.deviceID || pData.deviceID || "";
                                itemStorage = dData.storage || dData.storageCapacity || "";
                                itemColor = dData.color || dData.colour || "";
                            }
                        }

                        relatedItems.push({
                            name: itemName,
                            imei: itemImei,
                            deviceID: itemDeviceId,
                            imageUrl: itemImageUrl,
                            storage: itemStorage,
                            color: itemColor
                        });
                    }
                }
                if (relatedItems.length > 0) {
                    title = relatedItems.map(i => i.name).join(", ");
                } else {
                    title = "Product Purchase";
                    relatedItems.push({
                        name: "Product Purchase",
                        imei: "",
                        deviceID: "",
                        imageUrl: "https://res.cloudinary.com/spyhcckw/image/upload/v1792084768/product/sample_iphone14.jpg",
                        storage: "",
                        color: ""
                    });
                }
            } else if (matchedType === "trade-in" && parentData) {
                const devId = parentData.deviceID;
                let itemName = "Trade-In Device";
                let itemImei = parentData.imeiNum || "";
                let itemDeviceId = devId || "";
                let itemImageUrl = "https://res.cloudinary.com/spyhcckw/image/upload/v1792084768/product/sample_iphone14.jpg";
                let itemStorage = "";
                let itemColor = "";

                if (devId) {
                    if (!deviceCache.has(devId)) {
                        try {
                            const dSnap = await db.collection("devices").doc(devId).get();
                            deviceCache.set(devId, dSnap.exists ? dSnap.data() : null);
                        } catch (_) {
                            deviceCache.set(devId, null);
                        }
                    }
                    const dData = deviceCache.get(devId);
                    if (dData) {
                        itemName = [dData.brand, dData.model].filter(Boolean).join(" ") || "Trade-In Device";
                        itemImei = dData.imeiNum || parentData.imeiNum || "";
                        itemDeviceId = dData.deviceID || devId || "";
                        itemStorage = dData.storageCapacity || dData.storage || "";
                        itemColor = dData.colour || dData.color || "";
                    }
                }

                relatedItems.push({
                    name: itemName,
                    imei: itemImei,
                    deviceID: itemDeviceId,
                    imageUrl: itemImageUrl,
                    storage: itemStorage,
                    color: itemColor
                });
                title = itemName;
            } else if (matchedType === "rental") {
                title = "Device Rental";
                relatedItems.push({
                    name: "Device Rental",
                    imei: "",
                    deviceID: "",
                    imageUrl: "https://res.cloudinary.com/spyhcckw/image/upload/v1792084768/product/sample_iphone14.jpg",
                    storage: "",
                    color: ""
                });
            }

            // Breakdown: only base amount and total paid (no tax)
            const baseAmount = Number(parentData?.subtotal || parentData?.finalOfferPrice || rawAmount);

            // Use orderID, tradeInRequestID, or rentalID as primary business ID
            const businessId = (matchedType === "purchase" ? t.orderID : (matchedType === "trade-in" ? t.tradeInRequestID : t.rentalID))
                || t.orderID
                || t.tradeInRequestID
                || t.rentalID
                || t.transactionID
                || doc.id;

            allMatchedTransactions.push({
                id: doc.id,
                transactionId: businessId,
                rawTransactionId: t.transactionID || doc.id,
                orderID: t.orderID || null,
                tradeInRequestID: t.tradeInRequestID || null,
                rentalID: t.rentalID || null,
                title,
                type: matchedType,
                amount: rawAmount,
                isCredit,
                status,
                date: isoDate,
                formattedDate,
                paymentMethod,
                relatedItem: relatedItems[0] || {
                    name: title,
                    imei: "N/A",
                    imageUrl: "https://res.cloudinary.com/spyhcckw/image/upload/v1792084768/product/sample_iphone14.jpg",
                    storage: "",
                    color: ""
                },
                relatedItems,
                breakdown: {
                    baseAmount,
                    taxAmount: 0.00,
                    totalPaid: rawAmount
                }
            });
        }

        // Sort by date (newest first)
        allMatchedTransactions.sort((a, b) => new Date(b.date) - new Date(a.date));

        // Filter by category type ('all', 'purchase', 'trade-in', 'rental')
        let filtered = allMatchedTransactions;
        if (type && type.toLowerCase() !== "all") {
            const cleanType = type.toLowerCase().replace(/s$/, '').replace(/_/g, '-');
            filtered = filtered.filter(tx => {
                const txType = (tx.type || "").toLowerCase().replace(/_/g, '-');
                if (cleanType === "purchase") return txType === "purchase";
                if (cleanType === "trade-in" || cleanType === "tradein") return txType === "trade-in";
                if (cleanType === "rental") return txType === "rental";
                return true;
            });
        }

        // Search bar: strictly search by ID (supports orderID, tradeInRequestID, rentalID, or transactionID)
        if (searchId && searchId.trim().length > 0) {
            const cleanSearch = searchId.trim().toLowerCase().replace(/^#/, '');
            filtered = filtered.filter(tx => {
                const txId = (tx.transactionId || "").toLowerCase().replace(/^#/, '');
                const rawId = (tx.id || "").toLowerCase();
                const rawTxId = (tx.rawTransactionId || "").toLowerCase();
                const ordId = (tx.orderID || "").toLowerCase();
                const trId = (tx.tradeInRequestID || "").toLowerCase();
                const rntId = (tx.rentalID || "").toLowerCase();
                return txId.includes(cleanSearch) || 
                       rawId.includes(cleanSearch) || 
                       rawTxId.includes(cleanSearch) || 
                       ordId.includes(cleanSearch) || 
                       trId.includes(cleanSearch) || 
                       rntId.includes(cleanSearch);
            });
        }

        const totalCount = filtered.length;
        const pagedData = filtered.slice(offsetNum, offsetNum + limitNum);
        const hasMore = (offsetNum + limitNum) < totalCount;

        return res.json({
            success: true,
            totalCount,
            offset: offsetNum,
            limit: limitNum,
            hasMore,
            transactions: pagedData
        });
    } catch (err) {
        console.error("Error fetching transactions:", err);
        return res.status(500).json({ success: false, error: "Failed to fetch transactions" });
    }
});

module.exports = router;

