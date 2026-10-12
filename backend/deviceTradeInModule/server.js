const express = require("express");
const androidDeviceList = require("android-device-list");
const TradeInRequest = require("../models/tradeInModel");
const Device = require("../models/deviceModel");
const db = require("../config/firebase");

const router = express.Router();

// Apple iPhone complete device catalogue
const APPLE_IPHONE_MODELS = [
    "iPhone 16 Pro Max", "iPhone 16 Pro", "iPhone 16 Plus", "iPhone 16",
    "iPhone 15 Pro Max", "iPhone 15 Pro", "iPhone 15 Plus", "iPhone 15",
    "iPhone 14 Pro Max", "iPhone 14 Pro", "iPhone 14 Plus", "iPhone 14",
    "iPhone 13 Pro Max", "iPhone 13 Pro", "iPhone 13", "iPhone 13 mini",
    "iPhone 12 Pro Max", "iPhone 12 Pro", "iPhone 12", "iPhone 12 mini",
    "iPhone 11 Pro Max", "iPhone 11 Pro", "iPhone 11",
    "iPhone SE (3rd Gen)", "iPhone SE (2nd Gen)", "iPhone SE (1st Gen)",
    "iPhone XS Max", "iPhone XS", "iPhone XR", "iPhone X",
    "iPhone 8 Plus", "iPhone 8", "iPhone 7 Plus", "iPhone 7",
    "iPhone 6s Plus", "iPhone 6s", "iPhone 6 Plus", "iPhone 6",
    "iPhone 5s", "iPhone 5c", "iPhone 5"
];

const WELL_KNOWN_MOBILE_BRANDS = [
    "Apple (iPhone)",
    "Samsung",
    "Xiaomi",
    "POCO",
    "Oppo",
    "Vivo",
    "Honor",
    "Realme",
    "Huawei",
    "ZTE",
    "OnePlus",
    "Infinix",
    "ASUS",
    "Google (Pixel)",
    "Sony",
    "Nothing",
    "Other"
];

