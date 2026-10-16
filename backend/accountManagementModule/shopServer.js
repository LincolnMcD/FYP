const express = require("express");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const db = require("../config/firebase");

const router = express.Router();

/**
 * Helper to resolve user document from email or userId
 */
async function getUserDoc(emailOrId) {
    if (!emailOrId) return null;
    const directDoc = await db.collection("users").doc(emailOrId).get();
    if (directDoc.exists) {
        return directDoc;
    }
    const query = await db.collection("users").where("email", "==", emailOrId).limit(1).get();
    if (!query.empty) {
        return query.docs[0];
    }
    return null;
}

/**
 * GET /api/shop/products
 * Fetch listed products, filtering out those already in the requesting user's cart
 * Query: ?email=...&search=...&brand=...
 */
router.get("/products", async (req, res) => {
    try {
        const { email, search, brand } = req.query;

        // 1. Get user's cart item IDs
        let userCartProductIds = [];
        if (email) {
            const userDoc = await getUserDoc(email);
            if (userDoc && userDoc.exists) {
                const userData = userDoc.data();
                userCartProductIds = Array.isArray(userData.Cart) ? userData.Cart : [];
            }
        }

        // 2. Fetch all products with listingStatus == 'listed'
        const snapshot = await db.collection("product")
            .where("listingStatus", "==", "listed")
            .get();

        let products = [];
        snapshot.forEach(doc => {
            const data = doc.data();
            const pid = data.productID || doc.id;

            // Exclude items already in this user's cart
            if (userCartProductIds.includes(pid)) {
                return;
            }

            // Parse device info from description if separate fields are missing
            // Example: "Apple iPhone 15 Pro Max (256 GB) - Pristine condition, verified screen & battery health 95%+"
            let brandName = data.brand || "";
            let modelName = data.model || "";
            let storageSize = data.storage || "";
            let conditionStr = data.condition || "Good";

            const descStr = data.description || "";
            if (!brandName || !modelName) {
                const dashParts = descStr.split(" - ");
                const titlePart = dashParts[0] || descStr;
                const match = titlePart.match(/^([A-Za-z0-9]+)\s+(.+?)(?:\s*\(([^)]+)\))?$/);
                if (match) {
                    brandName = brandName || match[1];
                    modelName = modelName || match[2];
                    storageSize = storageSize || (match[3] || "");
                } else {
                    modelName = modelName || titlePart;
                }

                if (!data.condition && dashParts[1]) {
                    const cLower = dashParts[1].toLowerCase();
                    if (cLower.includes("pristine") || cLower.includes("brand new") || cLower.includes("like new")) {
                        conditionStr = "Brand New";
                    } else if (cLower.includes("grade a") || cLower.includes("excellent")) {
                        conditionStr = "Good";
                    } else {
                        conditionStr = "Fair";
                    }
                }
            }

            products.push({
                id: doc.id,
                productID: pid,
                description: descStr,
                brand: brandName,
                model: modelName,
                storage: storageSize,
                ram: data.ram || "",
                color: data.color || "",
                condition: conditionStr,
                sellingPrice: Number(data.sellingPrice || 0),
                listingStatus: data.listingStatus || "listed",
                imageUrl: data.imageUrl || "https://res.cloudinary.com/spyhcckw/image/upload/v1792084768/product/sample_iphone14.jpg",
                createdAt: data.createdAt
            });
        });

        // 3. Apply brand filter if specified
        if (brand && brand.toLowerCase() !== "all" && brand.toLowerCase() !== "all devices" && brand.toLowerCase() !== "all brands") {
            const brandLower = brand.toLowerCase();
            // Match either Apple or iPhone for Apple
            const isApple = brandLower === "apple" || brandLower === "iphone";
            products = products.filter(p => {
                const b = (p.brand || "").toLowerCase();
                const d = (p.description || "").toLowerCase();
                const m = (p.model || "").toLowerCase();
                if (isApple) {
                    return b.includes("apple") || d.includes("apple") || d.includes("iphone") || m.includes("iphone");
                }
                if (brandLower.includes("google") || brandLower.includes("pixel")) {
                    return b.includes("google") || d.includes("google") || d.includes("pixel") || m.includes("pixel");
                }
                return b.includes(brandLower) || d.includes(brandLower) || m.includes(brandLower);
            });
        }

        // 4. Apply search filter if specified
        if (search && typeof search === "string" && search.trim().length > 0) {
            const q = search.trim().toLowerCase();
            products = products.filter(p => {
                const desc = (p.description || "").toLowerCase();
                const title = (p.model || "").toLowerCase();
                const brand = (p.brand || "").toLowerCase();
                const pid = (p.productID || "").toLowerCase();
                return desc.includes(q) || title.includes(q) || brand.includes(q) || pid.includes(q);
            });
        }

        return res.json({
            success: true,
            products
        });
    } catch (err) {
        console.error("Error fetching shop products:", err);
        return res.status(500).json({ success: false, error: "Failed to fetch products" });
    }
});

