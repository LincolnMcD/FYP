const express = require("express");
const { FieldValue, FieldPath } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const db = require("../config/firebase");
const { assignDeliveryTask } = require("../taskAssignmentModule/taskAssignmentService");

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
        condition: product.condition,
        deviceID: product.deviceID || "",
        modelCode: product.modelCode || ""
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
    const deviceID = data.deviceID || "";
    let modelCode = data.modelCode || "";
    if (Array.isArray(modelCode)) {
        modelCode = modelCode.join(", ");
    }
    const product = {
        id: doc.id,
        productID: pid,
        deviceID,
        modelCode: modelCode ? String(modelCode) : "",
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

        // Ensure device record is resolved by deviceID to get modelCode
        if (product.deviceID && (!product.modelCode || product.modelCode.trim().length === 0)) {
            try {
                let devDoc = await db.collection("devices").doc(product.deviceID).get();
                if (!devDoc.exists) {
                    const devSnap = await db.collection("devices").where("deviceID", "==", product.deviceID).limit(1).get();
                    if (!devSnap.empty) devDoc = devSnap.docs[0];
                }
                if (devDoc && devDoc.exists) {
                    const devData = devDoc.data();
                    let mCode = devData.modelCode || "";
                    if (Array.isArray(mCode)) mCode = mCode.join(", ");
                    if (mCode) product.modelCode = String(mCode);
                }
            } catch (devErr) {
                console.error("Error looking up device for product:", devErr);
            }
        }

        return res.json({ success: true, product });
    } catch (err) {
        console.error("Error fetching product detail:", err);
        return res.status(500).json({ success: false, error: "Failed to fetch product." });
    }
});

// Cache for device specs
const specCache = new Map();

/**
 * Helper to build comprehensive structured specs fallback when external TechEngine is offline
 */