// Curated flagship & popular models per brand (ensuring newest releases are on top)
const POPULAR_BRAND_MODELS = {
    "Samsung": [
        "Galaxy S24 Ultra", "Galaxy S24+", "Galaxy S24",
        "Galaxy S23 Ultra", "Galaxy S23+", "Galaxy S23", "Galaxy S23 FE",
        "Galaxy S22 Ultra", "Galaxy S22+", "Galaxy S22",
        "Galaxy S21 Ultra", "Galaxy S21+", "Galaxy S21", "Galaxy S21 FE",
        "Galaxy Z Fold 6", "Galaxy Z Fold 5", "Galaxy Z Fold 4", "Galaxy Z Fold 3",
        "Galaxy Z Flip 6", "Galaxy Z Flip 5", "Galaxy Z Flip 4", "Galaxy Z Flip 3",
        "Galaxy Note 20 Ultra", "Galaxy Note 20",
        "Galaxy A55 5G", "Galaxy A54 5G", "Galaxy A35 5G", "Galaxy A34 5G"
    ],
    "POCO": [
        "POCO F6 Pro", "POCO F6", "POCO X6 Pro 5G", "POCO X6 5G", "POCO X6 Neo",
        "POCO M6 Pro 5G", "POCO M6 5G", "POCO M6 Plus 5G", "POCO C65", "POCO C61",
        "POCO F5 Pro", "POCO F5", "POCO X5 Pro 5G", "POCO X5 5G",
        "POCO F4 GT", "POCO F4", "POCO X4 Pro 5G", "POCO X4 GT",
        "POCO F3", "POCO F2 Pro", "POCO F1"
    ],
    "ZTE": [
        "Nubia Z60 Ultra Leading Version", "Nubia Z60 Ultra", "Nubia Z60S Pro",
        "Nubia RedMagic 9S Pro+", "Nubia RedMagic 9S Pro", "Nubia RedMagic 9 Pro",
        "Nubia RedMagic 8S Pro", "Nubia RedMagic 8 Pro", "Nubia RedMagic 7 Pro",
        "Nubia Flip 5G", "Nubia Focus Pro 5G", "Nubia Neo 2 5G",
        "Axon 50 Ultra", "Axon 40 Ultra", "Axon 30 Ultra",
        "Blade V50 Design", "Blade A73 5G", "Blade A53 Pro"
    ],
    "Google": [
        "Pixel 9 Pro Fold", "Pixel 9 Pro XL", "Pixel 9 Pro", "Pixel 9",
        "Pixel 8 Pro", "Pixel 8", "Pixel 8a",
        "Pixel 7 Pro", "Pixel 7", "Pixel 7a",
        "Pixel 6 Pro", "Pixel 6", "Pixel 6a", "Pixel Fold"
    ],
    "Xiaomi": [
        "Xiaomi 14 Ultra", "Xiaomi 14 Pro", "Xiaomi 14",
        "Xiaomi 13 Ultra", "Xiaomi 13 Pro", "Xiaomi 13", "Xiaomi 13T Pro",
        "Xiaomi 12 Pro", "Xiaomi 12", "Xiaomi 12T Pro",
        "Redmi Note 13 Pro+ 5G", "Redmi Note 13 Pro", "Redmi Note 13 5G",
        "Redmi Note 12 Pro+", "Redmi 13C", "Redmi 12", "Redmi 10"
    ],
    "OnePlus": [
        "OnePlus 12", "OnePlus 12R", "OnePlus Open",
        "OnePlus 11", "OnePlus 11R", "OnePlus 10 Pro", "OnePlus 10T",
        "OnePlus 9 Pro", "OnePlus 9", "OnePlus Nord 4", "OnePlus Nord 3 5G"
    ],
    "Oppo": [
        "Find X7 Ultra", "Find X7", "Find N3", "Find N3 Flip",
        "Find X6 Pro", "Find X6", "Find N2 Flip",
        "Reno12 Pro 5G", "Reno12 5G", "Reno11 Pro 5G", "Reno11 5G",
        "A98 5G", "A79 5G", "A58"
    ],
    "Vivo": [
        "X100 Ultra", "X100 Pro", "X100", "X Fold 3 Pro", "X Fold 3",
        "X90 Pro", "X90", "V30 Pro", "V30", "V30e",
        "V29 5G", "V27 5G", "Y200 5G", "Y100 5G"
    ],
    "Honor": [
        "Magic V3", "Magic V2", "Magic6 Pro", "Magic6",
        "Magic5 Pro", "Honor 200 Pro", "Honor 200", "Honor 90", "Honor X9b 5G"
    ],
    "Huawei": [
        "Pura 70 Ultra", "Pura 70 Pro", "Pura 70",
        "Mate 60 Pro+", "Mate 60 Pro", "Mate X5", "P60 Pro", "Mate 50 Pro",
        "nova 12 Pro", "nova 11", "nova 10 Pro"
    ],
    "Sony": [
        "Xperia 1 VI", "Xperia 1 V", "Xperia 1 IV", "Xperia 1 III",
        "Xperia 5 V", "Xperia 5 IV", "Xperia 5 III",
        "Xperia 10 VI", "Xperia 10 V", "Xperia 10 IV", "Xperia Pro-I"
    ],
    "ASUS": [
        "ROG Phone 8 Pro", "ROG Phone 8", "ROG Phone 7 Ultimate", "ROG Phone 7",
        "ROG Phone 6", "Zenfone 11 Ultra", "Zenfone 10", "Zenfone 9"
    ],
    "Realme": [
        "GT 6", "GT 6T", "GT 5 Pro", "GT Neo 5",
        "Realme 12 Pro+ 5G", "Realme 12+ 5G", "Realme 12 5G",
        "Realme 11 Pro+", "Realme C67", "Realme C55"
    ],
    "Nothing": [
        "Phone (2a) Plus", "Phone (2a)", "Phone (2)", "Phone (1)", "CMF Phone 1"
    ],
    "Motorola": [
        "Razr 50 Ultra", "Razr 50", "Razr 40 Ultra", "Razr 40",
        "Edge 50 Ultra", "Edge 50 Pro", "Edge 50 Fusion",
        "Edge 40 Pro", "Edge 40", "Moto G84", "Moto G54"
    ],
    "Infinix": [
        "Zero 40 5G", "Zero 30 5G", "GT 20 Pro", "GT 10 Pro",
        "Note 40 Pro+ 5G", "Note 40 5G", "Hot 40 Pro"
    ],
    "Tecno": [
        "Phantom V Fold 2", "Phantom V Flip 2", "Phantom X2 Pro",
        "Camon 30 Premier 5G", "Camon 30 Pro", "Pova 6 Pro", "Spark 20 Pro+"
    ],
    "Nokia": [
        "Nokia XR21", "Nokia G42 5G", "Nokia X30 5G", "Nokia G60 5G", "Nokia C32"
    ]
};

