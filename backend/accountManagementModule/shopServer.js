const express = require("express");
const { FieldValue, FieldPath } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const db = require("../config/firebase");

const router = express.Router();
const PRODUCT_PAGE_SIZE = 20;
const PRODUCT_SCAN_PAGE_SIZE = 25;
const PRODUCT_CACHE_TTL_MS = 15_000;
const productPageCache = new Map();
const productCache = new Map();

function cacheGet(cache, key) {
    const entry = cache.get(key);
    if (!entry) return null;
    if (entry.expiresAt <= Date.now()) {
        cache.delete(key);
        return null;
    }
    return entry.value;
}

function cacheSet(cache, key, value, limit = 300) {
    cache.set(key, { value, expiresAt: Date.now() + PRODUCT_CACHE_TTL_MS });
    if (cache.size > limit) {
        const now = Date.now();
        for (const [entryKey, entry] of cache) {
            if (entry.expiresAt <= now || cache.size > limit) cache.delete(entryKey);
            if (cache.size <= limit) break;
        }
    }
}

function invalidateProductCaches(email = null) {
    if (!email) {
        productCache.clear();
        productPageCache.clear();
        return;
    }
    const prefix = `${String(email).trim().toLowerCase()}|`;
    for (const key of productPageCache.keys()) {
        if (key.startsWith(prefix)) productPageCache.delete(key);
    }
}

function decodeCursor(value) {
    if (!value) return null;
    try {
        const cursor = JSON.parse(Buffer.from(String(value), "base64url").toString("utf8"));
        if (typeof cursor.id !== "string" || !cursor.id) return null;
        return cursor;
    } catch (_) {
        return null;
    }
}

function cartProduct(productId, product) {
    if (!product || product._missing) {
        return {
            productID: productId,
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
        };
    }
    return {
        productID: productId,
        description: product.description,
        sellingPrice: product.sellingPrice,
        imageUrl: product.imageUrl,
        isSold: product.listingStatus === "sold",
        listingStatus: product.listingStatus,
        brand: product.brand,
        model: product.model,
        storage: product.storage,
        ram: product.ram,
        color: product.color,
        condition: product.condition
    };
}

function serializeProduct(doc) {
    const data = doc.data();
    const pid = data.productID || doc.id;
    let brandName = data.brand || "";
    let modelName = data.model || "";
    let storageSize = data.storage || "";
    let conditionStr = data.condition || "Good";
    const description = data.description || "";
    if (!brandName || !modelName) {
        const dashParts = description.split(" - ");
        const titlePart = dashParts[0] || description;
        const match = titlePart.match(/^([A-Za-z0-9]+)\s+(.+?)(?:\s*\(([^)]+)\))?$/);
        if (match) {
            brandName = brandName || match[1];
            modelName = modelName || match[2];
            storageSize = storageSize || (match[3] || "");
        } else {
            modelName = modelName || titlePart;
        }
        if (!data.condition && dashParts[1]) {
            const condition = dashParts[1].toLowerCase();
            conditionStr = condition.includes("pristine") || condition.includes("brand new") || condition.includes("like new")
                ? "Brand New"
                : condition.includes("grade a") || condition.includes("excellent") ? "Good" : "Fair";
        }
    }
    const product = {
        id: doc.id,
        productID: pid,
        description,
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
    };
    cacheSet(productCache, doc.id, product);
    return product;
}

function productMatches(product, search, brand) {
    const query = search.trim().toLowerCase();
    if (query) {
        const fields = [product.description, product.displayTitle, product.brand, product.model, product.productID]
            .map(value => String(value || "").toLowerCase());
        if (!fields.some(value => value.includes(query))) return false;
    }
    const filter = brand.trim().toLowerCase();
    if (!filter || ["all", "all devices", "all brands"].includes(filter)) return true;
    const b = product.brand.toLowerCase();
    const d = product.description.toLowerCase();
    const m = product.model.toLowerCase();
    if (filter === "apple" || filter === "iphone") return b.includes("apple") || d.includes("apple") || d.includes("iphone") || m.includes("iphone");
    if (filter.includes("google") || filter.includes("pixel")) return b.includes("google") || d.includes("google") || d.includes("pixel") || m.includes("pixel");
    return b.includes(filter) || d.includes(filter) || m.includes(filter);
}

