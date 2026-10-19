const express = require("express");
const db = require("../config/firebase");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");

const router = express.Router();

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
 * Helper: Generate next addressID
 * Format: YYMMDDADDXXXXX (where XXXXX is a 5-digit sequence starting from 00001)
 * Takes latest record of the day to determine next ID
 */
async function generateAddressId() {
    const now = new Date();
    const yy = String(now.getFullYear()).slice(-2);
    const mm = String(now.getMonth() + 1).padStart(2, "0");
    const dd = String(now.getDate()).padStart(2, "0");
    const prefix = `${yy}${mm}${dd}ADD`;

    // Query the latest record created with this prefix
    const snap = await db.collection("address")
        .where("addressID", ">=", prefix)
        .where("addressID", "<=", prefix + "\uf8ff")
        .orderBy("addressID", "desc")
        .limit(1)
        .get();

    let seq = 1;
    if (!snap.empty) {
        const latestId = snap.docs[0].data().addressID || "";
        const seqPart = latestId.replace(prefix, "");
        const parsed = parseInt(seqPart, 10);
        if (!isNaN(parsed)) {
            seq = parsed + 1;
        }
    }

    const paddedSeq = String(seq).padStart(5, "0");
    return `${prefix}${paddedSeq}`;
}

const MALAYSIAN_STATES = [
    'Johor',
    'Kedah',
    'Kelantan',
    'Melaka',
    'Negeri Sembilan',
    'Pahang',
    'Penang',
    'Perak',
    'Perlis',
    'Sabah',
    'Sarawak',
    'Selangor',
    'Terengganu',
    'Wilayah Persekutuan Kuala Lumpur',
    'Wilayah Persekutuan Labuan',
    'Wilayah Persekutuan Putrajaya',
];

/**
 * Match a raw state string from geocoding to the official Malaysian State list
 */
function matchMalaysianState(rawState, rawCity, fullDisplayName) {
    const text = `${rawState || ''} ${rawCity || ''} ${fullDisplayName || ''}`.toLowerCase();
    
    if (text.includes('kuala lumpur') || text.includes('kl')) return 'Wilayah Persekutuan Kuala Lumpur';
    if (text.includes('putrajaya')) return 'Wilayah Persekutuan Putrajaya';
    if (text.includes('labuan')) return 'Wilayah Persekutuan Labuan';
    if (text.includes('selangor')) return 'Selangor';
    if (text.includes('penang') || text.includes('pulau pinang')) return 'Penang';
    if (text.includes('johor')) return 'Johor';
    if (text.includes('perak')) return 'Perak';
    if (text.includes('pahang')) return 'Pahang';
    if (text.includes('sarawak')) return 'Sarawak';
    if (text.includes('sabah')) return 'Sabah';
    if (text.includes('kedah')) return 'Kedah';
    if (text.includes('kelantan')) return 'Kelantan';
    if (text.includes('terengganu')) return 'Terengganu';
    if (text.includes('melaka') || text.includes('malacca')) return 'Melaka';
    if (text.includes('negeri sembilan') || text.includes('sembilan')) return 'Negeri Sembilan';
    if (text.includes('perlis')) return 'Perlis';

    return null;
}

/**
 * GET /api/address/reverse-geocode?lat=...&lng=...
 * Reverse geocodes latitude/longitude and validates Malaysian location
 */
router.get("/reverse-geocode", async (req, res) => {
    try {
        const { lat, lng } = req.query;
        if (!lat || !lng) {
            return res.status(400).json({ success: false, error: "Latitude and longitude are required" });
        }

        const url = `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${lat}&lon=${lng}&addressdetails=1&accept-language=en`;
        const response = await fetch(url, {
            headers: {
                "User-Agent": "ReByteApp/1.0 (lincoln@rebyte.com)"
            }
        });

        if (!response.ok) {
            return res.status(502).json({ success: false, error: "Geocoding service unavailable" });
        }

        const data = await response.json();
        const addressObj = data.address || {};
        const countryCode = String(addressObj.country_code || "").toLowerCase();
        const countryName = String(addressObj.country || "").toLowerCase();

        // Validate Malaysia region
        if (countryCode !== "my" && !countryName.includes("malaysia")) {
            return res.status(400).json({
                success: false,
                isMalaysia: false,
                error: "Sorry, only able to select Malaysia region"
            });
        }

        // Build street address / unit number
        const roadParts = [
            addressObj.house_number,
            addressObj.building,
            addressObj.road,
            addressObj.suburb,
            addressObj.neighbourhood || addressObj.residential
        ].filter(Boolean);

        const addressLine = roadParts.join(", ") || data.name || (data.display_name ? data.display_name.split(",").slice(0, 2).join(",") : "");
        const postcode = addressObj.postcode || "";
        const city = addressObj.city || addressObj.town || addressObj.municipality || addressObj.county || addressObj.district || "";
        const state = matchMalaysianState(addressObj.state, city, data.display_name) || addressObj.state || "";

        return res.json({
            success: true,
            isMalaysia: true,
            address: {
                addressLine,
                postcode,
                city,
                state,
                displayName: data.display_name
            }
        });
    } catch (err) {
        console.error("Reverse geocoding error:", err);
        return res.status(500).json({ success: false, error: "Failed to reverse geocode location" });
    }
});