function buildFallbackSpecs(brand, model, modelCode) {
    const bLower = (brand || "").toLowerCase();
    const mLower = (model || "").toLowerCase();
    const isApple = bLower.includes("apple") || mLower.includes("iphone");
    const isSamsung = bLower.includes("samsung") || mLower.includes("galaxy");
    const isPixel = bLower.includes("google") || mLower.includes("pixel");
    const isXiaomi = bLower.includes("xiaomi") || mLower.includes("poco") || mLower.includes("redmi");

    let screenDesc = '6.7" Super Retina XDR OLED (120Hz ProMotion, 2000 nits)';
    let socName = 'Apple A17 Pro (3nm)';
    let socGpu = 'Apple 6-core GPU';
    let ram = '8 GB LPDDR5';
    let battery = '4,422 mAh';
    let wiredCharging = '25W PD wired';
    let wirelessCharging = '15W MagSafe / Qi2';
    let mainCam = '48 MP, f/1.78, 24mm, sensor-shift OIS';
    let ultraCam = '12 MP, f/2.2, 13mm, 120˚';
    let teleCam = '12 MP 5x optical periscope zoom';
    let selfieCam = '12 MP, f/1.9 TrueDepth';
    let dimensions = '159.9 x 76.7 x 8.25 mm';
    let weight = '221 g';
    let ipRating = 'IP68 dust/water resistant (up to 6m for 30 mins)';
    let os = 'iOS 17 (upgradable to latest)';
    let connectivity = 'Wi-Fi 6E, Bluetooth 5.3, NFC, USB-C 3.2 Gen 2 (10Gbps)';

    if (mLower.includes("15 pro max")) {
        screenDesc = '6.7" Super Retina XDR OLED (120Hz ProMotion, 2000 nits, 2796 x 1290, 460 ppi)';
        socName = 'Apple A17 Pro (3nm, 6-core CPU)';
        socGpu = 'Apple 6-core GPU (Hardware Ray Tracing)';
        battery = '4,422 mAh';
        teleCam = '12 MP, f/2.8, 120mm (5x optical zoom), 3D sensor-shift OIS';
    } else if (mLower.includes("15 pro")) {
        screenDesc = '6.1" Super Retina XDR OLED (120Hz ProMotion, 2000 nits, 2556 x 1179, 460 ppi)';
        socName = 'Apple A17 Pro (3nm, 6-core CPU)';
        socGpu = 'Apple 6-core GPU (Hardware Ray Tracing)';
        battery = '3,274 mAh';
        teleCam = '12 MP, f/2.8, 77mm (3x optical zoom), OIS';
        dimensions = '146.6 x 70.6 x 8.25 mm';
        weight = '187 g';
    } else if (mLower.includes("14 pro max")) {
        screenDesc = '6.7" Super Retina XDR OLED (120Hz ProMotion, 2000 nits, 2796 x 1290, 460 ppi)';
        socName = 'Apple A16 Bionic (4nm, 6-core CPU)';
        socGpu = 'Apple 5-core GPU';
        battery = '4,323 mAh';
        ram = '6 GB LPDDR5';
        dimensions = '160.7 x 77.6 x 7.85 mm';
        weight = '240 g';
    } else if (mLower.includes("14")) {
        screenDesc = '6.1" Super Retina XDR OLED (60Hz, 1200 nits, 2532 x 1170, 460 ppi)';
        socName = 'Apple A15 Bionic (5nm, 6-core CPU)';
        socGpu = 'Apple 5-core GPU';
        ram = '6 GB LPDDR4X';
        battery = '3,279 mAh';
        mainCam = '12 MP, f/1.5, 26mm, sensor-shift OIS';
        teleCam = 'None';
        dimensions = '146.7 x 71.5 x 7.8 mm';
        weight = '172 g';
    } else if (mLower.includes("13")) {
        screenDesc = '6.1" Super Retina XDR OLED (60Hz, 1200 nits, 2532 x 1170, 460 ppi)';
        socName = 'Apple A15 Bionic (5nm, 6-core CPU)';
        socGpu = 'Apple 4-core GPU';
        ram = '4 GB LPDDR4X';
        battery = '3,227 mAh';
        mainCam = '12 MP, f/1.6, 26mm, sensor-shift OIS';
        teleCam = 'None';
        dimensions = '146.7 x 71.5 x 7.65 mm';
        weight = '174 g';
    } else if (mLower.includes("s24 ultra")) {
        screenDesc = '6.8" Dynamic LTPO AMOLED 2X (1-120Hz, 2600 nits, 3120 x 1440, 505 ppi, Gorilla Armor)';
        socName = 'Qualcomm Snapdragon 8 Gen 3 for Galaxy (4nm)';
        socGpu = 'Adreno 750 (1 GHz)';
        ram = '12 GB LPDDR5X';
        battery = '5,000 mAh';
        wiredCharging = '45W wired, PD3.0';
        wirelessCharging = '15W wireless (Qi/PMA), 4.5W reverse wireless';
        mainCam = '200 MP, f/1.7, 24mm, multi-directional PDAF, Laser AF, OIS';
        ultraCam = '12 MP, f/2.2, 13mm, 120˚, Dual Pixel PDAF';
        teleCam = '50 MP 5x periscope OIS + 10 MP 3x optical OIS';
        selfieCam = '12 MP, f/2.2, 26mm, Dual Pixel PDAF';
        dimensions = '162.3 x 79 x 8.6 mm';
        weight = '232 g';
        ipRating = 'IP68 dust/water resistant (up to 1.5m for 30 mins), Armor Aluminum frame';
        os = 'Android 14, One UI 6.1 (7 years OS upgrades)';
        connectivity = 'Wi-Fi 7, Bluetooth 5.3, NFC, UWB, USB-C 3.2 DisplayPort';
    } else if (mLower.includes("s24")) {
        screenDesc = '6.2" Dynamic LTPO AMOLED 2X (1-120Hz, 2600 nits, 2340 x 1080, 416 ppi)';
        socName = 'Qualcomm Snapdragon 8 Gen 3 / Exynos 2400 (4nm)';
        socGpu = 'Adreno 750 / Xclipse 940';
        ram = '8 GB LPDDR5X';
        battery = '4,000 mAh';
        wiredCharging = '25W wired, PD3.0';
        wirelessCharging = '15W wireless, 4.5W reverse wireless';
        mainCam = '50 MP, f/1.8, 24mm, Dual Pixel PDAF, OIS';
        ultraCam = '12 MP, f/2.2, 13mm, 120˚';
        teleCam = '10 MP, f/2.4, 67mm (3x optical zoom), PDAF, OIS';
        selfieCam = '12 MP, f/2.2, Dual Pixel PDAF';
        dimensions = '147 x 70.6 x 7.6 mm';
        weight = '167 g';
        ipRating = 'IP68 dust/water resistant';
        os = 'Android 14, One UI 6.1';
        connectivity = 'Wi-Fi 6E, Bluetooth 5.3, NFC, USB-C 3.2';
    } else if (mLower.includes("s23 ultra")) {
        screenDesc = '6.8" Dynamic AMOLED 2X (120Hz, 1750 nits, 3088 x 1440, 500 ppi)';
        socName = 'Qualcomm Snapdragon 8 Gen 2 for Galaxy (4nm)';
        socGpu = 'Adreno 740';
        ram = '8 GB / 12 GB LPDDR5X';
        battery = '5,000 mAh';
        wiredCharging = '45W wired, PD3.0';
        wirelessCharging = '15W wireless';
        mainCam = '200 MP, f/1.7, 24mm, Laser AF, OIS';
        ultraCam = '12 MP, f/2.2, 13mm, 120˚';
        teleCam = '10 MP 10x periscope + 10 MP 3x optical zoom, OIS';
        selfieCam = '12 MP, f/2.2, 26mm, Dual Pixel PDAF';
        dimensions = '163.4 x 78.1 x 8.9 mm';
        weight = '234 g';
        ipRating = 'IP68 dust/water resistant';
        os = 'Android 13 (upgradable to Android 14)';
        connectivity = 'Wi-Fi 6E, Bluetooth 5.3, NFC, USB-C 3.2';
    } else if (mLower.includes("s23")) {
        screenDesc = '6.1" Dynamic AMOLED 2X (120Hz, 1750 nits, 2340 x 1080, 425 ppi)';
        socName = 'Qualcomm Snapdragon 8 Gen 2 for Galaxy (4nm)';
        socGpu = 'Adreno 740';
        ram = '8 GB LPDDR5X';
        battery = '3,900 mAh';
        wiredCharging = '25W wired';
        wirelessCharging = '15W wireless';
        mainCam = '50 MP, f/1.8, 24mm, Dual Pixel PDAF, OIS';
        ultraCam = '12 MP, f/2.2, 13mm, 120˚';
        teleCam = '10 MP, f/2.4, 70mm (3x optical zoom), OIS';
        selfieCam = '12 MP, f/2.2';
        dimensions = '146.3 x 70.9 x 7.6 mm';
        weight = '168 g';
        ipRating = 'IP68 dust/water resistant';
        os = 'Android 13, One UI';
        connectivity = 'Wi-Fi 6E, Bluetooth 5.3, NFC, USB-C 3.2';
    } else if (mLower.includes("z flip 5")) {
        screenDesc = '6.7" Foldable Dynamic AMOLED 2X (120Hz) + 3.4" Super AMOLED Flex Window';
        socName = 'Qualcomm Snapdragon 8 Gen 2 for Galaxy (4nm)';
        socGpu = 'Adreno 740';
        ram = '8 GB LPDDR5X';
        battery = '3,700 mAh';
        wiredCharging = '25W wired';
        wirelessCharging = '15W wireless';
        mainCam = '12 MP, f/1.8, 24mm, Dual Pixel PDAF, OIS';
        ultraCam = '12 MP, f/2.2, 123˚';
        teleCam = 'None';
        selfieCam = '10 MP, f/2.2, 23mm';
        dimensions = '165.1 x 71.9 x 6.9 mm (Folded: 85.1 x 71.9 x 15.1 mm)';
        weight = '187 g';
        ipRating = 'IPX8 water resistant (up to 1.5m for 30 mins)';
        os = 'Android 13, One UI';
        connectivity = 'Wi-Fi 6E, Bluetooth 5.3, NFC, USB-C 3.2';
    } else if (mLower.includes("pixel 8 pro")) {
        screenDesc = '6.7" LTPO OLED Super Actua display (1-120Hz, 2400 nits, 2992 x 1344, 489 ppi)';
        socName = 'Google Tensor G3 (4nm, 9-core CPU) + Titan M2 security coprocessor';
        socGpu = 'Immortalis-G715s MC10';
        ram = '12 GB LPDDR5X';
        battery = '5,050 mAh';
        wiredCharging = '30W fast charging, PD3.0';
        wirelessCharging = '23W fast wireless (Pixel Stand)';
        mainCam = '50 MP Octa PD, f/1.68, 25mm, Laser AF, OIS';
        ultraCam = '48 MP Quad PD, f/1.95, 126˚ with Macro Focus';
        teleCam = '48 MP Quad PD 5x optical telephoto zoom, up to 30x Super Res Zoom, OIS';
        selfieCam = '10.5 MP Dual PD, f/2.2, autofocus';
        dimensions = '162.6 x 76.5 x 8.8 mm';
        weight = '213 g';
        ipRating = 'IP68 dust and water resistance';
        os = 'Android 14 (7 years of OS & security updates)';
        connectivity = 'Wi-Fi 7, Bluetooth 5.3, NFC, Ultra-Wideband (UWB), USB-C 3.2';
    } else if (mLower.includes("pixel 7 pro")) {
        screenDesc = '6.7" LTPO AMOLED (120Hz, 1500 nits, 3120 x 1440, 512 ppi)';
        socName = 'Google Tensor G2 (5nm) + Titan M2 security coprocessor';
        socGpu = 'Mali-G710 MP7';
        ram = '12 GB LPDDR5';
        battery = '5,000 mAh';
        wiredCharging = '23W wired, PD3.0';
        wirelessCharging = '23W wireless';
        mainCam = '50 MP, f/1.85, 25mm, Laser AF, OIS';
        ultraCam = '12 MP, f/2.2, 126˚';
        teleCam = '48 MP, f/3.5, 120mm (5x optical zoom), OIS';
        selfieCam = '10.8 MP, f/2.2';
        dimensions = '162.9 x 76.6 x 8.9 mm';
        weight = '212 g';
        ipRating = 'IP68 dust and water resistance';
        os = 'Android 13 (upgradable to Android 14)';
        connectivity = 'Wi-Fi 6E, Bluetooth 5.2, NFC, USB-C 3.2';
    } else if (mLower.includes("xiaomi 14 pro") || mLower.includes("14 pro")) {
        screenDesc = '6.73" LTPO AMOLED (1-120Hz, 3000 nits peak, 3200 x 1440, 522 ppi, Dolby Vision)';
        socName = 'Qualcomm Snapdragon 8 Gen 3 (4nm, Octa-Core up to 3.3 GHz)';
        socGpu = 'Adreno 750';
        ram = '16 GB LPDDR5X';
        battery = '4,880 mAh';
        wiredCharging = '120W HyperCharge wired (100% in 18 min)';
        wirelessCharging = '50W wireless HyperCharge, 10W reverse wireless';
        mainCam = '50 MP Leica Light Hunter 900, f/1.42-f/4.0 stepless variable aperture, 23mm, OIS';
        ultraCam = '50 MP Leica 115˚ ultra-wide, f/2.2, 14mm, AF';
        teleCam = '50 MP Leica 75mm floating telephoto, f/2.0, OIS, 3.2x optical zoom';
        selfieCam = '32 MP, f/2.0 wide angle';
        dimensions = '161.4 x 75.3 x 8.5 mm';
        weight = '223 g';
        ipRating = 'IP68 dust/water resistant (up to 1.5m for 30 mins)';
        os = 'Xiaomi HyperOS based on Android 14';
        connectivity = 'Wi-Fi 7, Bluetooth 5.4, Dual NFC, USB-C 3.2 Gen 2';
    } else if (mLower.includes("13 ultra")) {
        screenDesc = '6.73" LTPO AMOLED (1-120Hz, 2600 nits, 3200 x 1440, 522 ppi)';
        socName = 'Qualcomm Snapdragon 8 Gen 2 (4nm)';
        socGpu = 'Adreno 740';
        ram = '16 GB LPDDR5X';
        battery = '5,000 mAh';
        wiredCharging = '90W wired';
        wirelessCharging = '50W wireless';
        mainCam = '50 MP 1-inch Sony IMX989, f/1.9-f/4.0 variable aperture, OIS';
        ultraCam = '50 MP, f/1.8, 12mm, 122˚';
        teleCam = '50 MP 3.2x optical + 50 MP 5x periscope zoom, OIS';
        selfieCam = '32 MP, f/2.0';
        dimensions = '163.2 x 74.6 x 9.06 mm';
        weight = '227 g';
        ipRating = 'IP68 dust/water resistant';
        os = 'MIUI / HyperOS based on Android 13';
        connectivity = 'Wi-Fi 6E/7, Bluetooth 5.3, NFC, USB-C 3.2 Gen 1';
    } else if (mLower.includes("13t pro")) {
        screenDesc = '6.67" CrystalRes AMOLED (144Hz, 2600 nits, 2712 x 1220, 446 ppi)';
        socName = 'MediaTek Dimensity 9200+ (4nm)';
        socGpu = 'Immortalis-G715 MC11';
        ram = '12 GB LPDDR5X';
        battery = '5,000 mAh';
        wiredCharging = '120W HyperCharge (100% in 19 min)';
        wirelessCharging = 'None';
        mainCam = '50 MP Leica, f/1.9, 24mm, OIS';
        ultraCam = '12 MP Leica, f/2.2, 15mm';
        teleCam = '50 MP Leica 2x optical zoom, f/1.9, 50mm';
        selfieCam = '20 MP, f/2.2';
        dimensions = '162.2 x 75.7 x 8.49 mm';
        weight = '206 g';
        ipRating = 'IP68 dust/water resistant';
        os = 'MIUI 14 / HyperOS based on Android 13';
        connectivity = 'Wi-Fi 7, Bluetooth 5.4, NFC, USB-C 2.0';
    } else if (mLower.includes("oneplus 12")) {
        screenDesc = '6.82" 2K ProXDR LTPO AMOLED (1-120Hz, 4500 nits peak, 3168 x 1440, 510 ppi)';
        socName = 'Qualcomm Snapdragon 8 Gen 3 (4nm)';
        socGpu = 'Adreno 750';
        ram = '16 GB LPDDR5X';
        battery = '5,400 mAh Dual-Cell';
        wiredCharging = '100W SUPERVOOC (1-100% in 26 min)';
        wirelessCharging = '50W AIRVOOC wireless';
        mainCam = '50 MP Sony LYT-808, f/1.6, 23mm, ALC anti-reflective coating, OIS';
        ultraCam = '48 MP Sony IMX581, f/2.2, 114˚ with Macro';
        teleCam = '64 MP OmniVision OV64B 3x periscope zoom (up to 120x digital), OIS';
        selfieCam = '32 MP Sony IMX615, f/2.4';
        dimensions = '164.3 x 75.8 x 9.15 mm';
        weight = '220 g';
        ipRating = 'IP65 water & dust resistance with Aqua Touch';
        os = 'OxygenOS 14 based on Android 14';
        connectivity = 'Wi-Fi 7, Bluetooth 5.4, NFC, USB-C 3.2 Gen 1';
    } else if (mLower.includes("a15")) {
        screenDesc = '6.5" Super AMOLED (90Hz, 800 nits, 2340 x 1080 FHD+)';
        socName = 'MediaTek Helio G99 (6nm, Octa-Core)';
        socGpu = 'Mali-G57 MC2';
        ram = '4 GB / 8 GB';
        battery = '5,000 mAh';
        wiredCharging = '25W Super Fast Charging';
        wirelessCharging = 'None';
        mainCam = '50 MP, f/1.8 main camera, AF';
        ultraCam = '5 MP, f/2.2 ultra-wide';
        teleCam = '2 MP macro';
        selfieCam = '13 MP, f/2.0';
        dimensions = '160.1 x 76.8 x 8.4 mm';
        weight = '200 g';
        ipRating = 'Standard enclosure';
        os = 'Android 14, One UI 6.0';
        connectivity = 'Wi-Fi 5, Bluetooth 5.3, NFC, 3.5mm jack, USB-C 2.0';
    } else if (mLower.includes("y9 prime")) {
        screenDesc = '6.59" TFT LCD Ultra FullView (2340 x 1080 FHD+, 391 ppi)';
        socName = 'HiSilicon Kirin 710F (12nm, Octa-Core)';
        socGpu = 'Mali-G51 MP4';
        ram = '4 GB';
        battery = '4,000 mAh';
        wiredCharging = '10W standard';
        wirelessCharging = 'None';
        mainCam = '16 MP, f/1.8, PDAF';
        ultraCam = '8 MP, f/2.4, 120˚ ultra-wide';
        teleCam = '2 MP depth sensor';
        selfieCam = '16 MP, f/2.0 motorized pop-up camera';
        dimensions = '163.5 x 77.3 x 8.8 mm';
        weight = '196.8 g';
        ipRating = 'Standard splash resistance';
        os = 'EMUI 9.1 based on Android 9 (upgradable)';
        connectivity = 'Wi-Fi 802.11 a/b/g/n/ac, Bluetooth 5.0, 3.5mm jack, USB-C';
    }

    return {
        screen: screenDesc,
        soc: socName,
        gpu: socGpu,
        ram: ram,
        battery: battery,
        wired_charging: wiredCharging,
        wireless_charging: wirelessCharging,
        main_camera: mainCam,
        ultra_camera: ultraCam,
        tele_camera: teleCam,
        selfie_camera: selfieCam,
        dimensions: dimensions,
        weight: weight,
        ip_rating: ipRating,
        os: os,
        connectivity: connectivity
    };
}