function getEmailFromToken(decoded) {
    if (decoded.email) return decoded.email.trim().toLowerCase();
    const identities = decoded.firebase?.identities;
    if (identities && identities.email && identities.email[0]) {
        return String(identities.email[0]).trim().toLowerCase();
    }
    return "";
}

async function requireShopUser(req, res, next) {
    try {
        const token = String(req.headers.authorization || "").replace(/^Bearer\s+/i, "");
        if (!token) return res.status(401).json({ success: false, error: "Authentication required." });
        const decoded = await getAuth().verifyIdToken(token, true);
        const tokenEmail = getEmailFromToken(decoded);
        const requestedEmail = String(req.query.email || (req.body || {}).email || "").trim().toLowerCase();
        
        let userDoc = await db.collection("users").doc(decoded.uid).get();
        if (!userDoc.exists && (tokenEmail || requestedEmail)) {
            const emailToFind = tokenEmail || requestedEmail;
            const snap = await db.collection("users").where("email", "==", emailToFind).limit(1).get();
            if (!snap.empty) {
                userDoc = snap.docs[0];
            }
        }

        if (!userDoc.exists) {
            return res.status(403).json({ success: false, error: "Account not found or unavailable." });
        }

        const docEmail = String(userDoc.get("email") || "").trim().toLowerCase();
        if (requestedEmail && docEmail && docEmail !== requestedEmail) {
            return res.status(403).json({ success: false, error: "You can only access your own account." });
        }

        if (["suspended", "banned", "archived"].includes(String(userDoc.get("status") || "active").toLowerCase())) {
            return res.status(403).json({ success: false, error: "This account is not active." });
        }
        req.shopUserDoc = userDoc;
        req.shopAuth = decoded;
        next();
    } catch (err) {
        return res.status(401).json({ success: false, error: "Authentication required." });
    }
}

/**
 * GET /api/shop/products
 * Fetch listed products, filtering out those already in the requesting user's cart
 * Query: ?email=...&search=...&brand=...&sort=none|low|high&cursor=...
 */