/**
 * GET /api/address/search?q=...
 * Search places/addresses via Nominatim
 */
router.get("/search", async (req, res) => {
    try {
        const { q } = req.query;
        if (!q || !q.trim()) {
            return res.status(400).json({ success: false, error: "Search query is required" });
        }

        const url = `https://nominatim.openstreetmap.org/search?format=jsonv2&q=${encodeURIComponent(q.trim())}&addressdetails=1&accept-language=en&limit=6`;
        const response = await fetch(url, {
            headers: {
                "User-Agent": "ReByteApp/1.0 (lincoln@rebyte.com)"
            }
        });

        if (!response.ok) {
            return res.status(502).json({ success: false, error: "Search geocoding service unavailable" });
        }

        const results = await response.json();
        const mapped = results.map(item => {
            const addr = item.address || {};
            const countryCode = String(addr.country_code || "").toLowerCase();
            const countryName = String(addr.country || "").toLowerCase();
            const isMalaysia = countryCode === "my" || countryName.includes("malaysia");

            const roadParts = [
                addr.house_number,
                addr.building,
                addr.road,
                addr.suburb,
                addr.neighbourhood || addr.residential
            ].filter(Boolean);

            const addressLine = roadParts.join(", ") || item.name || (item.display_name ? item.display_name.split(",").slice(0, 2).join(",") : "");
            const postcode = addr.postcode || "";
            const city = addr.city || addr.town || addr.municipality || addr.county || addr.district || "";
            const state = matchMalaysianState(addr.state, city, item.display_name) || addr.state || "";

            return {
                lat: parseFloat(item.lat),
                lng: parseFloat(item.lon),
                displayName: item.display_name,
                name: item.name || addressLine,
                isMalaysia,
                address: {
                    addressLine,
                    postcode,
                    city,
                    state,
                    displayName: item.display_name
                }
            };
        });

        return res.json({ success: true, results: mapped });
    } catch (err) {
        console.error("Geocoding search error:", err);
        return res.status(500).json({ success: false, error: "Failed to search location" });
    }
});

/**
 * GET /api/address/current-location
 * Get approximate GPS coordinates based on user network IP
 */
router.get("/current-location", async (req, res) => {
    try {
        const clientIp = req.headers["x-forwarded-for"]?.split(",")[0]?.trim() || req.socket?.remoteAddress || "";
        const queryTarget = (!clientIp || clientIp.includes("127.0.0.1") || clientIp === "::1" || clientIp.startsWith("192.168.") || clientIp.startsWith("10."))
            ? "" // empty queries the requester's public IP on ip-api.com
            : clientIp;

        const response = await fetch(`http://ip-api.com/json/${queryTarget}?fields=status,country,countryCode,city,regionName,lat,lon,zip`, {
            signal: AbortSignal.timeout(4000)
        });

        if (response.ok) {
            const data = await response.json();
            if (data.status === "success" && data.lat && data.lon) {
                return res.json({
                    success: true,
                    lat: data.lat,
                    lng: data.lon,
                    city: data.city || "",
                    region: data.regionName || "",
                    isMalaysia: (data.countryCode === "MY" || data.country === "Malaysia")
                });
            }
        }
    } catch (e) {
        // Fallback below
    }

    // Default fallback to Kuala Lumpur coordinates
    return res.json({
        success: true,
        lat: 3.1390,
        lng: 101.6869,
        isMalaysia: true,
        fallback: true
    });
});

/**
 * GET /api/address?email=...
 * Fetch all active addresses for a customer
 */
