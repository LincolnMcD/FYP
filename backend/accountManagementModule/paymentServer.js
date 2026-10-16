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

module.exports = router;