const POPULAR_COLORS = [
    { name: "Black / Midnight / Space Gray", hex: "#1F2421" },
    { name: "White / Silver / Starlight", hex: "#E5E7EB" },
    { name: "Blue / Navy / Deep Sea", hex: "#2563EB" },
    { name: "Purple / Deep Purple / Lavender", hex: "#7C3AED" },
    { name: "Natural Titanium / Titanium Gray", hex: "#9CA3AF" },
    { name: "Green / Alpine Green / Mint", hex: "#059669" },
    { name: "Gold / Rose Gold / Bronze", hex: "#D97706" },
    { name: "Red / (PRODUCT)RED", hex: "#DC2626" },
    { name: "Yellow / Amber", hex: "#EAB308" },
    { name: "Orange / Coral / Peach", hex: "#EA580C" },
    { name: "Other", hex: "#6B7280" }
];

// Helper: Normalize brand query name (e.g. "Apple (iPhone)" -> "Apple", "Google (Pixel)" -> "Google")
function normalizeBrandName(brand) {
    if (!brand) return "";
    const b = brand.toLowerCase().trim();
    if (b.includes("apple") || b.includes("iphone")) return "Apple";
    if (b.includes("google") || b.includes("pixel")) return "Google";
    if (b.includes("poco")) return "POCO";
    if (b.includes("zte")) return "ZTE";
    return brand.trim();
}

// Helper: Get models for a specific brand from android-device-list + Apple DB
function getModelsForBrand(brand) {
    if (!brand) return [];
    
    const normalizedBrand = normalizeBrandName(brand);
    const brandLower = normalizedBrand.toLowerCase();

    // 1. Apple (iPhone)
    if (brandLower === "apple") {
        return APPLE_IPHONE_MODELS;
    }

    const modelSet = new Set();

    // 2. Add flagship / curated series for this brand
    for (const [key, list] of Object.entries(POPULAR_BRAND_MODELS)) {
        if (key.toLowerCase() === brandLower) {
            list.forEach(m => modelSet.add(m));
            break;
        }
    }

    // 3. Query android-device-list library for this brand
    try {
        const rawBrands = androidDeviceList.brandList ? androidDeviceList.brandList() : [];
        // Match brand in library
        const matchedBrand = rawBrands.find(b => b.toLowerCase() === brandLower) || normalizedBrand;
        const devices = androidDeviceList.getDevicesByBrand(matchedBrand) || [];

        const namedDevices = [];
        const unnamedDevices = [];

        devices.forEach(d => {
            const name = d.name ? d.name.trim() : '';
            const model = d.model ? d.model.trim() : '';

            if (name) {
                namedDevices.push(name);
            } else if (model) {
                unnamedDevices.push(model);
            }
        });

        // Add unique marketing names
        namedDevices.forEach(name => {
            if (name.length > 1) modelSet.add(name);
        });

        // Add remaining distinct hardware models if list is relatively small
        if (modelSet.size < 50) {
            unnamedDevices.slice(0, 50).forEach(m => {
                if (m.length > 1) modelSet.add(m);
            });
        }
    } catch (e) {
        console.error("Error retrieving models from android-device-list:", e);
    }

    return Array.from(modelSet);
}