router.get("/", async (req, res) => {
    try {
        const { email } = req.query;
        if (!email) {
            return res.status(400).json({ success: false, error: "Email or customer identifier required" });
        }

        const { customerID } = await getCustomerInfo(email);
        const targetIds = [customerID];
        if (email && email !== customerID) {
            targetIds.push(email);
        }

        const snap = await db.collection("address")
            .where("customerID", "in", targetIds)
            .get();

        const addresses = snap.docs
            .map(doc => {
                const data = doc.data();
                
                // Helper to format timestamp or date string to ISO string for JSON response
                let updatedIso = null;
                if (data.updatedAt && typeof data.updatedAt.toDate === "function") {
                    updatedIso = data.updatedAt.toDate().toISOString();
                } else if (data.updatedAt) {
                    updatedIso = String(data.updatedAt);
                }

                let createdIso = null;
                if (data.createdAt && typeof data.createdAt.toDate === "function") {
                    createdIso = data.createdAt.toDate().toISOString();
                } else if (data.createdAt) {
                    createdIso = String(data.createdAt);
                }

                return {
                    id: doc.id,
                    addressID: data.addressID || doc.id,
                    addressLine: data.addressLine || data.addressLIne || "",
                    postcode: data.postcode || "",
                    city: data.city || "",
                    state: data.state || "",
                    recipentName: data.recipentName || data.recipientName || "",
                    phoneNumber: data.phoneNumber || "",
                    addressType: data.addressType || "Home",
                    isDefault: data.isDefault === true,
                    customerID: data.customerID || customerID,
                    status: data.status || "Active",
                    createdAt: createdIso,
                    updatedAt: updatedIso
                };
            })
            .filter(item => item.status !== "delete" && item.status !== "Deleted")
            .sort((a, b) => {
                if (a.isDefault === b.isDefault) {
                    return (b.createdAt || "").localeCompare(a.createdAt || "");
                }
                return a.isDefault ? -1 : 1;
            });

        return res.json({ success: true, addresses });
    } catch (err) {
        console.error("Error fetching addresses:", err);
        return res.status(500).json({ success: false, error: "Internal server error" });
    }
});

/**
 * POST /api/address
 * Create a new address in address collection
 */
router.post("/", async (req, res) => {
    try {
        const {
            email,
            addressLine,
            postcode,
            city,
            state,
            recipentName,
            phoneNumber,
            addressType,
            isDefault
        } = req.body;

        if (!email || !addressLine || !postcode || !city || !state || !recipentName || !phoneNumber) {
            return res.status(400).json({ success: false, error: "All required address fields must be provided" });
        }

        // Validate addressType
        let finalType = (addressType || "Home").trim();
        if (finalType.length > 20) {
            return res.status(400).json({ success: false, error: "Address type cannot exceed 20 characters" });
        }

        const { customerID } = await getCustomerInfo(email);
        const targetIds = [customerID];
        if (email && email !== customerID) {
            targetIds.push(email);
        }

        // Check if customer already has any active addresses
        const existingSnap = await db.collection("address")
            .where("customerID", "in", targetIds)
            .get();

        const activeAddresses = existingSnap.docs.filter(doc => {
            const s = doc.data().status;
            return s !== "delete" && s !== "Deleted";
        });

        // If this is the user's first address, force isDefault = true
        let shouldBeDefault = isDefault === true || activeAddresses.length === 0;

        // If setting as default, unset any existing default address for this customer
        if (shouldBeDefault && activeAddresses.length > 0) {
            const batch = db.batch();
            activeAddresses.forEach(doc => {
                if (doc.data().isDefault) {
                    batch.update(doc.ref, {
                        isDefault: false,
                        updatedAt: FieldValue.serverTimestamp()
                    });
                }
            });
            await batch.commit();
        }

        const addressID = await generateAddressId();
        const addressDoc = {
            addressID,
            addressLine: addressLine.trim(),
            postcode: postcode.trim(),
            city: city.trim(),
            state: state.trim(),
            recipentName: recipentName.trim(),
            phoneNumber: phoneNumber.trim(),
            addressType: finalType,
            isDefault: shouldBeDefault,
            customerID,
            status: "Active",
            createdAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp()
        };

        await db.collection("address").doc(addressID).set(addressDoc);

        return res.status(201).json({
            success: true,
            message: "Address created successfully",
            address: {
                ...addressDoc,
                createdAt: new Date().toISOString(),
                updatedAt: new Date().toISOString()
            }
        });
    } catch (err) {
        console.error("Error creating address:", err);
        return res.status(500).json({ success: false, error: "Internal server error" });
    }
});

/**
 * PUT /api/address/:id
 * Update an existing address
 */