/**
 * GET /api/shop/products/:productId/specs
 * Links product to device record using deviceID to get modelCode,
 * then retrieves spec details from GetTechAPI (http://localhost:8000/v1/smartphones/{slug}),
 * and falls back gracefully to local specs if the microservice is offline.
 */
router.get("/products/:productId/specs", async (req, res) => {
    try {
        const productId = String(req.params.productId || "").trim();
        if (!productId) return res.status(400).json({ success: false, error: "Product ID is required." });

        // 1. Fetch product record
        let productDoc = await db.collection("product").doc(productId).get();
        if (!productDoc.exists) {
            return res.status(404).json({ success: false, error: "Product not found." });
        }
        const pData = productDoc.data();
        const serialized = serializeProduct(productDoc);
        const deviceID = pData.deviceID || serialized.deviceID || "";

        const cacheKey = `${productId}|${deviceID}`;
        const isForceRefresh = req.query.refresh === "true";
        if (!isForceRefresh) {
            const cached = cacheGet(specCache, cacheKey);
            if (cached) return res.json({ success: true, ...cached, cached: true });
        }

        // 2. Fetch device record by deviceID
        let deviceData = null;
        let modelCode = "";
        if (deviceID) {
            let devDoc = await db.collection("devices").doc(deviceID).get();
            if (!devDoc.exists) {
                const devSnap = await db.collection("devices").where("deviceID", "==", deviceID).limit(1).get();
                if (!devSnap.empty) devDoc = devSnap.docs[0];
            }
            if (devDoc && devDoc.exists) {
                deviceData = devDoc.data();
                const rawCode = deviceData.modelCode;
                if (Array.isArray(rawCode)) {
                    modelCode = rawCode.join(", ");
                } else if (rawCode) {
                    modelCode = String(rawCode);
                }
            }
        }

        // Always prioritize the linked device record's brand and model over the product's static description!
        const brand = (deviceData && deviceData.brand) ? deviceData.brand : (serialized.brand || "");
        const model = (deviceData && deviceData.model) ? deviceData.model : (serialized.model || "");

        // 3. Prepare query slug for GetTechAPI (e.g. "galaxy-s24", "iphone-15-pro-max", "xiaomi-14-pro")
        const primaryCode = modelCode ? modelCode.split(",")[0].trim() : "";
        const slug = (model || primaryCode || serialized.displayTitle || "smartphone")
            .toLowerCase()
            .replace(/\s+/g, "-")
            .replace(/[^a-z0-9-]/g, "")
            .replace(/-+/g, "-");

        let techApiData = null;
        let source = "fallback";

        // 4. Try querying GetTechAPI at http://localhost:8000/v1/smartphones/{slug}
        try {
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), 2000); // 2 second timeout

            // First try slug endpoint, then try search with primaryCode or slug
            const techUrl = `http://localhost:8000/v1/smartphones/${encodeURIComponent(slug)}`;
            const response = await fetch(techUrl, {
                signal: controller.signal,
                headers: { "Accept": "application/json" }
            });
            clearTimeout(timeoutId);

            if (response.ok) {
                const json = await response.json();
                techApiData = json;
                source = "GetTechAPI";
            }
        } catch (apiErr) {
            // GetTechAPI is offline or unreachable - proceed to fallback specs
        }

        // Format standardized specification payload
        let specs = {};
        if (techApiData) {
            specs = {
                screen: techApiData.display ? `${techApiData.display.size_inch || ''}" ${techApiData.display.type || 'OLED'} (${techApiData.display.refresh_hz || 120}Hz, ${techApiData.display.resolution || ''})` : "",
                soc: techApiData.soc ? `${techApiData.soc.name || ''} (${techApiData.soc.manufacturer || ''} ${techApiData.soc.process_nm ? techApiData.soc.process_nm + 'nm' : ''})` : "",
                gpu: techApiData.soc ? (techApiData.soc.gpu_name || "") : "",
                ram: techApiData.ram_gb ? `${techApiData.ram_gb} GB` : serialized.ram || "",
                battery: techApiData.battery_mah ? `${techApiData.battery_mah} mAh` : "",
                wired_charging: techApiData.charging_wired_w ? `${techApiData.charging_wired_w}W wired` : "",
                wireless_charging: techApiData.charging_wireless_w ? `${techApiData.charging_wireless_w}W wireless` : "",
                main_camera: Array.isArray(techApiData.cameras) && techApiData.cameras[0] ? `${techApiData.cameras[0].mp} MP (${techApiData.cameras[0].type || 'Main'})` : "",
                ultra_camera: Array.isArray(techApiData.cameras) && techApiData.cameras[1] ? `${techApiData.cameras[1].mp} MP (${techApiData.cameras[1].type || 'Ultrawide'})` : "",
                tele_camera: Array.isArray(techApiData.cameras) && techApiData.cameras[2] ? `${techApiData.cameras[2].mp} MP (${techApiData.cameras[2].type || 'Telephoto'})` : "",
                dimensions: techApiData.dimensions ? `${techApiData.dimensions.height_mm} x ${techApiData.dimensions.width_mm} x ${techApiData.dimensions.depth_mm} mm` : "",
                weight: techApiData.weight_g ? `${techApiData.weight_g} g` : "",
                ip_rating: techApiData.ip_rating || "",
                os: techApiData.os ? `${techApiData.os} ${techApiData.os_version || ''}`.trim() : "",
                connectivity: techApiData.connectivity ? Object.entries(techApiData.connectivity).map(([k, v]) => `${k.toUpperCase()}: ${v}`).join(", ") : ""
            };
        } else {
            specs = buildFallbackSpecs(brand, model, modelCode);
        }

        const payload = {
            productID: productId,
            deviceID,
            modelCode,
            brand,
            model,
            storage: serialized.storage,
            color: serialized.color,
            source,
            specs
        };

        cacheSet(specCache, cacheKey, payload, 300);
        return res.json({ success: true, ...payload });
    } catch (err) {
        console.error("Error retrieving device specs for product:", err);
        return res.status(500).json({ success: false, error: "Failed to retrieve device specs." });
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

        // Normalize status to proper Case (Pending, Delivering, Cancelled, Fail)
        let normalizedStatus = "Pending";
        if (req.body.orderStatus) {
            const s = String(req.body.orderStatus).trim().toLowerCase();
            if (s === "success" || s === "delivering" || s === "shipping") normalizedStatus = "Delivering";
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

        if (normalizedStatus === "Delivering") {
            const taskID = `TSK-${orderID}`;
            await db.collection("task").doc(taskID).set({
                taskID: taskID,
                taskType: "deliver",
                taskStatus: "Packaging",
                taskStartTime: null,
                estimatedDuration: null,
                scheduleID: null,
                orderID: orderID,
                appointmentID: null,
                createdAt: FieldValue.serverTimestamp()
            }, { merge: true });
        }

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
        if (s === "success" || s === "delivering" || s === "shipping") normalizedStatus = "Delivering";
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

        // If orderStatus is Delivering, create task and trigger task assignment
        if (normalizedStatus === "Delivering") {
            const taskID = `TSK-${orderID}`;
            const taskDocRef = db.collection("task").doc(taskID);
            const taskSnap = await taskDocRef.get();
            if (!taskSnap.exists) {
                await taskDocRef.set({
                    taskID: taskID,
                    taskType: "deliver",
                    taskStatus: "Packaging",
                    taskStartTime: null,
                    estimatedDuration: null,
                    scheduleID: null,
                    orderID: orderID,
                    appointmentID: null,
                    createdAt: FieldValue.serverTimestamp()
                });
            }

            // Trigger automated task assignment via OSRM algorithm
            assignDeliveryTask({
                orderID,
                addressID: addressID || updateData.addressID,
                requestedDate: new Date()
            }).catch(err => {
                console.error(`Automatic task assignment for order ${orderID} failed:`, err);
            });
        }

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

/**
 * GET /api/shop/orders
 * Retrieves all orders for the current authenticated user, populated with product items
 */
router.get("/orders", requireShopUser, async (req, res) => {
    try {
        const email = String(req.query.email || "").trim().toLowerCase();
        if (!email) {
            return res.status(400).json({ success: false, error: "email is required" });
        }

        const userDoc = req.shopUserDoc;
        const customerID = userDoc ? userDoc.id : await resolveCustomerID(email);

        // Fetch orders by customerID or email
        let ordersSnap = await db.collection("order")
            .where("customerID", "==", customerID)
            .get();

        if (ordersSnap.empty && email) {
            ordersSnap = await db.collection("order")
                .where("email", "==", email)
                .get();
        }

        const ordersList = await Promise.all(ordersSnap.docs.map(async (doc) => {
            const data = doc.data();
            const orderID = data.orderID || doc.id;
            const pIds = Array.isArray(data.productIDs) ? data.productIDs : [];

            // Populate products concurrently
            const itemPromises = pIds.map(async (pid) => {
                try {
                    let prod = cacheGet(productCache, pid);
                    if (!prod) {
                        const pDoc = await db.collection("product").doc(pid).get();
                        if (pDoc.exists) {
                            prod = serializeProduct(pDoc);
                        }
                    }
                    if (prod) {
                        return {
                            productID: prod.productID || pid,
                            description: prod.description || "",
                            sellingPrice: Number(prod.sellingPrice || 0),
                            imageUrl: prod.imageUrl || "https://res.cloudinary.com/spyhcckw/image/upload/v1792084768/product/sample_iphone14.jpg",
                            brand: prod.brand || "",
                            model: prod.model || "",
                            storage: prod.storage || "",
                            ram: prod.ram || "",
                            color: prod.color || "",
                            condition: prod.condition || "Good",
                            listingStatus: prod.listingStatus || "sold"
                        };
                    }
                } catch (_) {}
                return null;
            });

            // Populate delivery address concurrently
            const addressPromise = (async () => {
                if (!data.addressID) return null;
                try {
                    const aDoc = await db.collection("address").doc(data.addressID).get();
                    if (aDoc.exists) {
                        const aData = aDoc.data();
                        return {
                            id: aDoc.id,
                            addressID: aData.addressID || aDoc.id,
                            addressLine: aData.addressLine || "",
                            city: aData.city || "",
                            state: aData.state || "",
                            postcode: aData.postcode || "",
                            recipentName: aData.recipentName || aData.recipientName || "",
                            phoneNumber: aData.phoneNumber || "",
                            addressType: aData.addressType || "Home",
                            isDefault: !!aData.isDefault
                        };
                    }
                } catch (_) {}
                return null;
            })();

            // Lookup transaction payment concurrently
            const paymentPromise = (async () => {
                let paymentTitle = "Online Payment";
                let paymentAccountID = "";
                let paymentType = "card";

                try {
                    const tSnap = await db.collection("transaction").where("orderID", "==", orderID).limit(1).get();
                    if (!tSnap.empty) {
                        const tData = tSnap.docs[0].data();
                        paymentAccountID = tData.paymentAccountID || "";

                        if (paymentAccountID === "ewallet_all") {
                            paymentTitle = "E-Wallet";
                            paymentType = "ewallet";
                        } else if (paymentAccountID === "fpx_online_banking" || paymentAccountID === "fpx") {
                            paymentTitle = "FPX Online Banking";
                            paymentType = "fpx";
                        } else if (paymentAccountID) {
                            paymentType = "card";
                            try {
                                const pDoc = await db.collection("paymentAccount").doc(paymentAccountID).get();
                                if (pDoc.exists && pDoc.data().cardNumber) {
                                    const cNum = String(pDoc.data().cardNumber).replace(/\s+/g, "");
                                    const last4 = cNum.slice(-4);
                                    paymentTitle = `************ ${last4}`;
                                } else {
                                    paymentTitle = `************ ${String(paymentAccountID).slice(-4)}`;
                                }
                            } catch (_) {
                                paymentTitle = `************ ${String(paymentAccountID).slice(-4)}`;
                            }
                        } else if (tData.gatewayTransactionID) {
                            paymentTitle = "Online Payment";
                            paymentType = "card";
                        }
                    }
                } catch (_) {}
                return { paymentTitle, paymentAccountID, paymentType };
            })();

            // Lookup task status and schedule timing concurrently
            const taskPromise = (async () => {
                let taskStatus = "Packaging";
                let estimatedEndTime = null;
                let scheduleDate = null;
                let estimatedDuration = null;
                try {
                    const taskID = `TSK-${orderID}`;
                    const taskDoc = await db.collection("task").doc(taskID).get();
                    if (taskDoc.exists) {
                        const tData = taskDoc.data();
                        if (tData.taskStatus) taskStatus = tData.taskStatus;
                        if (tData.estimatedDuration) estimatedDuration = tData.estimatedDuration;

                        if (tData.scheduleID) {
                            const sDoc = await db.collection("schedule").doc(tData.scheduleID).get();
                            if (sDoc.exists) {
                                const sData = sDoc.data();
                                estimatedEndTime = sData.scheduleEndTime || null;
                                scheduleDate = sData.scheduleDate || null;
                            }
                        }
                    }
                } catch (_) {}
                return { taskStatus, estimatedEndTime, scheduleDate, estimatedDuration };
            })();

            const [itemsRaw, deliveryAddress, paymentInfo, taskInfo] = await Promise.all([
                Promise.all(itemPromises),
                addressPromise,
                paymentPromise,
                taskPromise
            ]);

            const items = itemsRaw.filter(Boolean);

            // Convert orderDate
            let paidAtDate = new Date();
            if (data.orderDate && data.orderDate.toDate) {
                paidAtDate = data.orderDate.toDate();
            } else if (data.orderDate) {
                paidAtDate = new Date(data.orderDate);
            } else if (data.createdAt && data.createdAt.toDate) {
                paidAtDate = data.createdAt.toDate();
            }

            let displayStatus = data.orderStatus || "Delivering";
            if (String(displayStatus).trim().toLowerCase() === "success") {
                displayStatus = "Delivering";
            }

            return {
                orderID,
                orderNumber: orderID.startsWith("#") ? orderID : `#${orderID}`,
                orderStatus: displayStatus,
                taskStatus: taskInfo.taskStatus,
                estimatedEndTime: taskInfo.estimatedEndTime,
                scheduleDate: taskInfo.scheduleDate,
                estimatedDuration: taskInfo.estimatedDuration,
                failReason: data.failReason || data.cancelledReason || data.cancelReason || "",
                subtotal: Number(data.subtotal || data.totalAmount || 0),
                shippingFee: Number(data.shippingFee || 0),
                totalAmount: Number(data.totalAmount || data.subtotal || 0),
                amountPaid: Number(data.totalAmount || data.subtotal || 0),
                addressID: data.addressID || "",
                deliveryAddress,
                paymentTitle: paymentInfo.paymentTitle,
                paymentAccountID: paymentInfo.paymentAccountID,
                paymentType: paymentInfo.paymentType,
                paidAt: paidAtDate.toISOString(),
                items
            };
        }));

        // Sort orders newest first
        ordersList.sort((a, b) => new Date(b.paidAt).getTime() - new Date(a.paidAt).getTime());

        return res.json({
            success: true,
            orders: ordersList
        });
    } catch (err) {
        console.error("Error fetching orders:", err);
        return res.status(500).json({ success: false, error: "Failed to fetch orders" });
    }
});

module.exports = router;