router.get("/products", async (req, res) => {
    try {
        const email = String(req.query.email || "").trim().toLowerCase();
        const search = String(req.query.search || "").trim();
        const brand = String(req.query.brand || "").trim();
        const sort = ["low", "high"].includes(String(req.query.sort)) ? String(req.query.sort) : "none";
        let userDoc = null;
        if (email) {
            const token = String(req.headers.authorization || "").replace(/^Bearer\s+/i, "");
            if (token) {
                try {
                    const decoded = await getAuth().verifyIdToken(token, true);
                    const tokenEmail = getEmailFromToken(decoded);
                    if (tokenEmail && tokenEmail !== email) {
                        return res.status(403).json({ success: false, error: "You can only access your own account." });
                    }
                    userDoc = await db.collection("users").doc(decoded.uid).get();
                    if (!userDoc.exists) {
                        const snap = await db.collection("users").where("email", "==", email).limit(1).get();
                        if (!snap.empty) userDoc = snap.docs[0];
                    }
                } catch (e) {
                    return res.status(401).json({ success: false, error: "Authentication required." });
                }
            } else {
                const snap = await db.collection("users").where("email", "==", email).limit(1).get();
                if (!snap.empty) userDoc = snap.docs[0];
            }
        }
        const cursor = decodeCursor(req.query.cursor);
        if (req.query.cursor && (!cursor || (sort !== "none" && !Number.isFinite(Number(cursor.price))))) {
            return res.status(400).json({ success: false, error: "Invalid product cursor." });
        }

        const cacheKey = `${email}|${search.toLowerCase()}|${brand.toLowerCase()}|${sort}|${req.query.cursor || "first"}`;
        const cached = cacheGet(productPageCache, cacheKey);
        if (cached) return res.json({ ...cached, cached: true });

        let cartIds = new Set();
        if (userDoc && userDoc.exists) {
            const storedCart = Array.isArray(userDoc.data().Cart) ? userDoc.data().Cart : [];
            cartIds = new Set(storedCart.map(String));
        }

        let query = db.collection("product").where("listingStatus", "==", "listed");
        if (sort === "low") query = query.orderBy("sellingPrice", "asc").orderBy(FieldPath.documentId(), "asc");
        else if (sort === "high") query = query.orderBy("sellingPrice", "desc").orderBy(FieldPath.documentId(), "asc");
        else query = query.orderBy(FieldPath.documentId(), "asc");
        const products = [];
        let scanAfter = cursor;
        let hasMore = false;
        let filterListedInMemory = false;
        while (products.length <= PRODUCT_PAGE_SIZE) {
            let pageQuery = query.limit(PRODUCT_SCAN_PAGE_SIZE);
            if (scanAfter) {
                pageQuery = sort === "none"
                    ? pageQuery.startAfter(scanAfter.id)
                    : pageQuery.startAfter(scanAfter.price, scanAfter.id);
            }
            let snapshot;
            try {
                snapshot = await pageQuery.get();
            } catch (err) {
                const code = String(err?.code || "").toLowerCase();
                // If the listingStatus + sellingPrice composite index has not been
                // deployed yet, fall back to the built-in single-field price index.
                // Filter status on the returned page so sort/filter remains usable.
                if (!filterListedInMemory && sort !== "none" && (code === "9" || code === "failed-precondition")) {
                    filterListedInMemory = true;
                    query = db.collection("product").orderBy("sellingPrice", sort === "low" ? "asc" : "desc");
                    continue;
                }
                throw err;
            }
            if (snapshot.empty) break;

            let pageEnded = true;
            for (const doc of snapshot.docs) {
                if (filterListedInMemory && String(doc.get("listingStatus") || "").trim().toLowerCase() !== "listed") {
                    scanAfter = { id: doc.id, price: Number(doc.get("sellingPrice") || 0) };
                    continue;
                }
                const product = serializeProduct(doc);
                const productId = String(product.productID);
                if (cartIds.has(productId) || !productMatches(product, search, brand)) {
                    scanAfter = { id: doc.id, price: Number(doc.get("sellingPrice") || 0) };
                    continue;
                }
                if (products.length === PRODUCT_PAGE_SIZE) {
                    hasMore = true;
                    pageEnded = false;
                    break;
                }
                products.push(product);
                scanAfter = { id: doc.id, price: Number(doc.get("sellingPrice") || 0) };
            }
            if (!pageEnded || snapshot.size < PRODUCT_SCAN_PAGE_SIZE) break;
        }

        const result = {
            success: true,
            products,
            nextCursor: hasMore && scanAfter ? Buffer.from(JSON.stringify(scanAfter)).toString("base64url") : null,
            hasMore,
            pageSize: PRODUCT_PAGE_SIZE
        };
        cacheSet(productPageCache, cacheKey, result);
        return res.json(result);
    } catch (err) {
        console.error("Error fetching shop products:", err);
        const code = String(err?.code || "").toLowerCase();
        const error = code === "9" || code === "failed-precondition"
            ? "The product query needs a Firestore index. Deploy the project's firestore.indexes.json and try again."
            : "Failed to fetch products. Please try again.";
        return res.status(500).json({ success: false, error });
    }
});

// Product detail reads only the selected record. Its short-lived cache is also
// populated by listing and cart requests when the same product was just loaded.
router.get("/products/:productId", async (req, res) => {
    try {
        const productId = String(req.params.productId || "");
        if (!productId) return res.status(400).json({ success: false, error: "Product ID is required." });
        let product = cacheGet(productCache, productId);
        if (!product) {
            const doc = await db.collection("product").doc(productId).get();
            if (!doc.exists) return res.status(404).json({ success: false, error: "Product not found." });
            product = serializeProduct(doc);
        }
        if (product._missing) return res.status(404).json({ success: false, error: "Product not found." });
        return res.json({ success: true, product });
    } catch (err) {
        console.error("Error fetching product detail:", err);
        return res.status(500).json({ success: false, error: "Failed to fetch product." });
    }
});

/**
 * GET /api/shop/cart
 * Get current user's cart items with full product details and sold/available status check
 * Query: ?email=...
 */
