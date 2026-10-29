const express = require("express");
const { FieldValue } = require("firebase-admin/firestore");
const nodemailer = require("nodemailer");
const crypto = require("crypto");
const db = require("../config/firebase");

const router = express.Router();

function createRecurringFailureMailer() {
    const { REBYTE_SMTP_HOST, REBYTE_SMTP_USER, REBYTE_SMTP_PASSWORD } = process.env;
    if (REBYTE_SMTP_HOST && REBYTE_SMTP_USER && REBYTE_SMTP_PASSWORD) {
        const port = Number(process.env.REBYTE_SMTP_PORT || 587);
        return nodemailer.createTransport({
            host: REBYTE_SMTP_HOST,
            port,
            secure: String(process.env.REBYTE_SMTP_SECURE || "false").toLowerCase() === "true",
            auth: { user: REBYTE_SMTP_USER, pass: REBYTE_SMTP_PASSWORD }
        });
    }

    // Default to ReByte's system Gmail transporter (consistent with taskAssignmentModule)
    return nodemailer.createTransport({
        service: "gmail",
        auth: {
            user: "lolincoln021@gmail.com",
            pass: "uooc wvdf zoqy nujh"
        }
    });
}

const recurringFailureMailer = createRecurringFailureMailer();

function generateReferenceSuffix() {
    return crypto.randomInt(0, 36 ** 4).toString(36).toUpperCase().padStart(4, "0");
}

/**
 * Register phone as rental phone
 * POST /rental/register-phone or /api/rental/register-phone
 * Body: { productID, fcmToken }
 */
router.post("/register-phone", async (req, res) => {
    try {
        const { productID, fcmToken } = req.body;

        if (!productID || String(productID).trim() === "") {
            return res.status(400).json({ error: "Product ID is required." });
        }

        const trimmedProductID = String(productID).trim();

        // Check if product exists by document ID or productID field
        let productRef = db.collection("product").doc(trimmedProductID);
        let productDoc = await productRef.get();

        if (!productDoc.exists) {
            const querySnap = await db.collection("product").where("productID", "==", trimmedProductID).limit(1).get();
            if (querySnap.empty) {
                return res.status(404).json({ error: "Product ID not found." });
            }
            productDoc = querySnap.docs[0];
            productRef = productDoc.ref;
        }

        const productData = productDoc.data() || {};

        // Verify product is in draft status
        const currentListingStatus = String(productData.listingStatus || productData.status || "").trim().toLowerCase();
        if (currentListingStatus !== "draft") {
            return res.status(400).json({ error: "That product is not in draft status." });
        }

        // Determine collected price
        let collectedPrice = 0;
        if (productData.collectedPrice !== undefined && productData.collectedPrice !== null && !isNaN(productData.collectedPrice)) {
            collectedPrice = Number(productData.collectedPrice);
        } else if (productData.tradeInRequestID) {
            try {
                const trDoc = await db.collection("tradeInRequests").doc(productData.tradeInRequestID).get();
                if (trDoc.exists) {
                    const trData = trDoc.data() || {};
                    const fq = trData.finalQuotation || {};
                    if (fq.finalOfferPrice !== undefined && fq.finalOfferPrice !== null && !isNaN(fq.finalOfferPrice)) {
                        collectedPrice = Number(fq.finalOfferPrice);
                    } else if (trData.finalOfferPrice !== undefined && trData.finalOfferPrice !== null && !isNaN(trData.finalOfferPrice)) {
                        collectedPrice = Number(trData.finalOfferPrice);
                    } else if (trData.quotedValue !== undefined && trData.quotedValue !== null && !isNaN(trData.quotedValue)) {
                        collectedPrice = Number(trData.quotedValue);
                    }
                }
            } catch (err) {
                console.error("Error looking up tradeInRequest for collectedPrice:", err);
            }
        }

        if (collectedPrice <= 0 && productData.sellingPrice) {
            const sPrice = Number(productData.sellingPrice);
            if (!isNaN(sPrice) && sPrice > 0) {
                collectedPrice = Math.round((sPrice / 1.2) * 100) / 100;
            }
        }

        const rentPricePerMonth = Math.round(collectedPrice * 0.05 * 100) / 100;
        const resolvedFcmToken = (fcmToken && String(fcmToken).trim().length > 0) ? String(fcmToken).trim() : "";

        // Prepare updates:
        // - delete isPublic attribute
        // - change listingStatus to rent
        // - delete marketVisibility / marketplaceVisibility attribute
        // - delete sellingPrice attribute
        // - change status to rent
        // - add rentPricePerMonth: collected price * 0.05
        // - add fcmToken attribute with retrieved fcmToken
        const updates = {
            listingStatus: "rent",
            status: "rent",
            rentPricePerMonth: rentPricePerMonth,
            fcmToken: resolvedFcmToken,
            fckToken: FieldValue.delete(),
            isPublic: FieldValue.delete(),
            marketVisibility: FieldValue.delete(),
            marketplaceVisibility: FieldValue.delete(),
            sellingPrice: FieldValue.delete(),
            updatedAt: FieldValue.serverTimestamp(),
        };

        if (collectedPrice > 0 && productData.collectedPrice === undefined) {
            updates.collectedPrice = collectedPrice;
        }

        await productRef.update(updates);

        return res.status(200).json({
            success: true,
            message: "Product successfully registered as rental phone.",
            productID: trimmedProductID,
            rentPricePerMonth,
            fcmToken: resolvedFcmToken,
        });
    } catch (error) {
        console.error("Error registering rental phone:", error);
        return res.status(500).json({ error: "Internal server error registering rental phone." });
    }
});

/**
 * Lock rental device via FCM
 * POST /rental/lock-device or /api/rental/lock-device
 * Body: { productID }
 */
router.post("/lock-device", async (req, res) => {
    try {
        const { productID } = req.body;
        if (!productID || String(productID).trim() === "") {
            return res.status(400).json({ error: "Product ID is required." });
        }

        const trimmedProductID = String(productID).trim();

        // 1. Locate product record in Firestore
        let productRef = db.collection("product").doc(trimmedProductID);
        let productDoc = await productRef.get();

        if (!productDoc.exists) {
            const querySnap = await db.collection("product").where("productID", "==", trimmedProductID).limit(1).get();
            if (querySnap.empty) {
                return res.status(404).json({ error: "Product not found." });
            }
            productDoc = querySnap.docs[0];
            productRef = productDoc.ref;
        }

        const productData = productDoc.data() || {};
        const fcmToken = productData.fcmToken || productData.fckToken;

        if (!fcmToken || String(fcmToken).trim() === "") {
            return res.status(400).json({ error: "No FCM token registered for this rental device." });
        }

        // 2. Send FCM message: LOCK_DEVICE
        const { getMessaging } = require("firebase-admin/messaging");
        const messaging = getMessaging();

        const message = {
            token: String(fcmToken).trim(),
            data: {
                action: "LOCK_DEVICE",
                command: "LOCK_DEVICE",
                productID: trimmedProductID,
                title: "ReByte Rental Device",
                message: "This device has been restricted. Please complete payment or contact ReByte."
            },
            android: {
                priority: "high"
            }
        };

        const fcmResponse = await messaging.send(message);
        console.log(`[FCM] Sent LOCK_DEVICE to product ${trimmedProductID} (${fcmToken}):`, fcmResponse);

        // 3. Update device status to Lock in Firestore
        await productRef.update({
            listingStatus: "Lock",
            status: "Lock",
            isRestricted: true,
            restrictedAt: FieldValue.delete(),
            lastLockCommandAt: FieldValue.delete(),
            updatedAt: FieldValue.serverTimestamp()
        }).catch(err => console.error("Error updating product restriction state:", err));

        return res.status(200).json({
            success: true,
            message: `Lock command sent to device (${trimmedProductID}). Status changed to Lock.`,
            fcmResponse,
            productID: trimmedProductID
        });
    } catch (error) {
        console.error("Error sending lock command:", error);
        return res.status(500).json({ error: error.message || "Failed to send lock command to device." });
    }
});

/**
 * Unlock rental device via FCM
 * POST /rental/unlock-device or /api/rental/unlock-device
 * Body: { productID }
 */
router.post("/unlock-device", async (req, res) => {
    try {
        const { productID } = req.body;
        if (!productID || String(productID).trim() === "") {
            return res.status(400).json({ error: "Product ID is required." });
        }

        const trimmedProductID = String(productID).trim();

        // 1. Locate product record in Firestore
        let productRef = db.collection("product").doc(trimmedProductID);
        let productDoc = await productRef.get();

        if (!productDoc.exists) {
            const querySnap = await db.collection("product").where("productID", "==", trimmedProductID).limit(1).get();
            if (querySnap.empty) {
                return res.status(404).json({ error: "Product not found." });
            }
            productDoc = querySnap.docs[0];
            productRef = productDoc.ref;
        }

        const productData = productDoc.data() || {};
        const fcmToken = productData.fcmToken || productData.fckToken;

        if (!fcmToken || String(fcmToken).trim() === "") {
            return res.status(400).json({ error: "No FCM token registered for this rental device." });
        }

        // 2. Send FCM message: UNLOCK_DEVICE
        const { getMessaging } = require("firebase-admin/messaging");
        const messaging = getMessaging();

        const message = {
            token: String(fcmToken).trim(),
            data: {
                action: "UNLOCK_DEVICE",
                command: "UNLOCK_DEVICE",
                productID: trimmedProductID,
                title: "ReByte Device Unlocked",
                message: "Restriction lifted. Device restored to normal operation."
            },
            android: {
                priority: "high"
            }
        };

        const fcmResponse = await messaging.send(message);
        console.log(`[FCM] Sent UNLOCK_DEVICE to product ${trimmedProductID} (${fcmToken}):`, fcmResponse);

        // 3. Update device status back to Renting in Firestore
        await productRef.update({
            listingStatus: "renting",
            status: "renting",
            isRestricted: false,
            unlockedAt: FieldValue.delete(),
            lastUnlockCommandAt: FieldValue.delete(),
            updatedAt: FieldValue.serverTimestamp()
        }).catch(err => console.error("Error updating product restriction state:", err));

        return res.status(200).json({
            success: true,
            message: `Unlock command sent to device (${trimmedProductID}). Status restored to Renting.`,
            fcmResponse,
            productID: trimmedProductID
        });
    } catch (error) {
        console.error("Error sending unlock command:", error);
        return res.status(500).json({ error: error.message || "Failed to send unlock command to device." });
    }
});