/**
 * GET /api/shop/cart
 * Get current user's cart items with full product details and sold/available status check
 * Query: ?email=...
 */
router.get("/cart", async (req, res) => {
    try {
        const { email } = req.query;
        if (!email) {
            return res.status(400).json({ success: false, error: "Email is required" });
        }

        const userDoc = await getUserDoc(email);
        if (!userDoc || !userDoc.exists) {
            return res.status(404).json({ success: false, error: "User not found" });
        }

        const userData = userDoc.data();
        const cartProductIds = Array.isArray(userData.Cart) ? userData.Cart : [];

        if (cartProductIds.length === 0) {
            return res.json({ success: true, items: [] });
        }

        // Fetch details of each product in the user's cart
        const items = [];
        for (const pid of cartProductIds) {
            const prodDoc = await db.collection("product").doc(pid).get();
            if (prodDoc.exists) {
                const prod = prodDoc.data();
                const isSold = prod.listingStatus === "sold";

                let brandName = prod.brand || "";
                let modelName = prod.model || "";
                let storageSize = prod.storage || "";
                let conditionStr = prod.condition || "Good";

                const descStr = prod.description || "";
                if (!brandName || !modelName) {
                    const dashParts = descStr.split(" - ");
                    const titlePart = dashParts[0] || descStr;
                    const match = titlePart.match(/^([A-Za-z0-9]+)\s+(.+?)(?:\s*\(([^)]+)\))?$/);
                    if (match) {
                        brandName = brandName || match[1];
                        modelName = modelName || match[2];
                        storageSize = storageSize || (match[3] || "");
                    } else {
                        modelName = modelName || titlePart;
                    }

                    if (!prod.condition && dashParts[1]) {
                        const cLower = dashParts[1].toLowerCase();
                        if (cLower.includes("pristine") || cLower.includes("brand new") || cLower.includes("like new")) {
                            conditionStr = "Brand New";
                        } else if (cLower.includes("grade a") || cLower.includes("excellent")) {
                            conditionStr = "Good";
                        } else {
                            conditionStr = "Fair";
                        }
                    }
                }

                items.push({
                    productID: pid,
                    description: descStr,
                    sellingPrice: Number(prod.sellingPrice || 0),
                    imageUrl: prod.imageUrl || "https://res.cloudinary.com/spyhcckw/image/upload/v1792084768/product/sample_iphone14.jpg",
                    isSold: isSold,
                    listingStatus: prod.listingStatus || "listed",
                    brand: brandName,
                    model: modelName,
                    storage: storageSize,
                    ram: prod.ram || "",
                    color: prod.color || "",
                    condition: conditionStr
                });
            } else {
                // Product no longer exists in collection, mark as sold/removed
                items.push({
                    productID: pid,
                    description: "Product unavailable",
                    sellingPrice: 0,
                    imageUrl: "https://res.cloudinary.com/spyhcckw/image/upload/v1792084768/product/sample_iphone14.jpg",
                    isSold: true,
                    listingStatus: "sold",
                    brand: "",
                    model: "Unavailable Item",
                    storage: "",
                    ram: "",
                    color: "",
                    condition: "Fair"
                });
            }
        }

        return res.json({
            success: true,
            items
        });
    } catch (err) {
        console.error("Error fetching cart items:", err);
        return res.status(500).json({ success: false, error: "Failed to fetch cart" });
    }
});

/**
 * POST /api/shop/cart/add
 * Add a product to the user's Cart array
 * Body: { email, productID }
 */
router.post("/cart/add", async (req, res) => {
    try {
        const { email, productID } = req.body;
        if (!email || !productID) {
            return res.status(400).json({ success: false, error: "email and productID are required" });
        }

        const userDoc = await getUserDoc(email);
        if (!userDoc || !userDoc.exists) {
            return res.status(404).json({ success: false, error: "User not found" });
        }

        await userDoc.ref.update({
            Cart: FieldValue.arrayUnion(productID),
            updatedAt: FieldValue.serverTimestamp()
        });

        return res.json({
            success: true,
            message: "Item added to cart",
            productID
        });
    } catch (err) {
        console.error("Error adding to cart:", err);
        return res.status(500).json({ success: false, error: "Failed to add to cart" });
    }
});

/**
 * POST /api/shop/cart/remove
 * Remove a product from the user's Cart array (returning it to their shop product page)
 * Body: { email, productID }
 */
