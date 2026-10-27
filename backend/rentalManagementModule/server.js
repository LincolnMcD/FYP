const express = require("express");
const { FieldValue } = require("firebase-admin/firestore");
const db = require("../config/firebase");

const router = express.Router();

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

module.exports = router;