/**
 * Helper to generate rentalID format: YYMMRENXXXXX
 * (XXXXX sequence number, take last same YYMM record + 1, if not just 00001)
 */
async function generateRentalID() {
    const now = new Date();
    const yy = String(now.getFullYear()).slice(-2);
    const mm = String(now.getMonth() + 1).padStart(2, '0');
    const prefix = `${yy}${mm}REN`;

    let maxSequence = 0;
    try {
        const snapshot = await db.collection("rental")
            .where("rentalID", ">=", prefix)
            .where("rentalID", "<=", prefix + "\uf8ff")
            .get();

        snapshot.forEach((doc) => {
            const rId = doc.data().rentalID || doc.id || "";
            if (rId.startsWith(prefix)) {
                const seqPart = rId.slice(prefix.length);
                const parsed = parseInt(seqPart, 10);
                if (!isNaN(parsed) && parsed > maxSequence) {
                    maxSequence = parsed;
                }
            }
        });
    } catch (e) {
        console.error("Error finding largest sequence number for rentalID:", e);
    }

    const nextSequence = maxSequence + 1;
    const sequenceFormatted = String(nextSequence).padStart(5, '0');
    return `${prefix}${sequenceFormatted}`;
}

/**
 * Format a Date object to YYYY-MM-DD
 */
function formatDateToYMD(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
}

/**
 * Helper to resolve customerID (userID) from email or userID
 */
async function resolveCustomerID(emailOrId) {
    if (!emailOrId) return "";
    try {
        const docSnap = await db.collection("users").doc(emailOrId).get();
        if (docSnap.exists) {
            const u = docSnap.data();
            return u.userId || docSnap.id;
        }

        const querySnap = await db.collection("users").where("email", "==", emailOrId).limit(1).get();
        if (!querySnap.empty) {
            const u = querySnap.docs[0].data();
            return u.userId || querySnap.docs[0].id;
        }
    } catch (e) {
        console.error("Error resolving customerID:", e);
    }
    return emailOrId;
}

const axios = require("axios");

const XENDIT_SECRET_KEY = process.env.XENDIT_SECRET_KEY || "";
const getXenditAuthHeader = () => {
    const authString = Buffer.from(`${XENDIT_SECRET_KEY}:`).toString("base64");
    return {
        Authorization: `Basic ${authString}`,
        "Content-Type": "application/json"
    };
};

/**
 * Create Rental Payment Session (PAY_AND_SAVE)
 * POST /rental/create-rental-session or /api/rental/create-rental-session
 * Initial payment collects upfront deposit + first month rental, and forces tokenization of payment method.
 */
router.post("/create-rental-session", async (req, res) => {
    try {
        const { email, amount, description, productID, durationMonths } = req.body;
        if (!email || !amount) {
            return res.status(400).json({ success: false, error: "email and amount are required." });
        }

        const sessionRefId = `rentalsess_${Date.now()}_${generateReferenceSuffix()}`;

        // Resolve customer name if available
        let givenName = "ReByte Customer";
        try {
            const userSnap = await db.collection("users").where("email", "==", email).limit(1).get();
            if (!userSnap.empty) {
                const uData = userSnap.docs[0].data();
                givenName = uData.name || uData.username || uData.given_names || givenName;
            }
        } catch (_) {}

        // Check if customer already exists in Xendit
        const custRef = `cust_${String(email).replace(/[^a-zA-Z0-9]/g, '_')}`;
        let xenditCustomerId = null;
        try {
            const fetchRes = await axios.get(`https://api.xendit.co/customers?reference_id=${encodeURIComponent(custRef)}`, {
                headers: {
                    ...getXenditAuthHeader(),
                    "api-version": "2020-10-31"
                }
            });
            if (fetchRes.data && Array.isArray(fetchRes.data.data) && fetchRes.data.data.length > 0) {
                xenditCustomerId = fetchRes.data.data[0].id;
            }
        } catch (fetchErr) {
            console.error("Error looking up Xendit customer:", fetchErr.response?.data || fetchErr.message);
        }

        const sessionPayload = {
            reference_id: sessionRefId,
            session_type: "PAY",
            allow_save_payment_method: "FORCED",
            payment_method_type: "CARD",
            currency: "MYR",
            amount: Number(amount),
            mode: "PAYMENT_LINK",
            country: "MY",
            locale: "en",
            description: description || `ReByte Rental Checkout`,
            success_return_url: "https://rebyte.local/payment-success",
            cancel_return_url: "https://rebyte.local/payment-failure"
        };

        if (xenditCustomerId) {
            sessionPayload.customer_id = xenditCustomerId;
        } else {
            sessionPayload.customer = {
                reference_id: custRef,
                type: "INDIVIDUAL",
                individual_detail: {
                    given_names: givenName
                }
            };
        }

        const sessionRes = await axios.post("https://api.xendit.co/sessions", sessionPayload, {
            headers: getXenditAuthHeader()
        });

        const data = sessionRes.data;
        return res.json({
            success: true,
            sessionId: data.payment_session_id,
            sessionUrl: data.payment_link_url,
            customerId: data.customer_id,
            referenceId: data.reference_id
        });
    } catch (err) {
        console.error("Error creating rental payment session:", err.response?.data || err.message);
        return res.status(500).json({
            success: false,
            error: err.response?.data?.message || err.message || "Failed to create rental payment session"
        });
    }
});

/**
 * Create Rental Record
 * POST /rental/create-rental or /api/rental/create-rental
 * Body: { customerID, email, productID, durationMonths, monthlyRentalFee, addressID, paymentAccountID, paymentTokenID, xenditCustomerID }
 */