router.post("/cart/remove", async (req, res) => {
    try {
        const { email, productID } = req.body;
        if (!email || !productID) {
            return res.status(400).json({ success: false, error: "email and productID are required" });
        }

        const userDoc = await getUserDoc(email);
        if (!userDoc || !userDoc.exists) {
            return res.status(404).json({ success: false, error: "User not found" });
        }

        await userDoc.ref.update({
            Cart: FieldValue.arrayRemove(productID),
            updatedAt: FieldValue.serverTimestamp()
        });

        return res.json({
            success: true,
            message: "Item removed from cart",
            productID
        });
    } catch (err) {
        console.error("Error removing from cart:", err);
        return res.status(500).json({ success: false, error: "Failed to remove from cart" });
    }
});

/**
 * POST /api/shop/purchase
 * Purchase items currently in cart (e.g. for user A)
 * 1. Marks products as listingStatus: 'sold'
 * 2. Removes items from purchaser's cart
 * 3. Scans all other users who had this product in their Cart, and creates a notification record for them
 * Body: { email, productIDs }
 */
router.post("/purchase", async (req, res) => {
    try {
        const { email, productIDs } = req.body;
        if (!email || !Array.isArray(productIDs) || productIDs.length === 0) {
            return res.status(400).json({ success: false, error: "email and productIDs array required" });
        }

        const purchaserDoc = await getUserDoc(email);
        if (!purchaserDoc || !purchaserDoc.exists) {
            return res.status(404).json({ success: false, error: "Purchaser user not found" });
        }

        const batch = db.batch();

        // 1. Mark each product as sold
        const purchasedProductNames = [];
        for (const pid of productIDs) {
            const prodRef = db.collection("product").doc(pid);
            const prodSnap = await prodRef.get();
            const prodData = prodSnap.data() || {};
            purchasedProductNames.push(prodData.description || pid);

            batch.update(prodRef, {
                listingStatus: "sold",
                soldToEmail: email,
                soldAt: FieldValue.serverTimestamp()
            });
        }

        // 2. Remove purchased products from purchaser's Cart
        batch.update(purchaserDoc.ref, {
            Cart: FieldValue.arrayRemove(...productIDs),
            updatedAt: FieldValue.serverTimestamp()
        });

        await batch.commit();

        // 3. Notify other users who had these items in their Cart
        for (let i = 0; i < productIDs.length; i++) {
            const pid = productIDs[i];
            const pName = purchasedProductNames[i];

            // Find any other users that have this product in Cart
            const otherUsersSnap = await db.collection("users")
                .where("Cart", "array-contains", pid)
                .get();

            for (const doc of otherUsersSnap.docs) {
                if (doc.id === purchaserDoc.id || doc.data().email === email) {
                    continue; // Skip purchaser
                }

                // Add notification document for this other user
                await db.collection("notification").add({
                    email: doc.data().email,
                    userId: doc.id,
                    type: "cart_item_sold",
                    title: "Cart item being purchased by other",
                    message: `An item in your cart (${pName}) has just been purchased by another customer and is now sold out.`,
                    productID: pid,
                    isRead: false,
                    createdAt: FieldValue.serverTimestamp()
                });
            }
        }

        return res.json({
            success: true,
            message: "Purchase successful",
            purchasedItems: productIDs
        });
    } catch (err) {
        console.error("Error processing purchase:", err);
        return res.status(500).json({ success: false, error: "Failed to complete purchase" });
    }
});

/**
 * GET /api/shop/notifications
 * Fetch notifications for a user
 * Query: ?email=...
 */
router.get("/notifications", async (req, res) => {
    try {
        const { email } = req.query;
        if (!email) {
            return res.status(400).json({ success: false, error: "Email is required" });
        }

        const snap = await db.collection("notification")
            .where("email", "==", email)
            .get();

        const notifications = [];
        snap.forEach(doc => {
            const d = doc.data();
            notifications.push({
                id: doc.id,
                title: d.title || "Notification",
                message: d.message || "",
                type: d.type || "general",
                isRead: d.isRead || false,
                productID: d.productID || "",
                createdAt: d.createdAt ? d.createdAt.toDate().toISOString() : new Date().toISOString()
            });
        });

        // Sort descending by date
        notifications.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

        return res.json({
            success: true,
            notifications
        });
    } catch (err) {
        console.error("Error fetching notifications:", err);
        return res.status(500).json({ success: false, error: "Failed to fetch notifications" });
    }
});

/**
 * POST /api/shop/notifications/read
 * Mark notification as read
 * Body: { notificationId }
 */
router.post("/notifications/read", async (req, res) => {
    try {
        const { notificationId } = req.body;
        if (!notificationId) {
            return res.status(400).json({ success: false, error: "notificationId is required" });
        }

        await db.collection("notification").doc(notificationId).update({
            isRead: true,
            updatedAt: FieldValue.serverTimestamp()
        });

        return res.json({ success: true });
    } catch (err) {
        return res.status(500).json({ success: false, error: "Failed to update notification" });
    }
});

module.exports = router;