router.put("/:id", async (req, res) => {
    try {
        const { id } = req.params;
        const {
            email,
            addressLine,
            postcode,
            city,
            state,
            recipentName,
            phoneNumber,
            addressType,
            isDefault
        } = req.body;

        const docRef = db.collection("address").doc(id);
        const docSnap = await docRef.get();
        if (!docSnap.exists) {
            return res.status(404).json({ success: false, error: "Address not found" });
        }

        let finalType = (addressType || docSnap.data().addressType || "Home").trim();
        if (finalType.length > 20) {
            return res.status(400).json({ success: false, error: "Address type cannot exceed 20 characters" });
        }

        const { customerID } = await getCustomerInfo(email || docSnap.data().customerID);
        const targetIds = [customerID];
        if (email && email !== customerID) {
            targetIds.push(email);
        }

        const shouldBeDefault = isDefault === true;

        if (shouldBeDefault) {
            const existingSnap = await db.collection("address")
                .where("customerID", "in", targetIds)
                .get();

            const batch = db.batch();
            existingSnap.docs.forEach(d => {
                if (d.id !== id && d.data().isDefault) {
                    batch.update(d.ref, {
                        isDefault: false,
                        updatedAt: FieldValue.serverTimestamp()
                    });
                }
            });
            await batch.commit();
        }

        const updateData = {
            updatedAt: FieldValue.serverTimestamp()
        };
        if (addressLine !== undefined) updateData.addressLine = addressLine.trim();
        if (postcode !== undefined) updateData.postcode = postcode.trim();
        if (city !== undefined) updateData.city = city.trim();
        if (state !== undefined) updateData.state = state.trim();
        if (recipentName !== undefined) updateData.recipentName = recipentName.trim();
        if (phoneNumber !== undefined) updateData.phoneNumber = phoneNumber.trim();
        if (addressType !== undefined) updateData.addressType = finalType;
        if (isDefault !== undefined) updateData.isDefault = shouldBeDefault;

        await docRef.update(updateData);

        const updatedDoc = (await docRef.get()).data();
        let updatedIso = new Date().toISOString();
        if (updatedDoc.updatedAt && typeof updatedDoc.updatedAt.toDate === "function") {
            updatedIso = updatedDoc.updatedAt.toDate().toISOString();
        }

        return res.json({
            success: true,
            message: "Address updated successfully",
            address: {
                ...updatedDoc,
                updatedAt: updatedIso
            }
        });
    } catch (err) {
        console.error("Error updating address:", err);
        return res.status(500).json({ success: false, error: "Internal server error" });
    }
});

/**
 * POST /api/address/:id/default
 * Set an address as default
 */
router.post("/:id/default", async (req, res) => {
    try {
        const { id } = req.params;
        const { email } = req.body;

        const docRef = db.collection("address").doc(id);
        const docSnap = await docRef.get();
        if (!docSnap.exists) {
            return res.status(404).json({ success: false, error: "Address not found" });
        }

        const { customerID } = await getCustomerInfo(email || docSnap.data().customerID);
        const targetIds = [customerID];
        if (email && email !== customerID) {
            targetIds.push(email);
        }

        const existingSnap = await db.collection("address")
            .where("customerID", "in", targetIds)
            .get();

        const batch = db.batch();
        existingSnap.docs.forEach(d => {
            const isTarget = d.id === id;
            if (d.data().isDefault !== isTarget) {
                batch.update(d.ref, {
                    isDefault: isTarget,
                    updatedAt: FieldValue.serverTimestamp()
                });
            }
        });
        await batch.commit();

        return res.json({ success: true, message: "Default address updated successfully" });
    } catch (err) {
        console.error("Error setting default address:", err);
        return res.status(500).json({ success: false, error: "Internal server error" });
    }
});

/**
 * DELETE /api/address/:id
 * Soft delete an address record (status: 'delete')
 */
router.delete("/:id", async (req, res) => {
    try {
        const { id } = req.params;
        const { email } = req.query;

        const docRef = db.collection("address").doc(id);
        const docSnap = await docRef.get();
        if (!docSnap.exists) {
            return res.status(404).json({ success: false, error: "Address not found" });
        }

        const wasDefault = docSnap.data().isDefault === true;
        const custId = docSnap.data().customerID;

        // Soft delete
        await docRef.update({
            status: "delete",
            isDefault: false,
            deletedAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp()
        });

        // If the deleted address was default, promote the first remaining active address to default
        if (wasDefault) {
            const { customerID } = await getCustomerInfo(email || custId);
            const targetIds = [customerID];
            if (email && email !== customerID) targetIds.push(email);

            const remSnap = await db.collection("address")
                .where("customerID", "in", targetIds)
                .get();

            const activeRemain = remSnap.docs
                .filter(d => d.id !== id && d.data().status !== "delete" && d.data().status !== "Deleted");

            if (activeRemain.length > 0 && !activeRemain.some(d => d.data().isDefault)) {
                await activeRemain[0].ref.update({
                    isDefault: true,
                    updatedAt: FieldValue.serverTimestamp()
                });
            }
        }

        return res.json({ success: true, message: "Address deleted successfully" });
    } catch (err) {
        console.error("Error deleting address:", err);
        return res.status(500).json({ success: false, error: "Internal server error" });
    }
});

module.exports = router;