router.post("/create-rental", async (req, res) => {
    try {
        const {
            customerID: reqCustomerID,
            email,
            productID,
            durationMonths,
            monthlyRentalFee: reqMonthlyRentalFee,
            depositAmount: reqDepositAmount,
            addressID,
            paymentAccountID,
            paymentTokenID,
            xenditCustomerID
        } = req.body;

        if (!productID || String(productID).trim() === "") {
            return res.status(400).json({ error: "Product ID is required." });
        }

        const trimmedProductID = String(productID).trim();

        // 1. Locate product
        let productRef = db.collection("product").doc(trimmedProductID);
        let productDoc = await productRef.get();

        if (!productDoc.exists) {
            const querySnap = await db.collection("product").where("productID", "==", trimmedProductID).limit(1).get();
            if (querySnap.empty) {
                return res.status(404).json({ error: "Product not found." });
            }
            productDoc = querySnap.docs[0];
            productRef = productDoc.ref;
        }

        const productData = productDoc.data() || {};

        // 2. Resolve customerID
        let customerID = reqCustomerID;
        if (!customerID && email) {
            customerID = await resolveCustomerID(email);
        } else if (customerID) {
            customerID = await resolveCustomerID(customerID);
        }
        if (!customerID) {
            customerID = email || "Unknown";
        }

        // 3. Resolve collectedPrice
        let collectedPrice = 0;
        if (productData.collectedPrice !== undefined && productData.collectedPrice !== null && !isNaN(productData.collectedPrice)) {
            collectedPrice = Number(productData.collectedPrice);
        } else if (productData.tradeInRequestID) {
            try {
                const trDoc = await db.collection("tradeInRequests").doc(productData.tradeInRequestID).get();
                if (trDoc.exists) {
                    const trData = trDoc.data() || {};
                    const fq = trData.finalQuotation || {};
                    if (fq.finalOfferPrice !== undefined && fq.finalOfferPrice !== null && !isNaN(fq.finalOfferPrice)) {
                        collectedPrice = Number(fq.finalOfferPrice);
                    } else if (trData.finalOfferPrice !== undefined && trData.finalOfferPrice !== null && !isNaN(trData.finalOfferPrice)) {
                        collectedPrice = Number(trData.finalOfferPrice);
                    } else if (trData.quotedValue !== undefined && trData.quotedValue !== null && !isNaN(trData.quotedValue)) {
                        collectedPrice = Number(trData.quotedValue);
                    }
                }
            } catch (err) {
                console.error("Error looking up tradeInRequest for collectedPrice:", err);
            }
        }
        if (collectedPrice <= 0 && productData.sellingPrice) {
            const sPrice = Number(productData.sellingPrice);
            if (!isNaN(sPrice) && sPrice > 0) {
                collectedPrice = Math.round((sPrice / 1.2) * 100) / 100;
            }
        }

        // depositAmount = ceil(collectedPrice * 0.1)
        let depositAmount = Math.ceil(collectedPrice * 0.1);
        if (reqDepositAmount !== undefined && !isNaN(Number(reqDepositAmount)) && Number(reqDepositAmount) > 0) {
            depositAmount = Math.ceil(Number(reqDepositAmount));
        }

        // 4. Monthly rental fee calculation
        let monthlyRentalFee = 0;
        if (reqMonthlyRentalFee !== undefined && !isNaN(Number(reqMonthlyRentalFee))) {
            monthlyRentalFee = Number(reqMonthlyRentalFee);
        } else if (productData.rentPricePerMonth !== undefined && !isNaN(Number(productData.rentPricePerMonth))) {
            monthlyRentalFee = Number(productData.rentPricePerMonth);
        } else if (productData.rentalPrice !== undefined && !isNaN(Number(productData.rentalPrice))) {
            monthlyRentalFee = Number(productData.rentalPrice);
        } else if (productData.monthlyRentalPrice !== undefined && !isNaN(Number(productData.monthlyRentalPrice))) {
            monthlyRentalFee = Number(productData.monthlyRentalPrice);
        } else {
            monthlyRentalFee = Math.round(collectedPrice * 0.05 * 100) / 100;
        }

        // 5. Calculate dates
        // durationMonths = total agreed lease duration
        // startDate = date of rental
        // endDate = end of lease agreement (e.g. 12 months later)
        // rentalExpiryDate = date until which current payment covers (1st month payment = 1 month later)
        const months = parseInt(durationMonths, 10) || 1;
        const now = new Date();
        const startDate = formatDateToYMD(now);

        const expDate = new Date(now.getFullYear(), now.getMonth() + months, now.getDate());
        const endDate = formatDateToYMD(expDate);

        // Current payment covers 1 month from startDate
        const firstPaidCoverageDate = new Date(now.getFullYear(), now.getMonth() + 1, now.getDate());
        const rentalExpiryDate = formatDateToYMD(firstPaidCoverageDate);

        // 6. Generate rentalID (YYMMRENXXXXX)
        const rentalID = await generateRentalID();
        const xenditReferenceSuffix = generateReferenceSuffix();

        // 7. Create a no-charge Xendit SAVE session for recurring-capable Malaysian
        // e-wallets. Xendit's allowed_payment_channels is the provider-side restriction,
        // so the hosted checkout offers these wallets and does not offer cards.
        let xenditRecurringPlanID = null;
        let xenditRecurringStatus = "requires_action";
        let xenditRecurringAuthUrl = null;
        let xenditRecurringAuthSessionID = null;
        let xenditCustomerId = xenditCustomerID || null;
        let recurringWalletChannels = ["TOUCHNGO", "SHOPEEPAY", "GRABPAY"];

        const customerReference = `rebyte${String(rentalID).replace(/[^a-zA-Z0-9]/g, "")}${xenditReferenceSuffix}`;
        const givenNames = String(email || "Customer")
            .split("@")[0]
            .replace(/[^a-zA-Z0-9]/g, "") || "Customer";
        const walletSessionPayload = {
            reference_id: `rentalauth${String(rentalID).replace(/[^a-zA-Z0-9]/g, "")}${xenditReferenceSuffix}`,
            session_type: "SAVE",
            mode: "PAYMENT_LINK",
            amount: 0,
            currency: "MYR",
            country: "MY",
            locale: "en",
            description: `Authorize recurring rental payments for rental ${rentalID}`,
            ...(xenditCustomerId
                ? { customer_id: xenditCustomerId }
                : {
                    customer: {
                        reference_id: customerReference,
                        type: "INDIVIDUAL",
                        email: email || undefined,
                        individual_detail: { given_names: givenNames }
                    }
                }),
            success_return_url: "https://rebyte.local/payment-success",
            cancel_return_url: "https://rebyte.local/payment-failure"
        };

        try {
            let walletSessionRes = null;
            while (!walletSessionRes && recurringWalletChannels.length > 0) {
                try {
                    walletSessionRes = await axios.post(
                        "https://api.xendit.co/sessions",
                        { ...walletSessionPayload, allowed_payment_channels: recurringWalletChannels },
                        { headers: { ...getXenditAuthHeader(), "api-version": "2026-01-01" } }
                    );
                } catch (channelErr) {
                    const errorCode = String(channelErr.response?.data?.error_code || "").toUpperCase();
                    const errorMessage = String(channelErr.response?.data?.message || "").toUpperCase();
                    const unavailableChannels = recurringWalletChannels.filter(channel => errorMessage.includes(channel));
                    if (errorCode !== "INVALID_PAYMENT_CHANNEL" || unavailableChannels.length === 0) {
                        throw channelErr;
                    }

                    // Xendit rejects requested channels that are not enabled for this
                    // merchant. Retry with the remaining recurring-capable wallets.
                    recurringWalletChannels = recurringWalletChannels.filter(
                        channel => !unavailableChannels.includes(channel)
                    );
                }
            }
            if (!walletSessionRes) {
                throw new Error("No recurring-capable e-wallet channels are enabled for this merchant.");
            }
            xenditRecurringAuthUrl = walletSessionRes.data?.payment_link_url || null;
            xenditRecurringAuthSessionID = walletSessionRes.data?.payment_session_id || null;
            xenditCustomerId = walletSessionRes.data?.customer_id || xenditCustomerId;

            if (!xenditRecurringAuthUrl || !xenditRecurringAuthSessionID) {
                throw new Error("Xendit did not return an e-wallet authorization session.");
            }
        } catch (sessionErr) {
            console.error("Xendit e-wallet authorization session failed:", sessionErr.response?.data || sessionErr.message);
            throw new Error("Unable to start recurring e-wallet authorization. Please try again.");
        }

        // 8. Attributes for rental collection including addressID & paymentAccountID
        const rentalRecord = {
            rentalID,
            rentalStatus: "renting",
            startDate,
            endDate,
            rentalExpiryDate,
            monthlyRentalFee,
            depositAmount,
            depositStatus: "paid",
            customerID,
            productID: productData.productID || trimmedProductID,
            addressID: addressID || "",
            paymentAccountID: paymentAccountID || "",
            durationMonths: months,
            paymentTokenID: "",
            xenditCustomerID: xenditCustomerId || "",
            recurringPlanID: xenditRecurringPlanID,
            recurringStatus: xenditRecurringStatus,
            recurringAuthUrl: xenditRecurringAuthUrl || null,
            recurringAuthSessionID: xenditRecurringAuthSessionID,
            xenditReferenceSuffix,
            recurringApiVersion: "2026-01-01",
        };

        // Create rental document with rentalID as doc ID
        await db.collection("rental").doc(rentalID).set(rentalRecord);

        // Update product status & listingStatus to 'renting'
        await productRef.update({
            status: "renting",
            listingStatus: "renting",
        });

        return res.status(201).json({
            success: true,
            message: "Rental record created successfully.",
            rental: rentalRecord,
            recurringAuthUrl: xenditRecurringAuthUrl || null,
            recurringAuthSessionID: xenditRecurringAuthSessionID,
            recurringStatus: xenditRecurringStatus,
        });
    } catch (error) {
        console.error("Error creating rental record:", error);
        return res.status(500).json({ error: error.message || "Internal server error creating rental record." });
    }
});

/**
 * Helper to generate transactionID format: YYMMDDTRANXXXXX
 */
async function generateTransactionID() {
    const now = new Date();
    const yy = String(now.getFullYear()).slice(-2);
    const mm = String(now.getMonth() + 1).padStart(2, '0');
    const dd = String(now.getDate()).padStart(2, '0');
    const prefix = `${yy}${mm}${dd}TRAN`;

    let maxSequence = 0;
    try {
        const snapshot = await db.collection("transaction")
            .where("transactionID", ">=", prefix)
            .where("transactionID", "<=", prefix + "\uf8ff")
            .get();

        snapshot.forEach((doc) => {
            const tId = doc.data().transactionID || doc.id || "";
            if (tId.startsWith(prefix)) {
                const seqPart = tId.slice(prefix.length);
                const parsed = parseInt(seqPart, 10);
                if (!isNaN(parsed) && parsed > maxSequence) {
                    maxSequence = parsed;
                }
            }
        });
    } catch (e) {
        console.error("Error finding largest sequence number for transactionID:", e);
    }

    const nextSequence = maxSequence + 1;
    const sequenceFormatted = String(nextSequence).padStart(5, '0');
    return `${prefix}${sequenceFormatted}`;
}

/**
 * Common handler for a successful recurring rental cycle:
 * Creates transaction record in 'transaction' collection,
 * advances rentalExpiryDate by monthsToPay (default 1), sets status to 'renting'.
 * deductCycles: boolean - only TRUE when customer manually pays rental in advance via 'Pay Rental'.
 * Normal scheduled recurring charges executed by Xendit must NOT deduct cycles.
 */