// GET /brands - Returns strictly well-known mobile phone brands
// Query: ?search=...
router.get("/brands", (req, res) => {
    try {
        let brands = [...WELL_KNOWN_MOBILE_BRANDS];
        const { search } = req.query;

        if (search) {
            const q = search.toLowerCase();
            brands = brands.filter(b => b.toLowerCase().includes(q));
        }

        return res.status(200).json({
            success: true,
            totalBrands: brands.length,
            brands
        });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

// GET /models?brand=Samsung&search=...
router.get("/models", (req, res) => {
    try {
        const { brand, search } = req.query;
        if (!brand) {
            return res.status(400).json({ success: false, message: "Brand query parameter is required" });
        }

        let models = getModelsForBrand(brand);

        if (search) {
            const q = search.toLowerCase();
            models = models.filter(m => m.toLowerCase().includes(q));
        }

        return res.status(200).json({
            success: true,
            brand,
            totalModels: models.length,
            models
        });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

// GET /colors
router.get("/colors", (req, res) => {
    try {
        return res.status(200).json({
            success: true,
            colors: POPULAR_COLORS
        });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

// POST /estimate - initial estimation calculation
router.post("/estimate", (req, res) => {
    try {
        const { brand, model, storageCapacity } = req.body;
        if (!brand || !model || !storageCapacity) {
            return res.status(400).json({ success: false, message: "Brand, model, and storage capacity are required." });
        }

        // Basic estimation heuristic based on brand & storage
        let basePrice = 200;
        const b = brand.toLowerCase();
        if (b.includes("apple") || b.includes("iphone")) {
            basePrice = 450;
            if (model.includes("16")) basePrice = 750;
            else if (model.includes("15")) basePrice = 600;
            else if (model.includes("14")) basePrice = 450;
            else if (model.includes("13")) basePrice = 350;
        } else if (b.includes("samsung")) {
            basePrice = 380;
            if (model.toLowerCase().includes("s24")) basePrice = 700;
            else if (model.toLowerCase().includes("s23")) basePrice = 520;
            else if (model.toLowerCase().includes("z fold")) basePrice = 750;
        } else if (b.includes("google")) {
            basePrice = 350;
            if (model.toLowerCase().includes("9")) basePrice = 650;
            else if (model.toLowerCase().includes("8")) basePrice = 480;
        } else if (b.includes("poco") || b.includes("xiaomi")) {
            basePrice = 250;
            if (model.toLowerCase().includes("14") || model.toLowerCase().includes("f6")) basePrice = 400;
        } else if (b.includes("zte")) {
            basePrice = 280;
            if (model.toLowerCase().includes("z60") || model.toLowerCase().includes("redmagic")) basePrice = 550;
        }

        // Storage multiplier
        if (storageCapacity.includes("1 TB") || storageCapacity.includes("2TB")) {
            basePrice += 150;
        } else if (storageCapacity.includes("512 GB")) {
            basePrice += 100;
        } else if (storageCapacity.includes("256 GB")) {
            basePrice += 50;
        }

        return res.status(200).json({
            success: true,
            estimatedPriceMin: Math.max(50, Math.round(basePrice * 0.85)),
            estimatedPriceMax: Math.round(basePrice * 1.15),
            currency: "USD"
        });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

// POST /device - create new record for device with status pending
router.post("/device", async (req, res) => {
    try {
        const {
            deviceID,
            deviceCategory = 'smartphone',
            brand,
            model,
            storageCapacity,
            colour,
            color,
            imeiNum,
            status = 'pending',
            deviceAge,
            userEmail
        } = req.body;

        if (!brand || !model || !storageCapacity || (!colour && !color)) {
            return res.status(400).json({ success: false, message: "Missing required device details." });
        }

        // Validate device age if provided
        if (deviceAge !== undefined && deviceAge !== null && deviceAge !== '') {
            const ageNum = parseInt(String(deviceAge).replace(/\D/g, ''), 10);
            if (!isNaN(ageNum) && ageNum > 10) {
                return res.status(400).json({
                    success: false,
                    message: "The device is old, unable to trade in. Device age must be between 0 and 10 years."
                });
            }
        }

        const device = new Device({
            deviceID,
            deviceCategory,
            brand,
            model,
            storageCapacity,
            colour: colour || color,
            imeiNum,
            status,
            deviceAge,
            userEmail
        });

        if (db) {
            await db.collection("devices").doc(device.deviceID).set(device.toJSON());
        }

        return res.status(201).json({
            success: true,
            message: "New device record created with status pending.",
            device: device.toJSON()
        });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

// GET /device/:id - check device record
router.get("/device/:id", async (req, res) => {
    try {
        const { id } = req.params;
        if (!db) {
            return res.status(200).json({ success: true, deviceID: id, status: "pending" });
        }
        const doc = await db.collection("devices").doc(id).get();
        if (!doc.exists) {
            return res.status(404).json({ success: false, message: "Device not found" });
        }
        return res.status(200).json({ success: true, device: doc.data() });
    } catch (err) {
        return res.status(500).json({ success: false, message: err.message });
    }
});

module.exports = router;