router.get("/cart", requireShopUser, async (req, res) => {
    try {
        const { email } = req.query;
        if (!email) {
            return res.status(400).json({ success: false, error: "Email is required" });
        }

        const userDoc = req.shopUserDoc;
        if (!userDoc || !userDoc.exists) {
            return res.status(404).json({ success: false, error: "User not found" });
        }

        const userData = userDoc.data();
        const cartProductIds = [...new Set((Array.isArray(userData.Cart) ? userData.Cart : []).map(String))];

        if (cartProductIds.length === 0) {
            return res.json({ success: true, items: [] });
        }

        const productDocsById = new Map();
        const missingRefs = [];
        const productRefs = cartProductIds.map(pid => db.collection("product").doc(pid));
        for (let index = 0; index < cartProductIds.length; index += 100) {
            const refs = productRefs.slice(index, index + 100);
            const ids = cartProductIds.slice(index, index + 100);
            const misses = refs.filter((ref, offset) => !cacheGet(productCache, ids[offset]));
            if (misses.length) missingRefs.push(...misses);
        }
        for (let index = 0; index < missingRefs.length; index += 100) {
            const refs = missingRefs.slice(index, index + 100);
            const docs = await db.getAll(...refs);
            for (const doc of docs) {
                if (doc.exists) serializeProduct(doc);
                else cacheSet(productCache, doc.id, { _missing: true });
            }
        }
        const items = cartProductIds.map(pid => cartProduct(pid, cacheGet(productCache, pid)));

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
router.post("/cart/add", requireShopUser, async (req, res) => {
    try {
        const { email, productID } = req.body;
        if (!email || !productID) {
            return res.status(400).json({ success: false, error: "email and productID are required" });
        }

        const userDoc = req.shopUserDoc;
        if (!userDoc || !userDoc.exists) {
            return res.status(404).json({ success: false, error: "User not found" });
        }

        await userDoc.ref.update({
            Cart: FieldValue.arrayUnion(productID),
            updatedAt: FieldValue.serverTimestamp()
        });
        invalidateProductCaches(email);

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
router.post("/cart/remove", requireShopUser, async (req, res) => {
    try {
        const { email, productID } = req.body;
        if (!email || !productID) {
            return res.status(400).json({ success: false, error: "email and productID are required" });
        }

        const userDoc = req.shopUserDoc;
        if (!userDoc || !userDoc.exists) {
            return res.status(404).json({ success: false, error: "User not found" });
        }

        await userDoc.ref.update({
            Cart: FieldValue.arrayRemove(productID),
            updatedAt: FieldValue.serverTimestamp()
        });
        invalidateProductCaches(email);

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

router.post("/cart/remove-many", requireShopUser, async (req, res) => {
    try {
        const productIDs = [...new Set((Array.isArray(req.body.productIDs) ? req.body.productIDs : []).map(String).filter(Boolean))];
        if (!productIDs.length) return res.status(400).json({ success: false, error: "productIDs are required." });
        await req.shopUserDoc.ref.update({ Cart: FieldValue.arrayRemove(...productIDs), updatedAt: FieldValue.serverTimestamp() });
        invalidateProductCaches(req.shopAuth.email);
        return res.json({ success: true, productIDs });
    } catch (err) {
        console.error("Error removing multiple items from cart:", err);
        return res.status(500).json({ success: false, error: "Failed to remove cart items." });
    }
});

/** Purchase is all-or-nothing: the transaction rechecks ownership, availability
 * and prices using current documents before marking inventory sold. */
router.post("/purchase", requireShopUser, async (req, res) => {
    try {
        const { email, productIDs } = req.body;
        const expectedPrices = req.body.expectedPrices && typeof req.body.expectedPrices === "object" ? req.body.expectedPrices : {};
        const uniqueProductIDs = [...new Set((Array.isArray(productIDs) ? productIDs : []).map(String))];
        if (!email || uniqueProductIDs.length === 0 || uniqueProductIDs.length > 100) {
            return res.status(400).json({ success: false, error: "email and productIDs array required" });
        }
        const purchaserDoc = req.shopUserDoc;
        const productRefs = uniqueProductIDs.map(pid => db.collection("product").doc(pid));
        const purchasedProductNames = [];
        const transactionResult = await db.runTransaction(async transaction => {
            const freshUser = await transaction.get(purchaserDoc.ref);
            const freshProducts = await transaction.getAll(...productRefs);
            const currentCart = new Set((Array.isArray(freshUser.get("Cart")) ? freshUser.get("Cart") : []).map(String));
            for (let index = 0; index < uniqueProductIDs.length; index++) {
                const pid = uniqueProductIDs[index];
                const product = freshProducts[index];
                const data = product.data() || {};
                if (!currentCart.has(pid)) throw Object.assign(new Error("One or more selected items are no longer in your cart."), { code: "CART_CHANGED" });
                if (!product.exists || data.listingStatus !== "listed") throw Object.assign(new Error("One or more products are no longer available. Refresh your cart."), { code: "ITEM_UNAVAILABLE" });
                if (expectedPrices[pid] !== undefined && Number(expectedPrices[pid]) !== Number(data.sellingPrice || 0)) {
                    throw Object.assign(new Error("A product price changed. Review the updated cart total and try again."), { code: "PRICE_CHANGED" });
                }
                purchasedProductNames[index] = data.description || pid;
            }
            for (const ref of productRefs) {
                transaction.update(ref, { listingStatus: "sold", soldToEmail: email, soldAt: FieldValue.serverTimestamp() });
            }
            transaction.update(purchaserDoc.ref, { Cart: FieldValue.arrayRemove(...uniqueProductIDs), updatedAt: FieldValue.serverTimestamp() });
            return { purchasedItems: uniqueProductIDs };
        });
        invalidateProductCaches();

        // Query up to 30 product IDs at a time and fan out notifications in
        // bounded batches, so each other user's document is read once per group.
        let notificationBatch = db.batch();
        let notificationWrites = 0;
        const commitNotifications = async () => {
            if (!notificationWrites) return;
            try {
                await notificationBatch.commit();
            } catch (notificationError) {
                console.error("Could not write cart item sold notifications:", notificationError);
            }
            notificationBatch = db.batch();
            notificationWrites = 0;
        };
        for (let start = 0; start < uniqueProductIDs.length; start += 30) {
            const group = uniqueProductIDs.slice(start, start + 30);
            const groupNames = new Map(group.map((pid, index) => [pid, purchasedProductNames[start + index]]));
            let lastDoc = null;
            while (true) {
                let query = db.collection("users").where("Cart", "array-contains-any", group).limit(500);
                if (lastDoc) query = query.startAfter(lastDoc);
                const otherUsersSnap = await query.get();
                if (otherUsersSnap.empty) break;
                for (const doc of otherUsersSnap.docs) {
                    const otherUser = doc.data();
                    if (doc.id === purchaserDoc.id || String(otherUser.email || "").toLowerCase() === String(email).toLowerCase()) continue;
                    if (!otherUser.email) continue;
                    const matchingIds = new Set((Array.isArray(otherUser.Cart) ? otherUser.Cart : []).map(String));
                    for (const pid of group) {
                        if (!matchingIds.has(pid)) continue;
                        const notificationRef = db.collection("notification").doc();
                        notificationBatch.set(notificationRef, {
                            email: otherUser.email,
                            userId: doc.id,
                            type: "cart_item_sold",
                            title: "Cart item being purchased by other",
                            message: `An item in your cart (${groupNames.get(pid)}) has just been purchased by another customer and is now sold out.`,
                            productID: pid,
                            isRead: false,
                            createdAt: FieldValue.serverTimestamp()
                        });
                        notificationWrites += 1;
                        if (notificationWrites >= 450) await commitNotifications();
                    }
                }
                lastDoc = otherUsersSnap.docs[otherUsersSnap.docs.length - 1];
                if (otherUsersSnap.size < 500) break;
            }
        }
        await commitNotifications();

        return res.json({
            success: true,
            message: "Purchase successful",
            purchasedItems: transactionResult.purchasedItems
        });
    } catch (err) {
        if (["CART_CHANGED", "ITEM_UNAVAILABLE", "PRICE_CHANGED"].includes(err.code)) {
            return res.status(409).json({ success: false, error: err.message, code: err.code });
        }
        console.error("Error processing purchase:", err);
        return res.status(500).json({ success: false, error: "Failed to complete purchase" });
    }
});

/**
 * GET /api/shop/notifications
 * Fetch notifications for a user
 * Query: ?email=...
 */
router.get("/notifications", requireShopUser, async (req, res) => {
    try {
        const { email } = req.query;
        if (!email) {
            return res.status(400).json({ success: false, error: "Email is required" });
        }

        const snap = await db.collection("notification")
            .where("email", "==", email)
            .orderBy("createdAt", "desc")
            .limit(50)
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
router.post("/notifications/read", requireShopUser, async (req, res) => {
    try {
        const { notificationId } = req.body;
        if (!notificationId) {
            return res.status(400).json({ success: false, error: "notificationId is required" });
        }

        const notificationRef = db.collection("notification").doc(notificationId);
        const notification = await notificationRef.get();
        if (!notification.exists || String(notification.get("email") || "").toLowerCase() !== String(req.shopAuth.email || "").toLowerCase()) {
            return res.status(404).json({ success: false, error: "Notification not found." });
        }
        await notificationRef.update({
            isRead: true,
            updatedAt: FieldValue.serverTimestamp()
        });

        return res.json({ success: true });
    } catch (err) {
        return res.status(500).json({ success: false, error: "Failed to update notification" });
    }
});

/**
 * Helper to generate orderID format: YYMMDDORDXXXXX
 * Takes the latest same-date record + 1, or 00001 if none exists today
 */
async function generateOrderID() {
    const now = new Date();
    const yy = String(now.getFullYear()).slice(-2);
    const mm = String(now.getMonth() + 1).padStart(2, '0');
    const dd = String(now.getDate()).padStart(2, '0');
    const prefix = `${yy}${mm}${dd}ORD`;

    let maxSequence = 0;
    try {
        const snapshot = await db.collection("order")
            .where("orderID", ">=", prefix)
            .where("orderID", "<=", prefix + "\uf8ff")
            .get();

        snapshot.forEach((doc) => {
            const oId = doc.data().orderID || doc.id || "";
            if (oId.startsWith(prefix)) {
                const seqPart = oId.slice(prefix.length);
                const parsed = parseInt(seqPart, 10);
                if (!isNaN(parsed) && parsed > maxSequence) {
                    maxSequence = parsed;
                }
            }
        });
    } catch (e) {
        console.error("Error finding largest sequence number for orderID:", e);
    }

    const nextSequence = maxSequence + 1;
    const sequenceFormatted = String(nextSequence).padStart(5, '0');
    return `${prefix}${sequenceFormatted}`;
}

/**
 * Helper to generate transactionID format: YYMMDDTRANXXXXX
 * Takes the latest same-date record + 1, or 00001 if none exists today
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
 * Helper: Find customer record from users collection by email or uid
 */
async function resolveCustomerID(emailOrId) {
    if (!emailOrId) return "";
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
    return emailOrId;
}

/**
 * POST /api/shop/order/create
 * Creates an order record with status 'pending' when user clicks checkout
 */
router.post("/order/create", requireShopUser, async (req, res) => {
    try {
        const { email, subtotal, shippingFee, totalAmount, addressID, productIDs } = req.body;
        if (!email) {
            return res.status(400).json({ success: false, error: "email is required" });
        }

        const customerID = await resolveCustomerID(email);
        const orderID = await generateOrderID();
        const now = new Date();

        // Normalize status to proper Case (Pending, Success, Cancelled, Fail)
        let normalizedStatus = "Pending";
        if (req.body.orderStatus) {
            const s = String(req.body.orderStatus).trim().toLowerCase();
            if (s === "success") normalizedStatus = "Success";
            else if (s === "cancelled" || s === "canceled") normalizedStatus = "Cancelled";
            else if (s === "fail" || s === "failed") normalizedStatus = "Fail";
        }

        const orderData = {
            orderID: orderID,
            customerID: customerID,
            subtotal: Number(subtotal) || 0,
            shippingFee: Number(shippingFee) || 0,
            totalAmount: Number(totalAmount) || 0,
            orderStatus: normalizedStatus, // "Pending"
            orderDate: FieldValue.serverTimestamp(),
            addressID: addressID || "",
            productIDs: Array.isArray(productIDs) ? productIDs : []
        };

        await db.collection("order").doc(orderID).set(orderData);

        return res.json({
            success: true,
            orderID: orderID,
            order: orderData
        });
    } catch (err) {
        console.error("Error creating order:", err);
        return res.status(500).json({ success: false, error: "Failed to create order record" });
    }
});

/**
 * POST /api/shop/order/update-status
 * Updates orderStatus: 'Success' when payment succeeds, 'Cancelled', or 'Fail'
 */
router.post("/order/update-status", requireShopUser, async (req, res) => {
    try {
        const { orderID, orderStatus, addressID, failReason } = req.body;
        if (!orderID || !orderStatus) {
            return res.status(400).json({ success: false, error: "orderID and orderStatus required" });
        }

        let normalizedStatus = "Pending";
        const s = String(orderStatus).trim().toLowerCase();
        if (s === "success") normalizedStatus = "Success";
        else if (s === "cancelled" || s === "canceled") normalizedStatus = "Cancelled";
        else if (s === "fail" || s === "failed") normalizedStatus = "Fail";

        const updateData = {
            orderStatus: normalizedStatus,
            updatedAt: FieldValue.serverTimestamp()
        };
        if (addressID) updateData.addressID = addressID;
        if (failReason && normalizedStatus === "Fail") {
            updateData.failReason = String(failReason).trim();
        }

        await db.collection("order").doc(orderID).set(updateData, { merge: true });

        return res.json({ success: true, orderID, orderStatus: normalizedStatus });
    } catch (err) {
        console.error("Error updating order status:", err);
        return res.status(500).json({ success: false, error: "Failed to update order status" });
    }
});

/**
 * POST /api/shop/transaction/create
 * Creates a transaction record in Firebase upon transaction completion
 */
router.post("/transaction/create", requireShopUser, async (req, res) => {
    try {
        const {
            transactionType,
            transactionStatus,
            transactionAmount,
            gatewayTransactionID,
            paymentAccountID,
            orderID,
            rentalID,
            tradeInRequestID
        } = req.body;

        const transactionID = await generateTransactionID();

        // Capitalize status properly (Success, Fail, Pending)
        let normalizedStatus = "Success";
        if (transactionStatus) {
            const st = String(transactionStatus).trim().toLowerCase();
            if (st === "fail" || st === "failed") normalizedStatus = "Fail";
            else if (st === "pending") normalizedStatus = "Pending";
            else if (st === "success") normalizedStatus = "Success";
        }

        const transactionData = {
            transactionID: transactionID,
            transactionType: transactionType || "Purchase",
            transactionStatus: normalizedStatus,
            transactionAmount: Number(transactionAmount) || 0,
            transactionDate: FieldValue.serverTimestamp(),
            gatewayTransactionID: gatewayTransactionID || "",
            paymentAccountID: paymentAccountID || ""
        };

        // Select either one: if orderID, save orderID; if rentalID, save rentalID; if tradeInRequestID, save tradeInRequestID
        // Do NOT store all 3 with null values or default empty fields
        if (orderID && String(orderID).trim() !== "") {
            transactionData.orderID = String(orderID).trim();
        } else if (rentalID && String(rentalID).trim() !== "") {
            transactionData.rentalID = String(rentalID).trim();
        } else if (tradeInRequestID && String(tradeInRequestID).trim() !== "") {
            transactionData.tradeInRequestID = String(tradeInRequestID).trim();
        }

        await db.collection("transaction").doc(transactionID).set(transactionData);

        return res.json({
            success: true,
            transactionID: transactionID,
            transaction: transactionData
        });
    } catch (err) {
        console.error("Error creating transaction:", err);
        return res.status(500).json({ success: false, error: "Failed to create transaction record" });
    }
});

const nodemailer = require("nodemailer");
const receiptTransporter = nodemailer.createTransport({
    service: "gmail",
    auth: {
        user: "lolincoln021@gmail.com",
        pass: "uooc wvdf zoqy nujh"
    }
});

/**
 * POST /api/shop/send-receipt-email
 * Sends a clean, itemized receipt email to the customer with ReByte branding
 */
router.post("/send-receipt-email", requireShopUser, async (req, res) => {
    try {
        const { email, orderID, items, subtotal, shippingFee, totalAmount, paidAt, paymentTitle } = req.body;
        if (!email) {
            return res.status(400).json({ success: false, error: "email is required" });
        }

        const dateStr = paidAt ? new Date(paidAt).toLocaleString("en-MY", { timeZone: "Asia/Kuala_Lumpur" }) : new Date().toLocaleString("en-MY", { timeZone: "Asia/Kuala_Lumpur" });
        const itemList = Array.isArray(items) ? items : [];

        let itemsHtml = "";
        for (const item of itemList) {
            const title = item.productName || item.title || "Product";
            const price = Number(item.sellingPrice || item.price || 0).toFixed(2);
            itemsHtml += `
            <tr style="border-bottom: 1px solid #E2E8F0;">
                <td style="padding: 12px 8px; text-align: left; color: #1E293B; font-size: 14px; font-weight: 500;">
                    ${title}
                </td>
                <td style="padding: 12px 8px; text-align: right; color: #0F172A; font-size: 14px; font-weight: 600;">
                    RM ${price}
                </td>
            </tr>
            `;
        }

        const subtotalStr = Number(subtotal || 0).toFixed(2);
        const shippingStr = Number(shippingFee || 0).toFixed(2);
        const totalStr = Number(totalAmount || subtotal || 0).toFixed(2);

        const htmlContent = `
        <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; max-width: 520px; margin: 0 auto; background-color: #ffffff; border: 1px solid #E2E8F0; border-radius: 16px; overflow: hidden;">
            <div style="background-color: #0C5AD2; padding: 24px; text-align: center;">
                <h1 style="color: #ffffff; margin: 0; font-size: 26px; font-weight: 800; letter-spacing: 0.5px;">ReByte</h1>
                <p style="color: #E0E7FF; margin: 6px 0 0 0; font-size: 13px; font-weight: 500;">Official Payment Receipt</p>
            </div>
            
            <div style="padding: 24px;">
                <div style="background-color: #F8FAFC; border-radius: 12px; padding: 16px; margin-bottom: 20px;">
                    <table style="width: 100%; border-collapse: collapse; font-size: 13px;">
                        <tr>
                            <td style="color: #64748B; padding: 4px 0;">Order ID:</td>
                            <td style="color: #0C5AD2; font-weight: 700; text-align: right; padding: 4px 0;">${orderID || 'N/A'}</td>
                        </tr>
                        <tr>
                            <td style="color: #64748B; padding: 4px 0;">Date & Time:</td>
                            <td style="color: #0F172A; font-weight: 500; text-align: right; padding: 4px 0;">${dateStr}</td>
                        </tr>
                        <tr>
                            <td style="color: #64748B; padding: 4px 0;">Payment Method:</td>
                            <td style="color: #0F172A; font-weight: 500; text-align: right; padding: 4px 0;">${paymentTitle || 'Card / Online Banking'}</td>
                        </tr>
                    </table>
                </div>

                <h3 style="font-size: 14px; text-transform: uppercase; color: #475569; letter-spacing: 0.5px; margin: 0 0 10px 0;">Purchased Items</h3>
                <table style="width: 100%; border-collapse: collapse; margin-bottom: 20px;">
                    <thead>
                        <tr style="border-bottom: 2px solid #CBD5E1;">
                            <th style="padding: 8px; text-align: left; font-size: 12px; color: #64748B; font-weight: 600;">ITEM</th>
                            <th style="padding: 8px; text-align: right; font-size: 12px; color: #64748B; font-weight: 600;">PRICE</th>
                        </tr>
                    </thead>
                    <tbody>
                        ${itemsHtml}
                    </tbody>
                </table>

                <div style="border-top: 2px dashed #E2E8F0; padding-top: 14px;">
                    <table style="width: 100%; border-collapse: collapse; font-size: 13px;">
                        <tr>
                            <td style="color: #64748B; padding: 4px 0;">Subtotal:</td>
                            <td style="color: #0F172A; font-weight: 600; text-align: right; padding: 4px 0;">RM ${subtotalStr}</td>
                        </tr>
                        <tr>
                            <td style="color: #64748B; padding: 4px 0;">Shipping Fee:</td>
                            <td style="color: #0F172A; font-weight: 600; text-align: right; padding: 4px 0;">RM ${shippingStr}</td>
                        </tr>
                        <tr style="border-top: 1px solid #CBD5E1;">
                            <td style="color: #0F172A; font-size: 16px; font-weight: 800; padding: 12px 0 0 0;">Total Amount:</td>
                            <td style="color: #0C5AD2; font-size: 18px; font-weight: 800; text-align: right; padding: 12px 0 0 0;">RM ${totalStr}</td>
                        </tr>
                    </table>
                </div>

                <div style="margin-top: 30px; text-align: center; color: #94A3B8; font-size: 12px;">
                    <p style="margin: 0;">Thank you for shopping sustainably with ReByte!</p>
                    <p style="margin: 4px 0 0 0;">If you have any questions, reach out to support@rebyte.com</p>
                </div>
            </div>
        </div>
        `;

        const mailOptions = {
            from: "\"ReByte\" <lolincoln021@gmail.com>",
            to: email,
            subject: `ReByte Official Receipt - Order ${orderID || ''}`,
            html: htmlContent
        };

        await receiptTransporter.sendMail(mailOptions);

        return res.json({ success: true, message: "Receipt email sent successfully" });
    } catch (err) {
        console.error("Error sending receipt email:", err);
        return res.status(500).json({ success: false, error: "Failed to send receipt email: " + err.message });
    }
});

module.exports = router;