async function processSuccessfulRentalCycle(rentalDoc, cycleData = {}, gatewayTxId = "", monthsToPay = 1, deductCycles = false) {
    const rentalData = rentalDoc.data() || {};
    const rentalID = rentalData.rentalID || rentalDoc.id;
    const countMonths = Math.max(1, parseInt(monthsToPay, 10) || 1);
    const monthlyFee = Number(rentalData.monthlyRentalFee || 75);
    const chargeAmount = Number(cycleData.amount || (monthlyFee * countMonths));
    const now = new Date();

    // Check if a transaction for this gatewayTxId or cycle was already created
    if (gatewayTxId) {
        const existingTxn = await db.collection("transaction")
            .where("gatewayTransactionID", "==", gatewayTxId)
            .limit(1)
            .get();
        if (!existingTxn.empty) {
            console.log(`[Recurring Cycle] Transaction already processed for gateway ID ${gatewayTxId}`);
            return existingTxn.docs[0].data();
        }
    }

    // 1. Calculate new expiry date (+countMonths from current rentalExpiryDate or now)
    let currentExpiry = now;
    if (rentalData.rentalExpiryDate) {
        const parsed = new Date(rentalData.rentalExpiryDate);
        if (!isNaN(parsed.getTime())) currentExpiry = parsed;
    }
    const newExpiry = new Date(currentExpiry.getFullYear(), currentExpiry.getMonth() + countMonths, currentExpiry.getDate());
    
    // Clamp to endDate if endDate is present
    if (rentalData.endDate) {
        const parsedEnd = new Date(rentalData.endDate);
        if (!isNaN(parsedEnd.getTime()) && newExpiry > parsedEnd) {
            newExpiry.setTime(parsedEnd.getTime());
        }
    }
    const newExpiryStr = formatDateToYMD(newExpiry);

    // 2. Generate standard transactionID
    const transactionID = await generateTransactionID();

    const paymentAccountID = cycleData.paymentAccountID || rentalData.paymentAccountID || "";

    const transactionData = {
        transactionID,
        transactionType: "Rental",
        transactionStatus: "Success",
        transactionAmount: chargeAmount,
        transactionDate: FieldValue.serverTimestamp(),
        rentalID,
        customerID: rentalData.customerID || "",
        paymentAccountID: paymentAccountID,
        gatewayTransactionID: gatewayTxId || cycleData.id || `xendit_rec_${Date.now()}`,
        recurringCycleID: cycleData.id || "",
        monthsPaid: countMonths,
        createdAt: now.toISOString()
    };

    await db.collection("transaction").doc(transactionID).set(transactionData);

    let effectiveExpiryStr = newExpiryStr;

    // 3. Update Xendit recurring plan cycles (ONLY when deductCycles is true, e.g. manual pay rental)
    let cyclesDeducted = 0;
    let remainingCyclesCount = null;
    const planId = rentalData.recurringPlanID;

    if (deductCycles && planId && !String(planId).startsWith("rec_plan_")) {
        try {
            // Determine effective API version (2026-01-01 preferred for newer plans, fallback to 2022-04-10)
            const candidateVersions = [
                rentalData.recurringApiVersion,
                "2026-01-01",
                "2022-04-10"
            ].filter((v, idx, arr) => Boolean(v) && arr.indexOf(v) === idx);

            let planData = null;
            let effectiveApiVersion = "2026-01-01";

            for (const v of candidateVersions) {
                try {
                    const pRes = await axios.get(`https://api.xendit.co/recurring/plans/${planId}`, {
                        headers: {
                            ...getXenditAuthHeader(),
                            "api-version": v
                        }
                    });
                    if (pRes.data && pRes.data.id) {
                        planData = pRes.data;
                        effectiveApiVersion = v;
                        break;
                    }
                } catch (pErr) {
                    // Try next version
                }
            }

            console.log(`[Xendit Plan] Retrieved plan ${planId} with api-version ${effectiveApiVersion}. Status: ${planData?.status}, current total_recurrence: ${planData?.schedule?.total_recurrence}`);

            console.log(`[Xendit Plan] Need to cancel ${countMonths} upcoming cycle(s) sequentially for plan ${planId}...`);

            effectiveExpiryStr = newExpiryStr;

            // Xendit generates upcoming cycles dynamically (typically 1 upcoming cycle at a time).
            // When Cycle N is cancelled, Xendit immediately spawns Cycle N+1.
            // Therefore, we loop countMonths times, re-fetching the active SCHEDULED cycle in each iteration and cancelling it!
            let lastCancelledTimestamp = null;
            for (let i = 0; i < countMonths; i++) {
                try {
                    const cyclesRes = await axios.get(`https://api.xendit.co/recurring/plans/${planId}/cycles`, {
                        headers: {
                            ...getXenditAuthHeader(),
                            "api-version": effectiveApiVersion
                        }
                    });
                    const cyclesList = Array.isArray(cyclesRes.data?.data) ? cyclesRes.data.data : (Array.isArray(cyclesRes.data) ? cyclesRes.data : []);
                    const currentScheduled = cyclesList.find(c => {
                        const s = String(c.status || "").toUpperCase();
                        return s === "SCHEDULED" || s === "CREATED" || s === "PENDING";
                    });

                    if (currentScheduled && currentScheduled.id) {
                        lastCancelledTimestamp = currentScheduled.scheduled_timestamp || lastCancelledTimestamp;
                        const cancelRes = await axios.post(
                            `https://api.xendit.co/recurring/plans/${planId}/cycles/${currentScheduled.id}/cancel`,
                            {},
                            {
                                headers: {
                                    ...getXenditAuthHeader(),
                                    "api-version": effectiveApiVersion,
                                    "Content-Type": "application/json"
                                }
                            }
                        );
                        cyclesDeducted++;
                        console.log(`[Xendit Cycle] Successfully cancelled cycle #${currentScheduled.cycle_number} (ID: ${currentScheduled.id}, Month ${i + 1}/${countMonths}). Status: ${cancelRes.data?.status || 'CANCELLED'}`);
                    } else {
                        console.log(`[Xendit Cycle] No more scheduled cycles found to cancel at step ${i + 1}/${countMonths}.`);
                        break;
                    }
                } catch (cycleErr) {
                    console.warn(`[Xendit Cycle Warning] Could not cancel cycle at step ${i + 1}/${countMonths}:`, cycleErr.response?.data || cycleErr.message);
                    break;
                }
            }

            // Determine remaining contract cycles from durationMonths
            const contractDuration = parseInt(rentalData.durationMonths, 10) || 0;
            const previousRemaining = (rentalData.remainingCycles !== undefined && rentalData.remainingCycles !== null)
                ? parseInt(rentalData.remainingCycles, 10)
                : Math.max(0, contractDuration - 1);
            remainingCyclesCount = Math.max(0, previousRemaining - countMonths);

            // Sync rentalExpiryDate with the latest cycle billing date from Xendit
            // EXCEPT when the final payment has been made (remainingCyclesCount === 0),
            // where the rentalExpiryDate MUST reach the agreement's full endDate!
            if (remainingCyclesCount === 0 && rentalData.endDate) {
                effectiveExpiryStr = rentalData.endDate;
                console.log(`[Rental Expiry] Final rental payment completed. Setting rentalExpiryDate to full endDate: ${effectiveExpiryStr}`);
            } else {
                try {
                    const refreshedRes = await axios.get(`https://api.xendit.co/recurring/plans/${planId}/cycles`, {
                        headers: {
                            ...getXenditAuthHeader(),
                            "api-version": effectiveApiVersion
                        }
                    });
                    const refreshedCycles = Array.isArray(refreshedRes.data?.data) ? refreshedRes.data.data : (Array.isArray(refreshedRes.data) ? refreshedRes.data : []);
                    
                    // First check for the newly spawned upcoming SCHEDULED cycle
                    const nextActiveCycle = refreshedCycles.find(c => {
                        const s = String(c.status || "").toUpperCase();
                        return s === "SCHEDULED" || s === "CREATED" || s === "PENDING";
                    });

                    const cycleTimestamp = nextActiveCycle?.scheduled_timestamp || lastCancelledTimestamp;
                    if (cycleTimestamp) {
                        const cycleDate = new Date(cycleTimestamp);
                        if (!isNaN(cycleDate.getTime())) {
                            effectiveExpiryStr = formatDateToYMD(cycleDate);
                            console.log(`[Rental Expiry] Synchronized rentalExpiryDate with Xendit cycle billing date: ${effectiveExpiryStr} (from ${cycleTimestamp})`);
                        }
                    }
                } catch (syncErr) {
                    console.warn(`[Rental Expiry Warning] Could not sync with Xendit cycle date:`, syncErr.message);
                }
            }

            // Check if contract has fully ended (newExpiry >= endDate OR remainingCyclesCount === 0)
            const hasContractEnded = rentalData.endDate ? (newExpiry >= new Date(rentalData.endDate)) : false;

            // CRITICAL: NEVER deactivate the plan while remainingCyclesCount > 0!
            // Because Xendit only generates 1 upcoming cycle at a time (scheduledCycles.length === 1),
            // checking remainingCyclesCount === 0 against scheduledCycles caused premature plan deactivation!
            if (hasContractEnded && remainingCyclesCount === 0) {
                try {
                    await axios.post(
                        `https://api.xendit.co/recurring/plans/${planId}/deactivate`,
                        {},
                        {
                            headers: {
                                ...getXenditAuthHeader(),
                                "api-version": effectiveApiVersion,
                                "Content-Type": "application/json"
                            }
                        }
                    );
                    console.log(`[Xendit Plan] All recurring cycles fulfilled. Deactivated plan ${planId}`);
                } catch (deactErr) {
                    console.warn(`[Xendit Plan Warning] Could not deactivate plan ${planId}:`, deactErr.response?.data || deactErr.message);
                }
            } else {
                console.log(`[Xendit Plan] Plan ${planId} remains ACTIVE with ${remainingCyclesCount} contract cycle(s) left.`);
            }
        } catch (planErr) {
            console.warn(`[Xendit Recurring Update Warning]:`, planErr.response?.data || planErr.message);
        }
    }

    // 4. Update rental document
    // If all remaining cycles have been paid/fulfilled or the rental has reached/passed endDate, clamp rentalExpiryDate to endDate
    if (rentalData.endDate) {
        const parsedEndDate = new Date(rentalData.endDate);
        const parsedEffective = new Date(effectiveExpiryStr);
        if (!isNaN(parsedEndDate.getTime()) && (remainingCyclesCount === 0 || parsedEffective >= parsedEndDate)) {
            effectiveExpiryStr = rentalData.endDate;
        }
    }

    const rentalUpdates = {
        rentalStatus: "renting",
        rentalExpiryDate: effectiveExpiryStr,
        lastRecurringSuccess: now.toISOString(),
        lastRecurringCycleID: cycleData.id || "",
        updatedAt: now.toISOString()
    };
    if (cyclesDeducted > 0) {
        rentalUpdates.cyclesDeducted = FieldValue.increment(cyclesDeducted);
    }
    if (remainingCyclesCount !== null) {
        rentalUpdates.remainingCycles = remainingCyclesCount;
        if (remainingCyclesCount === 0) {
            rentalUpdates.recurringStatus = "completed";
        }
    }

    await rentalDoc.ref.update(rentalUpdates);

    console.log(`[Recurring Cycle SUCCESS] Rental ${rentalID} extended to ${effectiveExpiryStr} (${countMonths} month(s), deducted ${cyclesDeducted} Xendit cycles). Transaction: ${transactionID}`);
    return transactionData;
}

/**
 * Record a failed recurring charge and notify the customer. A payment failure
 * does not itself change the rental status; overdue handling is a separate flow.
 */
async function processFailedRentalCycle(rentalDoc, cycleData = {}, reason = "") {
    const rentalData = rentalDoc.data() || {};
    const rentalID = rentalData.rentalID || rentalDoc.id;
    const monthlyFee = Number(cycleData.amount || rentalData.monthlyRentalFee || 75);
    const now = new Date();
    const failReason = String(
        reason || cycleData.failure_code || cycleData.failure_reason || cycleData.failure_message ||
        cycleData.reason || cycleData.failure?.message || "Payment declined by issuer or insufficient funds."
    );

    // Xendit can retry webhook delivery. Reuse the failed-cycle record so one
    // cycle does not create duplicate transactions or duplicate emails.
    const cycleID = cycleData.id || cycleData.cycle_id || "";
    let transactionRef;
    let transactionData;
    if (cycleID) {
        const existing = await db.collection("transaction")
            .where("recurringCycleID", "==", cycleID)
            .limit(1)
            .get();
        const existingFailure = existing.docs.find(doc => doc.data().transactionStatus === "Fail");
        if (existingFailure) {
            transactionRef = existingFailure.ref;
            transactionData = existingFailure.data();
        }
    }

    if (!transactionData) {
        const transactionID = await generateTransactionID();
        transactionRef = db.collection("transaction").doc(transactionID);
        transactionData = {
            transactionID,
            transactionType: "Rental",
            transactionStatus: "Fail",
            transactionAmount: monthlyFee,
            transactionDate: FieldValue.serverTimestamp(),
            rentalID,
            customerID: rentalData.customerID || "",
            paymentAccountID: rentalData.paymentAccountID || "",
            gatewayTransactionID: cycleID || `fail_rec_${Date.now()}`,
            recurringCycleID: cycleID,
            failureReason: failReason,
            createdAt: now.toISOString(),
            failureEmailStatus: "pending"
        };
        await transactionRef.set(transactionData);
    }

    await rentalDoc.ref.update({
        lastRecurringError: failReason,
        lastRecurringFailure: now.toISOString(),
        lastRecurringFailureTransactionID: transactionData.transactionID,
        updatedAt: now.toISOString()
    });

    if (transactionData.failureEmailStatus !== "sent") {
        try {
            let customerEmail = rentalData.email || rentalData.customerEmail || "";
            const customerID = rentalData.customerID || "";
            if (!customerEmail && customerID) {
                const customerSnap = await db.collection("users").doc(customerID).get();
                if (customerSnap.exists) customerEmail = customerSnap.data()?.email || "";
                if (!customerEmail) {
                    const legacyCustomerSnap = await db.collection("users")
                        .where("userId", "==", customerID).limit(1).get();
                    if (!legacyCustomerSnap.empty) customerEmail = legacyCustomerSnap.docs[0].data()?.email || "";
                }
            }

            if (!customerEmail) {
                await transactionRef.update({ failureEmailStatus: "no_customer_email" });
                console.warn(`[Recurring Cycle FAILED] No customer email available for rental ${rentalID}.`);
            } else if (!recurringFailureMailer) {
                await transactionRef.update({ failureEmailStatus: "not_configured" });
                console.warn("[Recurring Cycle FAILED] Email not sent: recurringFailureMailer not available.");
            } else {
                let customerName = rentalData.name || rentalData.customerName || "";
                if (!customerName && customerID) {
                    try {
                        const uSnap = await db.collection("users").doc(customerID).get();
                        if (uSnap.exists) {
                            customerName = uSnap.data()?.name || uSnap.data()?.fullName || "";
                        }
                    } catch (_) {}
                }
                if (!customerName) customerName = customerEmail.split('@')[0] || "Customer";

                // Get product display title if available
                let productTitle = rentalData.productTitle || "";
                if (!productTitle && rentalData.productID) {
                    try {
                        const prodDoc = await db.collection("product").doc(rentalData.productID).get();
                        if (prodDoc.exists) productTitle = prodDoc.data()?.displayTitle || prodDoc.data()?.model || "";
                    } catch (_) {}
                }

                const safeReason = String(failReason).replace(/[&<>"']/g, char => ({
                    "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;"
                })[char]);

                const formattedAmount = `RM ${monthlyFee.toFixed(2)}`;
                const fromAddress = process.env.REBYTE_SMTP_FROM || '"ReByte Notifications" <lolincoln021@gmail.com>';

                const emailHtml = `
                <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 24px; border: 1px solid #e2e8f0; border-radius: 12px; background-color: #ffffff;">
                    <div style="text-align: center; margin-bottom: 24px;">
                        <h2 style="color: #dc2626; margin: 0 0 8px 0; font-size: 22px;">⚠️ Auto Recurring Payment Failed</h2>
                        <p style="color: #64748b; margin: 0; font-size: 14px;">ReByte Rental Subscription Notification</p>
                    </div>

                    <p style="font-size: 15px; color: #1e293b; line-height: 1.6;">
                        Dear <strong>${customerName}</strong>,
                    </p>
                    <p style="font-size: 14px; color: #334155; line-height: 1.6;">
                        We were unable to process your scheduled auto recurring rental payment for your active device subscription.
                    </p>

                    <div style="background-color: #f8fafc; border: 1px solid #e2e8f0; border-radius: 8px; padding: 16px; margin: 20px 0;">
                        <table style="width: 100%; border-collapse: collapse; font-size: 14px; color: #334155;">
                            <tr>
                                <td style="padding: 6px 0; color: #64748b;"><strong>Rental ID:</strong></td>
                                <td style="padding: 6px 0; text-align: right; font-weight: 600; color: #0f172a;">${rentalID}</td>
                            </tr>
                            ${productTitle ? `
                            <tr>
                                <td style="padding: 6px 0; color: #64748b;"><strong>Product:</strong></td>
                                <td style="padding: 6px 0; text-align: right; color: #0f172a;">${productTitle}</td>
                            </tr>` : ''}
                            <tr>
                                <td style="padding: 6px 0; color: #64748b;"><strong>Amount Due:</strong></td>
                                <td style="padding: 6px 0; text-align: right; font-weight: 700; color: #dc2626;">${formattedAmount}</td>
                            </tr>
                            <tr>
                                <td style="padding: 6px 0; color: #64748b;"><strong>Failure Reason:</strong></td>
                                <td style="padding: 6px 0; text-align: right; color: #dc2626;">${safeReason}</td>
                            </tr>
                        </table>
                    </div>

                    <div style="background-color: #fef2f2; border-left: 4px solid #ef4444; padding: 12px 16px; margin-bottom: 24px; border-radius: 4px;">
                        <p style="margin: 0; font-size: 13px; color: #991b1b; line-height: 1.5;">
                            <strong>Action Required:</strong> Please open the ReByte mobile application and update your linked payment account or top up your balance to avoid service interruption or account restrictions.
                        </p>
                    </div>

                    <p style="font-size: 13px; color: #64748b; line-height: 1.5;">
                        If you believe this was an error or need assistance, please contact ReByte Customer Support via the app.
                    </p>

                    <hr style="border: 0; border-top: 1px solid #e2e8f0; margin: 24px 0;" />
                    <p style="font-size: 12px; color: #94a3b8; text-align: center; margin: 0;">
                        This is an automated notification from ReByte Platform. Please do not reply directly to this email.
                    </p>
                </div>
                `;

                await recurringFailureMailer.sendMail({
                    from: fromAddress,
                    to: customerEmail,
                    subject: `[Action Required] Recurring Rental Payment Failed - ${rentalID}`,
                    text: `Dear ${customerName},\n\nWe were unable to process the recurring payment of ${formattedAmount} for rental ${rentalID}.\n\nReason: ${failReason}\n\nPlease open the ReByte app to update your payment method or contact support.\n\nThank you,\nReByte Team`,
                    html: emailHtml
                });
                await transactionRef.update({ failureEmailStatus: "sent", failureEmailSentAt: new Date().toISOString() });
                console.log(`[Recurring Cycle FAILED] Email sent successfully to ${customerEmail} for rental ${rentalID}.`);
            }
        } catch (emailError) {
            await transactionRef.update({ failureEmailStatus: "failed" }).catch(() => {});
            console.error(`[Recurring Cycle FAILED] Could not email customer for rental ${rentalID}:`, emailError.message);
        }
    }

    console.log(`[Recurring Cycle FAILED] Rental ${rentalID}. Failed transaction: ${transactionData.transactionID}`);
    return transactionData;
}

/**
 * POST /rental/webhook/subscription or /api/rental/webhook/subscription
 * Handles Xendit recurring subscription webhooks:
 * - recurring.plan.activated
 * - recurring.plan.inactivated
 * - recurring.cycle.created
 * - recurring.cycle.succeeded
 * - recurring.cycle.failed
 * - recurring.cycle.retrying
 */
router.post("/webhook/subscription", async (req, res) => {
    try {
        const event = req.body || {};
        const eventType = String(event.event || event.type || "");
        console.log(`[Xendit Subscription Webhook] Event: ${eventType}:`, JSON.stringify(event));

        const data = event.data || {};
        const planId = data.plan_id || data.id;
        const referenceId = data.reference_id || "";

        // Find associated rental document
        let rentalDoc = null;
        if (planId) {
            const snap = await db.collection("rental").where("recurringPlanID", "==", planId).limit(1).get();
            if (!snap.empty) rentalDoc = snap.docs[0];
        }
        if (!rentalDoc && referenceId.startsWith("plan_")) {
            const rentalId = referenceId.replace(/^plan_/, "").replace(/_[A-Z0-9]{4}$/, "");
            const snap = await db.collection("rental").where("rentalID", "==", rentalId).limit(1).get();
            if (!snap.empty) rentalDoc = snap.docs[0];
        }

        if (eventType === "payment.succeeded") {
            // Payment success event from sessions PAY_AND_SAVE
            console.log(`[Webhook] Payment succeeded for session: ${data.payment_session_id || data.id}`);
        } else if (eventType === "payment_token.activated") {
            // Payment method tokenized and activated
            const paymentTokenId = data.id || data.payment_token_id;
            const customerId = data.customer_id;
            console.log(`[Webhook] Payment token activated: ${paymentTokenId} for customer: ${customerId}`);
            // If rental document exists without plan yet, link it
            if (rentalDoc) {
                await rentalDoc.ref.update({
                    paymentTokenID: paymentTokenId,
                    xenditCustomerID: customerId || "",
                    updatedAt: new Date().toISOString()
                });
            }
        } else if (eventType === "recurring.plan.activated" || data.status === "ACTIVE") {
            if (rentalDoc) {
                const updatePayload = {
                    recurringStatus: "active",
                    updatedAt: new Date().toISOString()
                };
                if (Array.isArray(data.payment_methods) && data.payment_methods.length > 0) {
                    const pmId = data.payment_methods[0].payment_method_id;
                    if (pmId) updatePayload.paymentMethodID = pmId;
                }
                if (Array.isArray(data.payment_tokens) && data.payment_tokens.length > 0) {
                    const ptId = data.payment_tokens[0].payment_token_id;
                    if (ptId) updatePayload.paymentTokenID = ptId;
                }
                await rentalDoc.ref.update(updatePayload);
                console.log(`[Webhook] Activated recurring plan for rental: ${rentalDoc.id}`, updatePayload);
            }
        } else if (eventType === "recurring.cycle.succeeded" || (data.status === "SUCCEEDED" && eventType.includes("cycle"))) {
            if (rentalDoc) {
                const actionId = (data.attempt_details && data.attempt_details[0]) ? data.attempt_details[0].action_id : "";
                await processSuccessfulRentalCycle(rentalDoc, data, actionId || data.id);
            }
        } else if (eventType === "recurring.cycle.failed" || (data.status === "FAILED" && eventType.includes("cycle"))) {
            if (rentalDoc) {
                const failureReason = data.failure_code || data.failure_reason || data.failure_message ||
                    data.reason || data.failure?.message || "Payment cycle failed";
                await processFailedRentalCycle(rentalDoc, data, failureReason);
            }
        }

        return res.status(200).json({ received: true });
    } catch (err) {
        console.error("[Webhook Subscription Error]:", err);
        return res.status(200).json({ received: true });
    }
});

/**
 * POST /rental/complete-recurring-auth or /api/rental/complete-recurring-auth
 * Verifies the e-wallet-only SAVE session and creates the recurring plan from
 * the resulting Malaysian e-wallet payment token.
 */
router.post("/complete-recurring-auth", async (req, res) => {
    try {
        const { rentalID, sessionID } = req.body;
        if (!rentalID || !sessionID) {
            return res.status(400).json({ success: false, error: "rentalID and sessionID are required." });
        }

        const rentalRef = db.collection("rental").doc(String(rentalID));
        const rentalSnap = await rentalRef.get();
        if (!rentalSnap.exists) {
            return res.status(404).json({ success: false, error: "Rental not found." });
        }

        const rental = rentalSnap.data() || {};
        if (String(rental.recurringAuthSessionID || "") !== String(sessionID)) {
            return res.status(403).json({ success: false, error: "Authorization session does not match this rental." });
        }

        // Repeated requests after plan creation are safe and return the current status.
        if (rental.recurringPlanID) {
            const existingPlan = await axios.get(
                `https://api.xendit.co/recurring/plans/${rental.recurringPlanID}`,
                { headers: { ...getXenditAuthHeader(), "api-version": rental.recurringApiVersion || "2026-01-01" } }
            );
            const existingStatus = String(existingPlan.data?.status || rental.recurringStatus || "").toLowerCase();
            await rentalRef.update({ recurringStatus: existingStatus, updatedAt: new Date().toISOString() });
            return res.json({
                success: ["active", "linked", "completed"].includes(existingStatus),
                status: existingStatus,
                recurringPlanID: rental.recurringPlanID
            });
        }

        const sessionRes = await axios.get(`https://api.xendit.co/sessions/${encodeURIComponent(sessionID)}`, {
            headers: { ...getXenditAuthHeader(), "api-version": "2026-01-01" }
        });
        const session = sessionRes.data || {};
        const paymentTokenID = session.payment_token_id || session.latest_payment_token_id;
        if (!paymentTokenID) {
            return res.status(409).json({
                success: false,
                status: String(session.status || "PENDING").toLowerCase(),
                message: "Touch 'n Go authorization has not completed."
            });
        }

        const tokenRes = await axios.get(`https://api.xendit.co/v3/payment_tokens/${encodeURIComponent(paymentTokenID)}`, {
            headers: { ...getXenditAuthHeader(), "api-version": "2024-11-11" }
        });
        const paymentToken = tokenRes.data || {};
        const recurringWalletChannels = new Set(["TOUCHNGO", "SHOPEEPAY", "GRABPAY"]);
        if (!recurringWalletChannels.has(String(paymentToken.channel_code || "").toUpperCase())) {
            return res.status(403).json({ success: false, error: "Only supported Malaysian e-wallets can authorize a rental plan." });
        }
        if (String(paymentToken.status || "").toUpperCase() !== "ACTIVE") {
            return res.status(409).json({
                success: false,
                status: String(paymentToken.status || "PENDING").toLowerCase(),
                message: "The e-wallet has not activated the payment token yet."
            });
        }

        const customerID = session.customer_id || rental.xenditCustomerID;
        if (!customerID) {
            return res.status(409).json({ success: false, error: "Xendit customer is missing from the authorization session." });
        }

        const startedAt = rental.startDate ? new Date(`${rental.startDate}T00:00:00`) : new Date();
        const nextCycleDate = new Date(startedAt.getFullYear(), startedAt.getMonth() + 1, startedAt.getDate());
        const months = Math.max(1, parseInt(rental.durationMonths, 10) || 1);
        const xenditReferenceSuffix = await db.runTransaction(async transaction => {
            const latestRental = await transaction.get(rentalRef);
            const existingSuffix = latestRental.data()?.xenditReferenceSuffix;
            if (existingSuffix) return existingSuffix;
            const newSuffix = generateReferenceSuffix();
            transaction.update(rentalRef, { xenditReferenceSuffix: newSuffix });
            return newSuffix;
        });
        const planPayload = {
            reference_id: `plan_${rentalID}_${xenditReferenceSuffix}`,
            customer_id: customerID,
            currency: "MYR",
            amount: Number(rental.monthlyRentalFee || 0),
            payment_tokens: [{ payment_token_id: paymentTokenID, rank: 1 }],
            schedule: {
                interval: "MONTH",
                interval_count: 1,
                anchor_date: nextCycleDate.toISOString(),
                total_recurrence: months > 1 ? months - 1 : 1,
                retry_interval: "DAY",
                retry_interval_count: 5,
                total_retry: 7,
                failed_attempt_notifications: [1, 3, 5]
            },
            immediate_payment: false,
            failed_cycle_action: "RESUME",
            notification_channels: ["EMAIL"],
            locale: "en",
            payment_link_for_failed_attempt: true,
            description: `Monthly Rental for ${rental.productID || rentalID} (${months} Months)`
        };

        const planRes = await axios.post("https://api.xendit.co/recurring/plans", planPayload, {
            headers: { ...getXenditAuthHeader(), "api-version": "2026-01-01" }
        });
        const planID = planRes.data?.id;
        if (!planID) {
            return res.status(502).json({ success: false, error: "Xendit did not create the recurring rental plan." });
        }

        const recurringStatus = String(planRes.data?.status || "ACTIVE").toLowerCase();
        await rentalRef.update({
            paymentTokenID,
            xenditCustomerID: customerID,
            recurringPlanID: planID,
            recurringStatus,
            updatedAt: new Date().toISOString()
        });

        return res.json({
            success: ["active", "linked", "completed"].includes(recurringStatus),
            status: recurringStatus,
            recurringPlanID: planID
        });
    } catch (err) {
        console.error("Error completing rental e-wallet authorization:", err.response?.data || err.message);
        return res.status(500).json({ success: false, error: "Unable to verify e-wallet authorization." });
    }
});

/**
 * POST /rental/sync-plan-status or /api/rental/sync-plan-status
 * Directly queries Xendit for the plan's live status and updates Firestore
 */
router.post("/sync-plan-status", async (req, res) => {
    try {
        const { rentalID } = req.body;
        if (!rentalID) return res.status(400).json({ error: "rentalID required" });

        const docRef = db.collection("rental").doc(rentalID);
        const docSnap = await docRef.get();
        if (!docSnap.exists) return res.status(404).json({ error: "Rental not found" });

        const data = docSnap.data();
        const planId = data.recurringPlanID;
        if (!planId) return res.json({ success: false, status: data.recurringStatus || "requires_action" });

        const planRes = await axios.get(`https://api.xendit.co/recurring/plans/${planId}`, {
            headers: {
                ...getXenditAuthHeader(),
                "api-version": data.recurringApiVersion || "2022-04-10"
            }
        });

        const liveStatus = String(planRes.data?.status || "").toLowerCase();
        await docRef.update({
            recurringStatus: liveStatus,
            updatedAt: new Date().toISOString()
        });

        const isFullyActive = (liveStatus === "active" || liveStatus === "linked" || liveStatus === "completed");
        if (isFullyActive && data.productID) {
            let pRef = db.collection("product").doc(data.productID);
            let pDoc = await pRef.get();
            if (!pDoc.exists) {
                const q = await db.collection("product").where("productID", "==", data.productID).limit(1).get();
                if (!q.empty) pRef = q.docs[0].ref;
            }
            if (pDoc.exists || pRef) {
                await pRef.update({
                    status: "renting",
                    listingStatus: "renting",
                });
            }
        }
        return res.json({
            success: isFullyActive,
            status: liveStatus,
            isActive: isFullyActive
        });
    } catch (e) {
        console.error("Error syncing plan status:", e.response?.data || e.message);
        return res.status(500).json({ error: e.message });
    }
});

/**
 * POST /rental/test-recurring-charge or /api/rental/test-recurring-charge
 * Sends signal to Xendit to execute/simulate cycle, handles pass and fail scenarios,
 * creates transaction record in 'transaction' with rentalID, and extends rentalExpiryDate by 1 month on success.
 * Body: { rentalID, forceFailure: boolean, failureReason: string }
 */
router.post("/test-recurring-charge", async (req, res) => {
    try {
        const { rentalID, forceFailure, failureReason, monthsToPay } = req.body;
        if (!rentalID) return res.status(400).json({ error: "rentalID is required" });

        // 1. Locate rental document
        let rentalRef = db.collection("rental").doc(rentalID);
        let docSnap = await rentalRef.get();
        if (!docSnap.exists) {
            const querySnap = await db.collection("rental").where("rentalID", "==", rentalID).limit(1).get();
            if (querySnap.empty) {
                return res.status(404).json({ error: "Rental record not found" });
            }
            docSnap = querySnap.docs[0];
            rentalRef = docSnap.ref;
        }

        const rentalData = docSnap.data();
        const planId = rentalData.recurringPlanID;
        const countMonths = Math.max(1, parseInt(monthsToPay, 10) || 1);
        const monthlyFee = Number(rentalData.monthlyRentalFee || 75);
        const totalCharge = Math.round(monthlyFee * countMonths * 100) / 100;

        // 2. If forceFailure is requested:
        if (forceFailure) {
            const reason = failureReason || "Card issuer declined recurring cycle (Simulated Test).";
            const txn = await processFailedRentalCycle(docSnap, { amount: totalCharge }, reason);

            return res.json({
                success: false,
                status: "failed",
                message: "Recurring charge failed. A failed transaction was recorded and the customer was notified. Rental status was not changed.",
                rentalStatus: rentalData.rentalStatus || "renting",
                transactionID: txn.transactionID,
                transaction: txn
            });
        }

        // 3. Success Scenario: Send signal to Xendit cycle simulation if planId exists
        let xenditCycleResult = null;
        if (planId) {
            try {
                // Fetch scheduled cycles for this plan
                const cyclesRes = await axios.get(`https://api.xendit.co/recurring/plans/${planId}/cycles`, {
                    headers: {
                        ...getXenditAuthHeader(),
                        "api-version": rentalData.recurringApiVersion || "2022-04-10"
                    }
                });

                const cycles = Array.isArray(cyclesRes.data?.data) ? cyclesRes.data.data : [];
                // Find next SCHEDULED cycle
                const targetCycle = cycles.find(c => c.status === "SCHEDULED") || cycles[0];

                if (targetCycle && targetCycle.id) {
                    console.log(`[Xendit Cycle Signal] Sending simulate request for cycle ${targetCycle.id}...`);
                    const simRes = await axios.post(`https://api.xendit.co/recurring/plans/${planId}/cycles/${targetCycle.id}/simulate`, {
                        amount: totalCharge
                    }, {
                        headers: {
                            ...getXenditAuthHeader(),
                            "api-version": rentalData.recurringApiVersion || "2022-04-10",
                            "Content-Type": "application/json"
                        }
                    });
                    xenditCycleResult = simRes.data;
                    console.log(`[Xendit Cycle Signal] Simulate succeeded:`, xenditCycleResult?.status);
                }
            } catch (xErr) {
                console.warn("[Xendit Cycle Signal Warning]:", xErr.response?.data || xErr.message);
                // Proceed to fulfill transaction locally if cycle was already executed or offline
            }
        }

        // Process successful rental cycle in database
        const actionId = xenditCycleResult?.attempt_details?.[0]?.action_id || xenditCycleResult?.id || "";
        const txn = await processSuccessfulRentalCycle(docSnap, xenditCycleResult || { amount: totalCharge }, actionId, countMonths);

        // Fetch refreshed expiry date
        const updatedSnap = await rentalRef.get();
        const updatedData = updatedSnap.data();

        return res.json({
            success: true,
            status: "success",
            message: `Xendit recurring cycle executed successfully! Transaction ${txn.transactionID} created. Rental extended until ${updatedData.rentalExpiryDate}.`,
            rentalStatus: "renting",
            newRentalExpiryDate: updatedData.rentalExpiryDate,
            transactionID: txn.transactionID,
            monthsPaid: countMonths,
            xenditCycleResult,
            transaction: txn
        });
    } catch (e) {
        console.error("Error executing recurring test:", e);
        return res.status(500).json({ error: e.message });
    }
});

/**
 * POST /rental/complete-rental-payment or /api/rental/complete-rental-payment
 * Called when a rental recurring payment invoice succeeds via Xendit.
 * Records the transaction with rentalID, extends rentalExpiryDate,
 * and updates/deducts corresponding cycles from the Xendit recurring plan.
 * Body: { rentalID, invoiceID, monthsToPay, amountPaid, paymentAccountID }
 */
router.post("/complete-rental-payment", async (req, res) => {
    try {
        const { rentalID, invoiceID, monthsToPay, amountPaid, paymentAccountID } = req.body;
        if (!rentalID) return res.status(400).json({ success: false, error: "rentalID is required" });

        // Locate rental document
        let rentalRef = db.collection("rental").doc(rentalID);
        let docSnap = await rentalRef.get();
        if (!docSnap.exists) {
            const querySnap = await db.collection("rental").where("rentalID", "==", rentalID).limit(1).get();
            if (querySnap.empty) {
                return res.status(404).json({ success: false, error: "Rental record not found" });
            }
            docSnap = querySnap.docs[0];
            rentalRef = docSnap.ref;
        }

        const rentalData = docSnap.data();
        const countMonths = Math.max(1, parseInt(monthsToPay, 10) || 1);
        const monthlyFee = Number(rentalData.monthlyRentalFee || 75);
        const totalCharge = Number(amountPaid) || Math.round(monthlyFee * countMonths * 100) / 100;

        // Process successful cycle (creates transaction with rentalID, updates expiryDate, and deducts Xendit plan cycles)
        const gatewayTxId = invoiceID || `xendit_inv_${Date.now()}`;
        const txn = await processSuccessfulRentalCycle(
            docSnap,
            { amount: totalCharge, paymentAccountID: paymentAccountID || rentalData.paymentAccountID || "" },
            gatewayTxId,
            countMonths,
            true // deductCycles: true because customer manually paid advance rental
        );

        const updatedSnap = await rentalRef.get();
        const updatedData = updatedSnap.data();

        return res.json({
            success: true,
            status: "success",
            message: `Rental payment recorded successfully. Transaction ${txn.transactionID} created. Expiry date updated to ${updatedData.rentalExpiryDate}.`,
            transactionID: txn.transactionID,
            rentalExpiryDate: updatedData.rentalExpiryDate,
            monthsPaid: countMonths,
            transaction: txn
        });
    } catch (e) {
        console.error("Error completing rental payment:", e);
        return res.status(500).json({ success: false, error: e.message });
    }
});

/**
 * GET /rental/customer/:customerIdentifier or /api/rental/customer/:customerIdentifier
 * Returns all rental records for a customer, including enriched product & device info
 */
router.get("/customer/:customerIdentifier", async (req, res) => {
    try {
        const { customerIdentifier } = req.params;
        if (!customerIdentifier) {
            return res.status(400).json({ error: "Customer identifier is required." });
        }

        const resolvedCustId = await resolveCustomerID(customerIdentifier);
        const searchTerms = [customerIdentifier];
        if (resolvedCustId && resolvedCustId !== customerIdentifier) {
            searchTerms.push(resolvedCustId);
        }

        // Query rental records
        let rentals = [];
        const snap = await db.collection("rental").where("customerID", "in", searchTerms).get();
        snap.forEach(d => rentals.push(d.data()));

        // Also query by email if customerIdentifier looks like email
        if (rentals.length === 0 && customerIdentifier.includes("@")) {
            const snap2 = await db.collection("rental").where("email", "==", customerIdentifier).get();
            snap2.forEach(d => rentals.push(d.data()));
        }

        // Enrich each rental record with product & device details
        const enriched = await Promise.all(rentals.map(async (r) => {
            let product = null;
            let device = null;
            if (r.productID) {
                try {
                    let pDoc = await db.collection("product").doc(r.productID).get();
                    if (!pDoc.exists) {
                        const pSnap = await db.collection("product").where("productID", "==", r.productID).limit(1).get();
                        if (!pSnap.empty) pDoc = pSnap.docs[0];
                    }
                    if (pDoc && pDoc.exists) {
                        product = pDoc.data();
                        const devId = product.deviceID;
                        if (devId) {
                            let dDoc = await db.collection("devices").doc(devId).get();
                            if (!dDoc.exists) {
                                const dSnap = await db.collection("devices").where("deviceID", "==", devId).limit(1).get();
                                if (!dSnap.empty) dDoc = dSnap.docs[0];
                            }
                            if (dDoc && dDoc.exists) {
                                device = dDoc.data();
                            }
                        }
                    }
                } catch (err) {
                    console.error("Error enriching rental product/device:", err);
                }
            }

            return {
                ...r,
                product: product || {},
                device: device || {},
            };
        }));

        // Sort rentals by startDate desc or rentalID desc
        enriched.sort((a, b) => String(b.rentalID || "").localeCompare(String(a.rentalID || "")));

        return res.json({
            success: true,
            rentals: enriched
        });
    } catch (error) {
        console.error("Error fetching customer rentals:", error);
        return res.status(500).json({ error: error.message || "Failed to retrieve rentals." });
    }
});

/**
 * POST /rental/cancel-rental or /api/rental/cancel-rental
 * Cancels an incomplete rental (e.g. user cancelled during recurring authorization),
 * deletes the rental document and restores the product status back to 'listed'.
 */
router.post("/cancel-rental", async (req, res) => {
    try {
        const { rentalID } = req.body;
        if (!rentalID) return res.status(400).json({ error: "rentalID required" });

        const rentalRef = db.collection("rental").doc(rentalID);
        const rentalSnap = await rentalRef.get();
        if (!rentalSnap.exists) {
            return res.json({ success: true, message: "Rental already removed or not found" });
        }

        const rentalData = rentalSnap.data();
        const pId = rentalData.productID;

        // Maintain product status as 'rent' on cancellation as requested
        if (pId) {
            let pRef = db.collection("product").doc(pId);
            let pDoc = await pRef.get();
            if (!pDoc.exists) {
                const q = await db.collection("product").where("productID", "==", pId).limit(1).get();
                if (!q.empty) pRef = q.docs[0].ref;
            }
            if (pDoc.exists || pRef) {
                await pRef.update({
                    status: "rent",
                    listingStatus: "rent"
                });
            }
        }

        // Deactivate recurring plan in Xendit if created
        const planId = rentalData.recurringPlanID;
        if (planId && !String(planId).startsWith("rec_plan_")) {
            try {
                await axios.post(`https://api.xendit.co/recurring/plans/${planId}/deactivate`, {}, {
                    headers: {
                        ...getXenditAuthHeader(),
                        "api-version": rentalData.recurringApiVersion || "2022-04-10"
                    }
                });
                console.log(`[Rental] Deactivated Xendit recurring plan: ${planId}`);
            } catch (deactErr) {
                console.warn("[Rental] Warning deactivating Xendit plan:", deactErr.response?.data || deactErr.message);
            }
        }

        // Delete un-authorized rental document
        await rentalRef.delete();

        return res.json({ success: true, message: "Rental cancelled and product released." });
    } catch (err) {
        console.error("Error cancelling rental:", err);
        return res.status(500).json({ error: err.message });
    }
});

/**
 * POST /rental/renew-rental or /api/rental/renew-rental
 * Extends the rental agreement's endDate and increases the Xendit subscription cycle recurrence.
 * Body: { rentalID, newEndDate, additionalMonths }
 */
router.post("/renew-rental", async (req, res) => {
    try {
        const { rentalID, newEndDate, additionalMonths } = req.body;
        if (!rentalID || !newEndDate) {
            return res.status(400).json({ success: false, error: "rentalID and newEndDate are required." });
        }

        const addMonths = parseInt(additionalMonths, 10) || 0;
        if (addMonths <= 0) {
            return res.status(400).json({ success: false, error: "New end date must extend the rental by at least 1 month." });
        }

        let rentalRef = db.collection("rental").doc(rentalID);
        let docSnap = await rentalRef.get();
        if (!docSnap.exists) {
            const querySnap = await db.collection("rental").where("rentalID", "==", rentalID).limit(1).get();
            if (querySnap.empty) {
                return res.status(404).json({ success: false, error: "Rental record not found." });
            }
            docSnap = querySnap.docs[0];
            rentalRef = docSnap.ref;
        }

        const rentalData = docSnap.data();

        // Validate newEndDate > current endDate
        const currentEnd = rentalData.endDate ? new Date(rentalData.endDate) : new Date();
        const targetEnd = new Date(newEndDate);
        if (targetEnd <= currentEnd) {
            return res.status(400).json({ success: false, error: "New end date must be strictly after the current end date." });
        }

        // Validate lastExpired (rentalExpiryDate) to newEndDate cannot exceed 5 years (60 months)
        const expiryDate = rentalData.rentalExpiryDate ? new Date(rentalData.rentalExpiryDate) : new Date();
        const diffYears = (targetEnd.getFullYear() - expiryDate.getFullYear()) + (targetEnd.getMonth() - expiryDate.getMonth()) / 12;
        if (diffYears > 5.0) {
            return res.status(400).json({ success: false, error: "Rental duration from rental expiry date cannot exceed 5 years." });
        }

        const planId = rentalData.recurringPlanID;
        let updatedXenditRecurrence = null;
        let newPlanID = null;
        let effectiveApiVersion = "2026-01-01";
        let resolvedPaymentTokenID = rentalData.paymentTokenID || "";
        let resolvedPaymentMethodID = rentalData.paymentMethodID || "";

        // If recurring plan exists, check its status
        if (planId && !String(planId).startsWith("rec_plan_")) {
            const candidateVersions = [
                rentalData.recurringApiVersion,
                "2026-01-01",
                "2022-04-10"
            ].filter((v, idx, arr) => Boolean(v) && arr.indexOf(v) === idx);

            let planData = null;

            for (const v of candidateVersions) {
                try {
                    const pRes = await axios.get(`https://api.xendit.co/recurring/plans/${planId}`, {
                        headers: {
                            ...getXenditAuthHeader(),
                            "api-version": v
                        }
                    });
                    if (pRes.data && pRes.data.id) {
                        planData = pRes.data;
                        effectiveApiVersion = v;
                        break;
                    }
                } catch (_) {}
            }

            const planStatus = String(planData?.status || "").toUpperCase();
            const isPlanInactive = planStatus === "INACTIVE" || planStatus === "DEACTIVATED" || planStatus === "COMPLETED";

            if (isPlanInactive) {
                // The previous plan is inactive because the customer had fully paid the rental.
                // Open a new Xendit subscription plan to link it again.
                // Anchor date = rentalExpiryDate (no +1 month).
                // Cycle number (total_recurrence) = customer selected increase month (addMonths).
                console.log(`[Xendit Renew] Previous plan ${planId} is ${planStatus}. Creating new subscription plan for ${addMonths} month(s)...`);

                const baseExpiry = rentalData.rentalExpiryDate ? new Date(rentalData.rentalExpiryDate) : new Date();
                const anchorDate = baseExpiry;

                // Generate fresh unique reference ID
                const xenditSuffix = generateReferenceSuffix();
                resolvedPaymentTokenID = rentalData.paymentTokenID || planData?.payment_tokens?.[0]?.payment_token_id || "";
                resolvedPaymentMethodID = rentalData.paymentMethodID || planData?.payment_methods?.[0]?.payment_method_id || "";
                const customerID = rentalData.xenditCustomerID || planData?.customer_id;

                if ((resolvedPaymentTokenID || resolvedPaymentMethodID) && customerID) {
                    try {
                        const targetApiVersion = resolvedPaymentTokenID ? "2026-01-01" : "2022-04-10";
                        let newPlanPayload = {};

                        if (resolvedPaymentTokenID) {
                            // Schema for api-version 2026-01-01 (tokens)
                            newPlanPayload = {
                                reference_id: `plan_${rentalID}_renew_${xenditSuffix}`,
                                customer_id: customerID,
                                currency: "MYR",
                                amount: Number(rentalData.monthlyRentalFee || 0),
                                payment_tokens: [{ payment_token_id: resolvedPaymentTokenID, rank: 1 }],
                                schedule: {
                                    interval: "MONTH",
                                    interval_count: 1,
                                    anchor_date: anchorDate.toISOString(),
                                    total_recurrence: addMonths,
                                    retry_interval: "DAY",
                                    retry_interval_count: 5,
                                    total_retry: 7,
                                    failed_attempt_notifications: [1, 3, 5]
                                },
                                immediate_payment: false,
                                failed_cycle_action: "RESUME",
                                notification_channels: ["EMAIL"],
                                locale: "en",
                                payment_link_for_failed_attempt: true,
                                description: `Monthly Rental Renewal for ${rentalData.productID || rentalID} (+${addMonths} Months)`
                            };
                        } else {
                            // Schema for api-version 2022-04-10 (payment_methods)
                            newPlanPayload = {
                                reference_id: `plan_${rentalID}_renew_${xenditSuffix}`,
                                customer_id: customerID,
                                recurring_action: "PAYMENT",
                                currency: "MYR",
                                amount: Number(rentalData.monthlyRentalFee || 0),
                                payment_methods: [{ payment_method_id: resolvedPaymentMethodID, rank: 1 }],
                                schedule: {
                                    reference_id: `sched_${rentalID}_renew_${xenditSuffix}`,
                                    interval: "MONTH",
                                    interval_count: 1,
                                    anchor_date: anchorDate.toISOString(),
                                    total_recurrence: addMonths,
                                    retry_interval: "DAY",
                                    retry_interval_count: 1,
                                    total_retry: 3,
                                    failed_attempt_notifications: []
                                },
                                failed_cycle_action: "RESUME",
                                description: `Monthly Rental Renewal for ${rentalData.productID || rentalID} (+${addMonths} Months)`
                            };
                        }

                        const createPlanRes = await axios.post("https://api.xendit.co/recurring/plans", newPlanPayload, {
                            headers: { ...getXenditAuthHeader(), "api-version": targetApiVersion }
                        });

                        newPlanID = createPlanRes.data?.id;
                        effectiveApiVersion = targetApiVersion;
                        updatedXenditRecurrence = addMonths;
                        console.log(`[Xendit Renew] Successfully created new active subscription plan ${newPlanID} with anchor date ${anchorDate.toISOString()} and ${addMonths} cycle(s).`);
                    } catch (createErr) {
                        console.warn(`[Xendit Renew Error] Could not create new recurring plan for inactive subscription:`, createErr.response?.data || createErr.message);
                    }
                } else {
                    console.warn(`[Xendit Renew Warning] Missing paymentTokenID/paymentMethodID (${resolvedPaymentTokenID || resolvedPaymentMethodID}) or customerID (${customerID}) to recreate plan.`);
                }
            } else if (planData && planData.schedule) {
                // Plan is still active: increase total_recurrence by addMonths
                const currentRecurrence = Number(planData.schedule.total_recurrence ?? 0);
                const newRecurrence = currentRecurrence + addMonths;

                try {
                    const patchRes = await axios.patch(
                        `https://api.xendit.co/recurring/plans/${planId}`,
                        {
                            schedule: {
                                total_recurrence: newRecurrence
                            }
                        },
                        {
                            headers: {
                                ...getXenditAuthHeader(),
                                "api-version": effectiveApiVersion,
                                "Content-Type": "application/json"
                            }
                        }
                    );
                    updatedXenditRecurrence = patchRes.data?.schedule?.total_recurrence ?? newRecurrence;
                    console.log(`[Xendit Renew] Successfully increased plan ${planId} total_recurrence from ${currentRecurrence} to ${updatedXenditRecurrence}`);
                } catch (patchErr) {
                    console.warn(`[Xendit Renew Warning] Could not update plan total_recurrence:`, patchErr.response?.data || patchErr.message);
                }
            }
        }

        // Update Firestore rental document
        const currentDuration = parseInt(rentalData.durationMonths, 10) || 0;
        const currentRemaining = (rentalData.remainingCycles !== undefined && rentalData.remainingCycles !== null)
            ? parseInt(rentalData.remainingCycles, 10)
            : Math.max(0, currentDuration - 1);

        const updatePayload = {
            endDate: newEndDate,
            durationMonths: currentDuration + addMonths,
            remainingCycles: currentRemaining + addMonths,
            recurringStatus: "active",
            lastRenewedAt: new Date().toISOString(),
            updatedAt: new Date().toISOString()
        };

        if (newPlanID) {
            updatePayload.recurringPlanID = newPlanID;
            updatePayload.recurringApiVersion = effectiveApiVersion || "2026-01-01";
            if (resolvedPaymentTokenID) updatePayload.paymentTokenID = resolvedPaymentTokenID;
            if (resolvedPaymentMethodID) updatePayload.paymentMethodID = resolvedPaymentMethodID;
        }

        await rentalRef.update(updatePayload);

        console.log(`[Rental Renew SUCCESS] Rental ${rentalID} extended to ${newEndDate} (+${addMonths} month(s)).`);
        return res.json({
            success: true,
            message: `Rental agreement successfully renewed until ${newEndDate}.`,
            rentalID,
            newEndDate,
            addedMonths: addMonths,
            newDurationMonths: currentDuration + addMonths,
            newRemainingCycles: currentRemaining + addMonths,
            updatedXenditRecurrence
        });
    } catch (err) {
        console.error("Error renewing rental:", err);
        return res.status(500).json({ success: false, error: err.message || "Failed to renew rental." });
    }
});

module.exports = router;


