const express = require("express");
const path = require("path");
const fs = require("fs");
const androidDeviceList = require("android-device-list");
const TradeInRequest = require("../models/tradeInModel");
const Device = require("../models/deviceModel");
const TradeInRequestImage = require("../models/tradeInRequestImageModel");
const cloudinary = require("../config/cloudinary");
const multer = require("multer");
const db = require("../config/firebase");
const { FieldValue } = require("firebase-admin/firestore");
const { assignTradeInTask, checkSlotAvailabilityForDate, checkMonthAvailabilityForTradeIn } = require("../taskAssignmentModule/taskAssignmentService");
const { autoResolveOverdueTradeInTasks } = require("../taskAssignmentModule/taskDelayMonitorService");

const router = express.Router();
const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 10 * 1024 * 1024 } // 10MB limit per image
});

// Official Google Play supported devices in-memory cache
// Covers over 54,000+ certified devices including latest models (e.g. Galaxy A15, A25, S24, Honor 90/200, etc.)
const googlePlayBrandToModels = {};
const googlePlayModelToCode = {};
const googlePlayModelToCodes = {};
const googlePlayBrandNormToCodes = {}; // brand -> normKey -> Set of model codes
const googlePlayBrandCodeToNames = {}; // brand:::CODE -> Array of model names

function initGooglePlayDevices() {
    const csvPath = path.join(__dirname, "google_play_devices.csv");
    if (!fs.existsSync(csvPath)) return;
    try {
        console.time("loadGooglePlayDevices");
        const buffer = fs.readFileSync(csvPath);
        const text = buffer.toString("utf16le");
        const lines = text.split(/\r?\n/);

        for (let i = 1; i < lines.length; i++) {
            const line = lines[i].trim();
            if (!line) continue;
            const parts = line.split('","');
            if (parts.length >= 4) {
                const brand = parts[0].replace(/^"/, '').trim();
                let name = parts[1].trim();
                const model = parts[3].replace(/"$/, '').trim();

                if (!brand) continue;
                const bLower = brand.toLowerCase();
                if (!googlePlayBrandToModels[bLower]) {
                    googlePlayBrandToModels[bLower] = new Set();
                    googlePlayBrandNormToCodes[bLower] = {};
                }

                // Ignore names containing Chinese, Japanese, or Korean characters
                const nonLatinRegex = /[\u4e00-\u9fa5\u3040-\u30ff\uac00-\ud7af]/;
                if (nonLatinRegex.test(name) && !nonLatinRegex.test(model)) {
                    // Use clean Latin model name if available, else skip
                    name = model;
                }
                if (nonLatinRegex.test(name)) continue;

                const mName = name || model;
                if (mName && !nonLatinRegex.test(mName)) {
                    googlePlayBrandToModels[bLower].add(mName);
                    const key = bLower + ":::" + mName.toLowerCase();
                    if (!googlePlayModelToCodes[key]) {
                        googlePlayModelToCodes[key] = new Set();
                    }
                    if (model) {
                        googlePlayModelToCodes[key].add(model);
                        if (!googlePlayModelToCode[key]) {
                            googlePlayModelToCode[key] = model;
                        }

                        // Index reverse lookup: brand + modelCode -> model names
                        const codeKey = bLower + ":::" + model.toUpperCase().replace(/[^A-Z0-9]/g, '');
                        if (!googlePlayBrandCodeToNames[codeKey]) {
                            googlePlayBrandCodeToNames[codeKey] = [];
                        }
                        if (!googlePlayBrandCodeToNames[codeKey].includes(mName)) {
                            googlePlayBrandCodeToNames[codeKey].push(mName);
                        }

                        // Pre-index under normalized key for instantaneous multi-code lookup
                        const normKey = normalizeModelSearchTerm(mName) + (mName.toLowerCase().includes('5g') ? '_5g' : '');
                        if (!googlePlayBrandNormToCodes[bLower][normKey]) {
                            googlePlayBrandNormToCodes[bLower][normKey] = new Set();
                        }
                        googlePlayBrandNormToCodes[bLower][normKey].add(model);

                        // Also pre-index without brand prefix (e.g. "huawei y9 prime 2019" -> "y9 prime 2019")
                        const bPartNorm = normalizeModelSearchTerm(bLower);
                        const normWithoutB = normKey.startsWith(bPartNorm) ? normKey.slice(bPartNorm.length) : normKey;
                        if (normWithoutB.length > 3) {
                            if (!googlePlayBrandNormToCodes[bLower][normWithoutB]) {
                                googlePlayBrandNormToCodes[bLower][normWithoutB] = new Set();
                            }
                            googlePlayBrandNormToCodes[bLower][normWithoutB].add(model);
                        }
                    }
                }
            }
        }
        console.timeEnd("loadGooglePlayDevices");
        console.log(`Loaded Google Play database: ${Object.keys(googlePlayBrandToModels).length} brands, 54,000+ devices indexed.`);
    } catch (e) {
        console.error("Failed to load Google Play devices database:", e.message);
    }
}
initGooglePlayDevices();

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
    "Apple",
    "Samsung",
    "Xiaomi",
    "OPPO",
    "HONOR",
    "vivo",
    "realme",
    "Huawei",
    "Redmi",
    "POCO",
    "OnePlus",
    "Nothing",
    "ASUS",
    "Google Pixel",
    "Motorola",
    "Infinix",
    "TECNO",
    "ZTE",
    "nubia",
    "Sony"
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
        "Galaxy A55 5G", "Galaxy A54 5G", "Galaxy A35 5G", "Galaxy A34 5G",
        "Galaxy A25 5G", "Galaxy A15 5G", "Galaxy A15", "Galaxy A14 5G", "Galaxy A05s"
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

// Helper: Normalize brand query name (e.g. "Google Pixel" -> "Google", "nubia" -> "Nubia")
function normalizeBrandName(brand) {
    if (!brand) return "";
    const b = brand.toLowerCase().trim();
    if (b.includes("apple") || b.includes("iphone")) return "Apple";
    if (b.includes("google") || b.includes("pixel")) return "Google";
    if (b === "poco") return "POCO";
    if (b === "zte") return "ZTE";
    if (b === "nubia") return "nubia";
    if (b === "oppo") return "OPPO";
    if (b === "honor") return "HONOR";
    if (b === "redmi") return "Redmi";
    return brand.trim();
}

// Helper: Get models for a specific brand from Google Play Database + Apple DB + curated flagship series
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
        if (key.toLowerCase() === brandLower || key.toLowerCase() === brand.toLowerCase().trim()) {
            list.forEach(m => modelSet.add(m));
            break;
        }
    }

    // 3. Query Google Play Certified Supported Devices Database (54,000+ devices)
    // Handle brand aliases in Google Play (e.g. Google Pixel -> google, Redmi -> redmi & xiaomi redmi)
    const gpKeys = [brandLower];
    if (brandLower === "google pixel" || brandLower === "google") {
        gpKeys.push("google");
    }
    if (brandLower === "redmi") {
        gpKeys.push("redmi");
        // Also include Redmi models listed under Xiaomi in Google Play
        const xiaomiSet = googlePlayBrandToModels["xiaomi"];
        if (xiaomiSet) {
            xiaomiSet.forEach(m => {
                if (m.toLowerCase().includes("redmi")) modelSet.add(m);
            });
        }
    }

    gpKeys.forEach(k => {
        const gpModels = googlePlayBrandToModels[k];
        if (gpModels && gpModels.size > 0) {
            gpModels.forEach(m => {
                if (m.length > 1) modelSet.add(m);
            });
        }
    });

    // 4. Query android-device-list library as additional source
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

        const nonLatinRegex = /[\u4e00-\u9fa5\u3040-\u30ff\uac00-\ud7af]/;
        // Add unique marketing names (ignoring non-Latin / Chinese names)
        namedDevices.forEach(name => {
            if (name.length > 1 && !nonLatinRegex.test(name)) modelSet.add(name);
        });

        // Add remaining distinct hardware models if list is relatively small
        if (modelSet.size < 50) {
            unnamedDevices.slice(0, 50).forEach(m => {
                if (m.length > 1 && !nonLatinRegex.test(m)) modelSet.add(m);
            });
        }
    } catch (e) {
        console.error("Error retrieving models from android-device-list:", e);
    }

    return Array.from(modelSet);
}

// Helper: Extract model code (e.g. A2638, SM-S928B, 2407FPN8EG, GKV4X) from TAC record specs or specs text
function extractModelCodeFromSpecs(specs) {
    if (!specs) return null;
    let clean = specs.replace(/"/g, '');
    // Remove appended publication years like "2019", "2020", "STK-L212019" -> "STK-L21"
    clean = clean.replace(/([A-Z0-9\/\-]+)(20[12][0-9])\b/gi, '$1');
    clean = clean.replace(/\b20[12][0-9]\b/g, ' ');

    // 1. Apple model codes: A followed by 4 digits (e.g. A2638, A3106, A3293)
    const appleMatch = clean.match(/\b(A\d{4})\b/i);
    if (appleMatch) return appleMatch[1].toUpperCase();

    // 2. Samsung model codes: SM-..., SC-..., GT-... (e.g. SM-S928B, SM-S928, SM-S918U1)
    const samsungMatch = clean.match(/\b((?:SM|SC|GT)-[A-Z0-9]+(?:\/[A-Z0-9]+)?)/i);
    if (samsungMatch) return samsungMatch[1].toUpperCase();

    // 3. Xiaomi / Poco / Android model codes (e.g. 2407FPN8EG, 2406APNFAG, 24117RK2CG)
    const xiaomiMatch = clean.match(/\b([0-9]{4,5}[A-Z0-9]{4,8})\b/i);
    if (xiaomiMatch) return xiaomiMatch[1].toUpperCase();

    // 4. Pixel model codes (e.g. GKV4X, G576D, GWKK3, G0DZQ, GE2AE, G1AZ8)
    const pixelMatch = clean.match(/\b(G[0-9A-Z]{4})\b/i);
    if (pixelMatch) return pixelMatch[1].toUpperCase();

    // 5. Generic hardware code pattern (e.g. STK-L21, STK-LX3, XQ-EC54, CPH2581, ANY-LX1)
    const genericMatch = clean.match(/\b([A-Z]{2,4}-[A-Z0-9]{3,8}|[A-Z]{3}[0-9]{4,5})\b/i);
    if (genericMatch) return genericMatch[1].toUpperCase();

    return null;
}

// Well-known base model codes for popular flagship models
const KNOWN_MODEL_CODES = {
    // Apple iPhones
    "iPhone 16 Pro Max": "A3296",
    "iPhone 16 Pro": "A3293",
    "iPhone 16 Plus": "A3290",
    "iPhone 16": "A3287",
    "iPhone 15 Pro Max": "A3106",
    "iPhone 15 Pro": "A3102",
    "iPhone 15 Plus": "A3094",
    "iPhone 15": "A3090",
    "iPhone 14 Pro Max": "A2894",
    "iPhone 14 Pro": "A2890",
    "iPhone 14 Plus": "A2886",
    "iPhone 14": "A2882",
    "iPhone 13 Pro Max": "A2643",
    "iPhone 13 Pro": "A2638",
    "iPhone 13 mini": "A2628",
    "iPhone 13": "A2633",
    "iPhone 12 Pro Max": "A2411",
    "iPhone 12 Pro": "A2407",
    "iPhone 12 mini": "A2399",
    "iPhone 12": "A2403",
    "iPhone 11 Pro Max": "A2218",
    "iPhone 11 Pro": "A2215",
    "iPhone 11": "A2221",
    "iPhone SE (3rd Gen)": "A2783",
    "iPhone SE (2nd Gen)": "A2275",
    "iPhone XS Max": "A2101",
    "iPhone XS": "A2097",
    "iPhone XR": "A2105",
    "iPhone X": "A1901",
    "iPhone 8 Plus": "A1897",
    "iPhone 8": "A1905",
    "iPhone 7 Plus": "A1784",
    "iPhone 7": "A1778",

    // Samsung Galaxy
    "Galaxy S24 Ultra": "SM-S928",
    "Galaxy S24+": "SM-S926",
    "Galaxy S24": "SM-S921",
    "Galaxy S23 Ultra": "SM-S918",
    "Galaxy S23+": "SM-S916",
    "Galaxy S23": "SM-S911",
    "Galaxy S23 FE": "SM-S711",
    "Galaxy S22 Ultra": "SM-S908",
    "Galaxy S22+": "SM-S906",
    "Galaxy S22": "SM-S901",
    "Galaxy S21 Ultra": "SM-G998",
    "Galaxy S21+": "SM-G996",
    "Galaxy S21": "SM-G991",
    "Galaxy S21 FE": "SM-G990",
    "Galaxy Z Fold 6": "SM-F956",
    "Galaxy Z Fold 5": "SM-F946",
    "Galaxy Z Fold 4": "SM-F936",
    "Galaxy Z Fold 3": "SM-F926",
    "Galaxy Z Flip 6": "SM-F741",
    "Galaxy Z Flip 5": "SM-F731",
    "Galaxy Z Flip 4": "SM-F721",
    "Galaxy Z Flip 3": "SM-F711",
    "Galaxy Note 20 Ultra": "SM-N986",
    "Galaxy Note 20": "SM-N981",
    "Galaxy A55 5G": "SM-A556",
    "Galaxy A54 5G": "SM-A546",
    "Galaxy A35 5G": "SM-A356",
    "Galaxy A34 5G": "SM-A346",
    "Galaxy A25 5G": "SM-A256",
    "Galaxy A15 5G": "SM-A156",
    "Galaxy A15": "SM-A155",
    "Galaxy A14 5G": "SM-A146",

    // Google Pixel
    "Pixel 9 Pro XL": "G1AZ8",
    "Pixel 9 Pro": "GE2AE",
    "Pixel 9": "GUR25",
    "Pixel 8 Pro": "GC3VE",
    "Pixel 8": "GPJ41",
    "Pixel 8a": "GKV4X",
    "Pixel 7 Pro": "GE2AE",
    "Pixel 7": "GVU6C",
    "Pixel 7a": "GWKK3",
    "Pixel 6 Pro": "GLUOG",
    "Pixel 6": "GB7N6",
    "Pixel 6a": "GX7AS",

    // Xiaomi & POCO
    "Xiaomi 14 Ultra": "24030PN60G",
    "Xiaomi 14 Pro": "23116PN5BC",
    "Xiaomi 14": "23127PN0CG",
    "Xiaomi 13 Ultra": "2304FPN6DC",
    "Xiaomi 13 Pro": "2210132G",
    "Xiaomi 13": "2211133G",
    "Xiaomi 13T Pro": "23078PND5G",
    "POCO F6 Pro": "23113RKC6G",
    "POCO F6": "24069PC21G",
    "POCO X6 Pro 5G": "2311DRK48G",
    "POCO X6 5G": "23122PCD1G"
};

// Helper: Normalize model name for robust cross-matching
function normalizeModelSearchTerm(m) {
    if (!m) return '';
    return m.toLowerCase()
        .replace(/\+/g, 'plus')
        .replace(/\b5g\b/g, '')
        .replace(/[^a-z0-9]/g, '');
}

// Helper: Resolve ALL modelCodes given brand and model name (does not stop at first match)
function getModelCodeForModel(brand, modelName) {
    if (!modelName) return null;
    const cleanModel = modelName.trim();
    const bLower = (brand || '').toLowerCase().trim();

    // 1. Apple: Dedicated exact or normalized lookup
    if (bLower === "apple" || bLower.includes("iphone")) {
        if (KNOWN_MODEL_CODES[cleanModel]) return KNOWN_MODEL_CODES[cleanModel];
        const norm = cleanModel.toLowerCase().replace(/[^a-z0-9]/g, '');
        for (const [k, v] of Object.entries(KNOWN_MODEL_CODES)) {
            const kNorm = k.toLowerCase().replace(/[^a-z0-9]/g, '');
            if (norm === kNorm || norm.includes(kNorm) || kNorm.includes(norm)) {
                return v;
            }
        }
    }

    // 2. Look up hardware models in Google Play Certified Devices Database (54,000+ devices)
    // Instantaneous multi-code lookup across the complete Google Play dataset
    const collectedCodes = new Set();
    try {
        const directKey = bLower + ":::" + cleanModel.toLowerCase();
        if (googlePlayModelToCodes[directKey] && googlePlayModelToCodes[directKey].size > 0) {
            googlePlayModelToCodes[directKey].forEach(c => collectedCodes.add(c));
        }

        const brandNormMap = googlePlayBrandNormToCodes[bLower] || {};
        const targetNorm = normalizeModelSearchTerm(cleanModel) + (cleanModel.toLowerCase().includes('5g') ? '_5g' : '');
        const bPartNorm = normalizeModelSearchTerm(bLower);
        const normWithoutB = targetNorm.startsWith(bPartNorm) ? targetNorm.slice(bPartNorm.length) : targetNorm;

        if (brandNormMap[targetNorm]) {
            brandNormMap[targetNorm].forEach(c => collectedCodes.add(c));
        }
        if (normWithoutB.length > 3 && brandNormMap[normWithoutB]) {
            brandNormMap[normWithoutB].forEach(c => collectedCodes.add(c));
        }
    } catch (_) {}

    // 3. Look up in android-device-list library as well (scan until finish)
    try {
        const rawBrands = androidDeviceList.brandList ? androidDeviceList.brandList() : [];
        const matchedBrand = rawBrands.find(b => b.toLowerCase() === bLower);
        if (matchedBrand) {
            const devices = androidDeviceList.getDevicesByBrand(matchedBrand) || [];
            const targetNorm = normalizeModelSearchTerm(cleanModel);
            const bPartNorm = normalizeModelSearchTerm(bLower);
            const targetWithoutB = targetNorm.startsWith(bPartNorm) ? targetNorm.slice(bPartNorm.length) : targetNorm;

            for (const d of devices) {
                const dName = (d.name || '').trim();
                const dModel = (d.model || '').trim();
                const dNorm = normalizeModelSearchTerm(dName);
                const dWithoutB = dNorm.startsWith(bPartNorm) ? dNorm.slice(bPartNorm.length) : dNorm;

                if (dName.toLowerCase() === cleanModel.toLowerCase() ||
                    dModel.toLowerCase() === cleanModel.toLowerCase() ||
                    (dNorm.length > 3 && dNorm === targetNorm) ||
                    (targetWithoutB.length > 3 && targetWithoutB === dWithoutB)) {
                    if (dModel) collectedCodes.add(dModel);
                }
            }
        }
    } catch (_) {}

    // 4. Return all collected unique model codes joined by comma
    if (collectedCodes.size > 0) {
        const cleanList = Array.from(collectedCodes)
            .map(c => extractModelCodeFromSpecs(c) || c.trim())
            .filter(Boolean);
        const unique = Array.from(new Set(cleanList));
        if (unique.length > 0) {
            return unique.join(', ');
        }
    }

    // 5. Fallback to KNOWN_MODEL_CODES if available
    if (KNOWN_MODEL_CODES[cleanModel]) {
        return KNOWN_MODEL_CODES[cleanModel];
    }
    const norm = cleanModel.toLowerCase().replace(/[^a-z0-9]/g, '');
    for (const [k, v] of Object.entries(KNOWN_MODEL_CODES)) {
        const kNorm = k.toLowerCase().replace(/[^a-z0-9]/g, '');
        if (norm === kNorm || norm.includes(kNorm) || kNorm.includes(norm)) {
            return v;
        }
    }

    // 6. Fallback: Check if cleanModel itself contains a model code
    const extracted = extractModelCodeFromSpecs(cleanModel);
    if (extracted) return extracted;

    // 7. Fallback generated code
    const bShort = (brand || "DEV").replace(/[^a-zA-Z]/g, '').substring(0, 3).toUpperCase();
    const mDigits = cleanModel.replace(/[^0-9]/g, '');
    return `${bShort}${mDigits || '001'}`;
}

// Helper: Check if detected modelCode from IMEI matches expected modelCode(s)
// e.g. detected "STK-L21" matches expected "STK-L21, STK-L22, STK-LX3"
// e.g. "XXXXSM1234XXX" / "SM-S928B" matches "SM1234" / "SM-S928"
function isModelCodeMatch(detectedCode, expectedCode) {
    if (!detectedCode || !expectedCode) return false;
    const d = detectedCode.toUpperCase().replace(/[^A-Z0-9]/g, '');
    if (!d) return false;

    // expectedCode may be comma-separated multiple codes (e.g. "STK-L21, STK-L22, STK-LX3")
    const candidates = String(expectedCode).split(',').map(c => c.trim()).filter(Boolean);
    for (const cand of candidates) {
        const e = cand.toUpperCase().replace(/[^A-Z0-9]/g, '');
        if (e && (d.includes(e) || e.includes(d))) {
            return true;
        }
    }
    return false;
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

        // Return array of models, plus modelCodes map for convenience
        const modelCodes = {};
        models.forEach(m => {
            modelCodes[m] = getModelCodeForModel(brand, m);
        });

        return res.status(200).json({
            success: true,
            brand,
            totalModels: models.length,
            models,
            modelCodes
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
            userEmail,
            modelCode = null
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

        const resolvedModelCode = modelCode || getModelCodeForModel(brand, model);

        const device = new Device({
            deviceID,
            deviceCategory,
            brand,
            model,
            modelCode: resolvedModelCode,
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

// Helper to generate tradeInRequestID format: TRYYMMDDXXXXX (X is sequence number based on today's existing tradeInRequests records)
async function generateTradeInRequestID() {
    const now = new Date();
    const yy = String(now.getFullYear()).slice(-2);
    const mm = String(now.getMonth() + 1).padStart(2, '0');
    const dd = String(now.getDate()).padStart(2, '0');
    const prefix = `TR${yy}${mm}${dd}`;

    let maxSequence = 0;

    if (db) {
        try {
            // Check all tradeInRequests starting with today's prefix TRYYMMDD
            const snapshot = await db.collection("tradeInRequests")
                .where("tradeInRequestID", ">=", prefix)
                .where("tradeInRequestID", "<=", prefix + "\uf8ff")
                .get();

            snapshot.forEach((doc) => {
                const reqID = doc.data().tradeInRequestID || doc.id || "";
                if (reqID.startsWith(prefix)) {
                    // Extract the suffix sequence number
                    const seqPart = reqID.slice(prefix.length);
                    const parsedSeq = parseInt(seqPart, 10);
                    if (!isNaN(parsedSeq) && parsedSeq > maxSequence) {
                        maxSequence = parsedSeq;
                    }
                }
            });
        } catch (e) {
            console.error("Error finding largest sequence number from tradeInRequests:", e);
        }
    }

    const nextSequence = maxSequence + 1;
    const sequenceFormatted = String(nextSequence).padStart(5, '0');
    return `${prefix}${sequenceFormatted}`;
}

// Helper to upload buffer to Cloudinary
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

// POST /submit-request - Page 3: Creates device record (status pending), uploads images to Cloudinary, creates TradeInRequest & TradeInRequestImage records
router.post("/submit-request", upload.any(), async (req, res) => {
    try {
        const body = req.body || {};
        const {
            deviceID: clientDeviceID,
            deviceCategory = 'smartphone',
            brand,
            model,
            storageCapacity,
            colour,
            color,
            imeiNum,
            deviceAge,
            userEmail,
            imagesBase64, // In case sent as JSON/Map of base64
        } = body;

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

        // 1. Create or persist Device record with pending status
        const resolvedModelCode = body.modelCode || getModelCodeForModel(brand, model);
        const device = new Device({
            deviceID: clientDeviceID,
            deviceCategory,
            brand,
            model,
            modelCode: resolvedModelCode,
            storageCapacity,
            colour: colour || color,
            imeiNum,
            status: 'pending',
            deviceAge,
            userEmail
        });

        if (db) {
            await db.collection("devices").doc(device.deviceID).set(device.toJSON(), { merge: true });
        }

        // 2. Obtain or Generate TradeInRequestID (TRYYMMDDXXXXX)
        // If client provides an existing tradeInRequestID from current flow session, reuse & update it!
        let tradeInRequestID = body.tradeInRequestID || null;
        let isUpdate = false;

        if (tradeInRequestID && db) {
            const existingDoc = await db.collection("tradeInRequests").doc(tradeInRequestID).get();
            if (existingDoc.exists) {
                isUpdate = true;
            }
        }

        if (!tradeInRequestID) {
            tradeInRequestID = await generateTradeInRequestID();
        }

        // 3. Create or Update TradeInRequest document
        const tradeInRequest = new TradeInRequest({
            tradeInRequestID: tradeInRequestID,
            requestStatus: 'Pending',
            deviceID: device.deviceID,
            userEmail: userEmail || null,
        });

        const tradeInRequestRef = db ? db.collection("tradeInRequests").doc(tradeInRequest.tradeInRequestID) : null;
        if (tradeInRequestRef) {
            await tradeInRequestRef.set(tradeInRequest.toJSON(), { merge: true });
        }

        // 4. Process removed images (if user cleared an image slot, purge it from Firestore and Cloudinary)
        let removedImageViews = [];
        try {
            if (body.removedImageViews) {
                removedImageViews = typeof body.removedImageViews === 'string'
                    ? JSON.parse(body.removedImageViews)
                    : body.removedImageViews;
            }
        } catch (_) {}

        if (tradeInRequestRef && Array.isArray(removedImageViews) && removedImageViews.length > 0) {
            for (const rmView of removedImageViews) {
                try {
                    const toDeleteDocs = await tradeInRequestRef.collection("images")
                        .where("imageView", "==", rmView)
                        .get();

                    for (const doc of toDeleteDocs.docs) {
                        const oldData = doc.data();
                        if (oldData && oldData.imageUrl) {
                            try {
                                const matches = oldData.imageUrl.match(/upload\/(?:v\d+\/)?(.+?)(?:\.[a-zA-Z0-9]+)?$/);
                                if (matches && matches[1]) {
                                    await cloudinary.uploader.destroy(matches[1]).catch(() => {});
                                }
                            } catch (_) {}
                        }
                        await doc.ref.delete().catch(() => {});
                    }
                } catch (delErr) {
                    console.error(`Error deleting removed image ${rmView}:`, delErr);
                }
            }
        }

        // 5. Process and upload each image:
        // If an image with this imageView already exists for this request, delete old image from Cloudinary & Firestore first!
        const uploadedImages = [];
        const files = req.files || [];

        const uploadTasks = files.map(async (file) => {
            const imageView = file.fieldname || 'front';
            const publicName = `${imageView}_${Date.now()}`;
            const folder = `rebyte/trade_in/${tradeInRequestID}`;

            try {
                // Delete existing images for this imageView from Firestore & Cloudinary if updating
                if (tradeInRequestRef) {
                    const existingImgDocs = await tradeInRequestRef.collection("images")
                        .where("imageView", "==", imageView)
                        .get();

                    for (const doc of existingImgDocs.docs) {
                        const oldData = doc.data();
                        if (oldData && oldData.imageUrl) {
                            try {
                                // Extract public_id from Cloudinary URL if available to delete from Cloudinary
                                const matches = oldData.imageUrl.match(/upload\/(?:v\d+\/)?(.+?)(?:\.[a-zA-Z0-9]+)?$/);
                                if (matches && matches[1]) {
                                    await cloudinary.uploader.destroy(matches[1]).catch(() => {});
                                }
                            } catch (_) {}
                        }
                        await doc.ref.delete().catch(() => {});
                    }
                }

                // Upload new image
                const cloudResult = await uploadBufferToCloudinary(file.buffer, folder, publicName);
                const reqImage = new TradeInRequestImage({
                    imageUrl: cloudResult.secure_url,
                    imageView: imageView,
                    tradeInRequestID: tradeInRequestID
                });

                if (tradeInRequestRef) {
                    await tradeInRequestRef.collection("images").doc(reqImage.imageID).set(reqImage.toJSON());
                }
                uploadedImages.push(reqImage.toJSON());
            } catch (uploadErr) {
                console.error(`Failed to process ${imageView}:`, uploadErr);
            }
        });

        // Run uploads in parallel with Promise.all for maximum speed!
        await Promise.all(uploadTasks);

        return res.status(isUpdate ? 200 : 201).json({
            success: true,
            isUpdate: isUpdate,
            message: isUpdate 
                ? "Trade-in request and device images updated successfully."
                : "Trade-in request and device images submitted successfully.",
            tradeInRequestID: tradeInRequest.tradeInRequestID,
            tradeInRequest: tradeInRequest.toJSON(),
            device: device.toJSON(),
            images: uploadedImages
        });
    } catch (err) {
        console.error("submit-request error:", err);
        return res.status(500).json({ success: false, message: err.message });
    }
});

// POST /finalize-request - Updates tradeInRequest requestStatus to 'Submitted' and stores validated imeiNum
router.post("/finalize-request", async (req, res) => {
    try {
        const { tradeInRequestID, imeiNum, imei } = req.body;
        const finalImei = (imeiNum || imei || '').trim();

        if (!tradeInRequestID) {
            return res.status(400).json({ success: false, message: "Missing tradeInRequestID." });
        }

        if (db) {
            const requestRef = db.collection("tradeInRequests").doc(tradeInRequestID);
            const doc = await requestRef.get();
            if (!doc.exists) {
                return res.status(404).json({ success: false, message: "Trade-in request not found." });
            }

            const requestUpdates = {
                requestStatus: "Submitted",
                submittedAt: new Date()
            };
            if (finalImei) {
                requestUpdates.imeiNum = finalImei;
            }

            await requestRef.update(requestUpdates);

            // Also update associated device status and imeiNum
            const reqData = doc.data();
            if (reqData && reqData.deviceID) {
                const deviceUpdates = {
                    status: "submitted"
                };
                if (finalImei) {
                    deviceUpdates.imeiNum = finalImei;
                }
                await db.collection("devices").doc(reqData.deviceID).update(deviceUpdates).catch(() => {});
            }
        }

        return res.status(200).json({
            success: true,
            message: "Trade-in request successfully submitted.",
            tradeInRequestID,
            imeiNum: finalImei || null
        });
    } catch (err) {
        console.error("finalize-request error:", err);
        return res.status(500).json({ success: false, message: err.message });
    }
});

// GET /active-pending - Retrieve existing pending trade-in request for a user if resuming
router.get("/active-pending", async (req, res) => {
    try {
        const { userEmail } = req.query;
        if (!userEmail || !db) {
            return res.status(200).json({ success: true, pendingRequest: null });
        }

        const snapshot = await db.collection("tradeInRequests")
            .where("userEmail", "==", userEmail)
            .where("requestStatus", "==", "Pending")
            .limit(1)
            .get();

        if (snapshot.empty) {
            return res.status(200).json({ success: true, pendingRequest: null });
        }

        const doc = snapshot.docs[0];
        const reqData = doc.data();

        // Also fetch device data if available
        let deviceData = null;
        if (reqData.deviceID) {
            const devDoc = await db.collection("devices").doc(reqData.deviceID).get();
            if (devDoc.exists) {
                deviceData = devDoc.data();
            }
        }

        return res.status(200).json({
            success: true,
            pendingRequest: reqData,
            device: deviceData
        });
    } catch (err) {
        console.error("active-pending error:", err);
        return res.status(500).json({ success: false, message: err.message });
    }
});

const parseEstimatedValueObject = (val, defaultVal = null) => {
    if (!val) return defaultVal;
    if (typeof val === 'object') {
        const min = Number(val.min != null ? val.min : (val.minEstimatedValue != null ? val.minEstimatedValue : (defaultVal ? defaultVal.min : 2340.50)));
        const max = Number(val.max != null ? val.max : (val.maxEstimatedValue != null ? val.maxEstimatedValue : (defaultVal ? defaultVal.max : 2355.30)));
        return {
            min: isNaN(min) ? (defaultVal ? defaultVal.min : 2340.50) : Number(min.toFixed(2)),
            max: isNaN(max) ? (defaultVal ? defaultVal.max : 2355.30) : Number(max.toFixed(2))
        };
    }
    if (typeof val === 'string') {
        const matches = val.replace(/,/g, '').match(/\d+(?:\.\d+)?/g);
        if (matches && matches.length >= 2) {
            return {
                min: Number(parseFloat(matches[0]).toFixed(2)),
                max: Number(parseFloat(matches[1]).toFixed(2))
            };
        } else if (matches && matches.length === 1) {
            const num = Number(parseFloat(matches[0]).toFixed(2));
            return { min: num, max: num };
        }
    }
    if (typeof val === 'number') {
        const num = Number(val.toFixed(2));
        return { min: num, max: num };
    }
    return defaultVal;
};

// POST /update-status - Updates tradeInRequest requestStatus (e.g. 'Evaluated', 'Quoted') and device status
router.post("/update-status", async (req, res) => {
    try {
        const { tradeInRequestID, status, estimatedValue } = req.body;
        if (!tradeInRequestID || !status) {
            return res.status(400).json({ success: false, message: "Missing tradeInRequestID or status." });
        }

        if (db) {
            const cleanId = String(tradeInRequestID).replace(/^#/, '');
            let requestRef = db.collection("tradeInRequests").doc(cleanId);
            let doc = await requestRef.get();
            if (!doc.exists) {
                requestRef = db.collection("tradeInRequests").doc(tradeInRequestID);
                doc = await requestRef.get();
            }
            if (!doc.exists) {
                return res.status(404).json({ success: false, message: "Trade-in request not found." });
            }

            const reqData = doc.data() || {};
            const isCancel = status.toLowerCase() === 'cancelled' || status.toLowerCase() === 'canceled';
            const isDecline = status.toLowerCase() === 'declined' || status.toLowerCase() === 'rejected';
            const isAccepted = status.toLowerCase() === 'accepted';

            // When accept or reject offer: ONLY change status and updatedAt date (bookingStatus and requestStatus NO NEED to change)
            if (isAccepted || isDecline) {
                const targetStatus = isAccepted 
                    ? 'Accepted' 
                    : (status.toLowerCase() === 'rejected' ? 'Rejected' : 'Declined');
                const now = new Date();
                const updatePayload = {
                    status: targetStatus,
                    updatedAt: now
                };
                if (targetStatus === 'Rejected') {
                    updatePayload.rejectedAt = now;
                    updatePayload.declinedAt = now;
                } else if (targetStatus === 'Declined') {
                    updatePayload.declinedAt = now;
                } else {
                    updatePayload.acceptedAt = now;
                }
                await requestRef.update(updatePayload);
                if (reqData && reqData.deviceID) {
                    await db.collection("devices").doc(reqData.deviceID).update({
                        status: targetStatus,
                        updatedAt: now
                    }).catch(() => {});
                }
                return res.status(200).json({
                    success: true,
                    message: `Trade-in offer ${targetStatus.toLowerCase()} successfully.`,
                    tradeInRequestID,
                    status: targetStatus
                });
            }

            const targetStatus = isCancel ? 'Cancelled' : status;

            const updateData = {
                requestStatus: targetStatus,
                status: targetStatus,
                updatedAt: new Date()
            };

            if (isCancel) {
                updateData.bookingStatus = 'Cancelled';
                updateData.cancelledAt = new Date();
                updateData.cancelledBy = 'Customer';
            } else if (status.toLowerCase() === 'completed') {
                updateData.bookingStatus = 'Completed';
                updateData.completedAt = new Date();
            } else if (status.toLowerCase() === 'inspected') {
                updateData.bookingStatus = 'Inspected';
                updateData.inspectedAt = new Date();
            } else if (status.toLowerCase() === 'evaluated') {
                updateData.evaluatedAt = new Date();
            } else if (status.toLowerCase() === 'quoted') {
                updateData.quotedAt = new Date();
                // estimatedValue is added to the record when transitioning to 'Quoted'
                const valToParse = estimatedValue || reqData.estimatedValue || { min: 2340.50, max: 2355.30 };
                updateData.estimatedValue = parseEstimatedValueObject(valToParse, { min: 2340.50, max: 2355.30 });
            } else if (status.toLowerCase() === 'agreed') {
                updateData.agreedAt = new Date();
            }

            await requestRef.update(updateData);
            if (reqData && reqData.deviceID) {
                await db.collection("devices").doc(reqData.deviceID).update({
                    status: isCancel ? 'cancelled' : status,
                    deviceStatus: isCancel ? 'cancelled' : status,
                    updatedAt: new Date()
                }).catch(() => {});
            }

            // DONT change appointment and task for accept or decline!
            // Only update appointment/task if it was an explicit pre-inspection cancellation (isCancel)
            if (isCancel) {
                const candidateIds = Array.from(new Set([tradeInRequestID, cleanId, `#${cleanId}`, doc.id]));

                // 1. Find all appointment records linked to this request
                const appIds = new Set();
                if (reqData.appointmentID) {
                    appIds.add(reqData.appointmentID);
                }
                for (const cId of candidateIds) {
                    try {
                        const aSnap = await db.collection("tradeInAppointment").where("tradeInRequestID", "==", cId).get();
                        for (const aDoc of aSnap.docs) {
                            appIds.add(aDoc.id);
                        }
                    } catch (_) {}
                }

                // 2. Update tradeInAppointment records to Cancelled
                for (const appID of appIds) {
                    try {
                        await db.collection("tradeInAppointment").doc(appID).update({
                            appointmentStatus: "Cancelled",
                            bookingStatus: "Cancelled",
                            status: "Cancelled",
                            cancelledAt: new Date(),
                            updatedAt: new Date()
                        });
                    } catch (_) {}
                }

                // 3. Find all tasks linked to this appointment or request
                const taskIds = new Set();
                for (const appID of appIds) {
                    try {
                        const tSnap = await db.collection("task").where("appointmentID", "==", appID).get();
                        for (const tDoc of tSnap.docs) {
                            taskIds.add(tDoc.id);
                        }
                    } catch (_) {}
                }
                for (const cId of candidateIds) {
                    try {
                        const tSnap = await db.collection("task").where("tradeInRequestID", "==", cId).get();
                        for (const tDoc of tSnap.docs) {
                            taskIds.add(tDoc.id);
                        }
                    } catch (_) {}
                }

                // 4. Update task records to Cancelled and collect scheduleIDs
                const scheduleIds = new Set();
                for (const tID of taskIds) {
                    try {
                        const tDoc = await db.collection("task").doc(tID).get();
                        if (tDoc.exists) {
                            const tData = tDoc.data();
                            if (tData.scheduleID) {
                                scheduleIds.add(tData.scheduleID);
                            }
                            await tDoc.ref.update({
                                taskStatus: "Cancelled",
                                status: "Cancelled",
                                cancelledAt: new Date(),
                                updatedAt: new Date()
                            });
                        }
                    } catch (_) {}
                }

                // 5. Also collect schedules linked by appointmentID or starting with SCH-<appointmentID>
                for (const appID of appIds) {
                    try {
                        const sSnap = await db.collection("schedule").get();
                        for (const sDoc of sSnap.docs) {
                            if (sDoc.id.startsWith(`SCH-${appID}`) || sDoc.data().appointmentID === appID) {
                                scheduleIds.add(sDoc.id);
                            }
                        }
                    } catch (_) {}
                }

                // 6. For schedule records with scheduleStatus: "assigned", update to "cancelled"
                for (const sID of scheduleIds) {
                    try {
                        const sDoc = await db.collection("schedule").doc(sID).get();
                        if (sDoc.exists) {
                            const sData = sDoc.data();
                            if (sData.scheduleStatus === "assigned") {
                                await sDoc.ref.update({
                                    scheduleStatus: "cancelled",
                                    cancelledAt: new Date(),
                                    updatedAt: new Date()
                                });
                            }
                        }
                    } catch (_) {}
                }
            }

            return res.status(200).json({
                success: true,
                tradeInRequestID: cleanId,
                status: targetStatus,
                message: `Trade-in request updated to ${targetStatus}.`
            });
        }

        return res.status(200).json({ success: true });
    } catch (err) {
        console.error("update-status error:", err);
        return res.status(500).json({ success: false, message: err.message });
    }
});

router.post("/book-appointment", async (req, res) => {
    try {
        const { tradeInRequestID, method, appointmentDate, appointmentTime, address, addressID } = req.body;
        if (!tradeInRequestID || !appointmentDate || !appointmentTime) {
            return res.status(400).json({ success: false, message: "Missing required booking fields." });
        }

        if (db) {
            const cleanId = String(tradeInRequestID).replace(/^#/, '');
            let requestRef = db.collection("tradeInRequests").doc(cleanId);
            let doc = await requestRef.get();
            if (!doc.exists) {
                requestRef = db.collection("tradeInRequests").doc(tradeInRequestID);
                doc = await requestRef.get();
            }
            if (!doc.exists) {
                return res.status(404).json({ success: false, message: "Trade-in request not found." });
            }

            const docData = doc.data();
            const candidateIds = Array.from(new Set([tradeInRequestID, cleanId, `#${cleanId}`, doc.id]));

            // 1. Identify existing appointment and task records to reuse (DO NOT create new appointment/task records)
            let existingAppointmentID = docData.appointmentID || null;
            if (!existingAppointmentID) {
                try {
                    const prevApps = await db.collection("tradeInAppointment")
                        .where("tradeInRequestID", "in", candidateIds.slice(0, 10))
                        .limit(1)
                        .get();
                    if (!prevApps.empty) {
                        existingAppointmentID = prevApps.docs[0].id;
                    }
                } catch (_) {}
            }

            let existingTaskID = null;
            try {
                if (existingAppointmentID) {
                    const prevTasks = await db.collection("task")
                        .where("appointmentID", "==", existingAppointmentID)
                        .limit(1)
                        .get();
                    if (!prevTasks.empty) {
                        existingTaskID = prevTasks.docs[0].id;
                    }
                }
                if (!existingTaskID) {
                    const directTasks = await db.collection("task")
                        .where("tradeInRequestID", "in", candidateIds.slice(0, 10))
                        .limit(1)
                        .get();
                    if (!directTasks.empty) {
                        existingTaskID = directTasks.docs[0].id;
                    }
                }
            } catch (_) {}

            // 2. Reassign trade-in task into existing appointment and task records
            const assignmentResult = await assignTradeInTask({
                tradeInRequestID: cleanId,
                method: method || "On-Site Inspection",
                appointmentDate,
                appointmentTime,
                address,
                addressID: addressID || (address && address.addressID),
                existingAppointmentID,
                existingTaskID,
                forceNewRecords: false
            });

            if (!assignmentResult || !assignmentResult.success || !assignmentResult.appointmentID) {
                console.error("[BOOK-APPOINTMENT ERROR] Task assignment failed:", assignmentResult?.message);
                return res.status(400).json({
                    success: false,
                    message: assignmentResult?.message || "Failed to book appointment. No technician available for the selected slot."
                });
            }

            const appointmentLocation = typeof address === 'string' ? address : (address?.addressLine || address?.formattedAddress || address?.address || '');

            await requestRef.update({
                appointmentID: assignmentResult.appointmentID,
                appointmentDate,
                appointmentTime,
                addressID: addressID || (address && address.addressID) || null,
                appointmentLocation: appointmentLocation || '',
                inspectionAddress: appointmentLocation || '',
                inspectionMethod: method || "On-Site Inspection",
                bookingStatus: "Confirmed",
                requestStatus: "Scheduled",
                status: "Scheduled",
                scheduledAt: new Date(),
                onHoldReason: FieldValue.delete(),
                onHoldAt: FieldValue.delete(),
                holdReason: FieldValue.delete(),
                reassignedAt: FieldValue.delete(),
                updatedAt: new Date()
            }).catch(() => {});

            if (docData && docData.deviceID) {
                await db.collection("devices").doc(docData.deviceID).update({
                    status: "scheduled",
                    deviceStatus: "scheduled",
                    updatedAt: new Date()
                }).catch(() => {});
            }

            return res.status(200).json({
                success: true,
                tradeInRequestID: cleanId,
                appointmentID: assignmentResult.appointmentID,
                taskID: assignmentResult.taskID,
                scheduleID: assignmentResult.scheduleID,
                staffID: assignmentResult.staffID,
                staffName: assignmentResult.staffName,
                message: assignmentResult.message || "Appointment successfully booked and assigned."
            });
        }

        return res.status(200).json({ success: true, message: "Appointment booked." });
    } catch (err) {
        console.error("book-appointment error:", err);
        return res.status(500).json({ success: false, message: err.message });
    }
});

// GET /check-available-slots - Check if all staff have tasks on target slot; if so, disable slot
router.get("/check-available-slots", async (req, res) => {
    try {
        const { method, date } = req.query;
        if (!date) {
            return res.status(400).json({ success: false, message: "Date query param is required." });
        }
        const availability = await checkSlotAvailabilityForDate({
            method: method || "On-Site Inspection",
            dateStr: date
        });
        return res.status(200).json({
            success: true,
            ...availability
        });
    } catch (err) {
        console.error("check-available-slots error:", err);
        return res.status(500).json({ success: false, message: err.message, disabledSlots: [], availableSlots: [] });
    }
});

// GET /check-month-availability - Get dates with 0 available slots in a month
router.get("/check-month-availability", async (req, res) => {
    try {
        const { method, month } = req.query;
        const availability = await checkMonthAvailabilityForTradeIn({
            method: method || "On-Site Inspection",
            monthStr: month
        });
        return res.status(200).json(availability);
    } catch (err) {
        console.error("check-month-availability error:", err);
        return res.status(500).json({ success: false, message: err.message, disabledDates: [] });
    }
});

// GET /active-submitted - Search for trade in request with 'Submitted' or 'Evaluated' status for active activity
router.get("/active-submitted", async (req, res) => {
    try {
        const { userEmail } = req.query;
        if (!userEmail || !db) {
            return res.status(200).json({ success: true, submittedRequest: null });
        }

        const snapshot = await db.collection("tradeInRequests")
            .where("userEmail", "==", userEmail)
            .where("requestStatus", "in", ["Submitted", "Evaluated", "Quoted"])
            .limit(20)
            .get();

        if (snapshot.empty) {
            return res.status(200).json({ success: true, submittedRequest: null });
        }

        // Filter for active statuses: 'Submitted', 'Evaluated', or 'Quoted'
        const validDocs = snapshot.docs.map(d => d.data());

        if (validDocs.length === 0) {
            return res.status(200).json({ success: true, submittedRequest: null });
        }

        // Sort descending by submittedAt or createdAt in memory if multiple
        const toMs = (ts) => {
            if (!ts) return 0;
            if (ts.toDate && typeof ts.toDate === "function") return ts.toDate().getTime();
            if (ts._seconds) return ts._seconds * 1000 + (ts._nanoseconds || 0) / 1e6;
            if (typeof ts === "string" || typeof ts === "number") return new Date(ts).getTime() || 0;
            if (ts instanceof Date) return ts.getTime();
            return 0;
        };

        validDocs.sort((a, b) => {
            const timeA = toMs(a.submittedAt) || toMs(a.createdAt);
            const timeB = toMs(b.submittedAt) || toMs(b.createdAt);
            return timeB - timeA;
        });

        const reqData = validDocs[0];
        let deviceData = null;
        if (reqData && reqData.deviceID) {
            const devDoc = await db.collection("devices").doc(reqData.deviceID).get();
            if (devDoc.exists) {
                deviceData = devDoc.data();
            }
        }

        return res.status(200).json({
            success: true,
            submittedRequest: reqData,
            device: deviceData
        });
    } catch (err) {
        console.error("active-submitted error:", err);
        return res.status(500).json({ success: false, message: err.message });
    }
});

// GET /user-requests - Fetch trade-in requests for a user with optional tab filtering and pagination
router.get("/user-requests", async (req, res) => {
    try {
        await autoResolveOverdueTradeInTasks().catch(() => {});
        const { userEmail, tab, status, page, limit } = req.query;
        let targetEmail = (userEmail || '').trim();

        if (!db) {
            return res.status(200).json({ success: true, requests: [], pagination: { page: 1, limit: 10, total: 0, hasMore: false } });
        }

        let snapshot;
        if (targetEmail && targetEmail !== 'customer@rebyte.com') {
            snapshot = await db.collection("tradeInRequests")
                .where("userEmail", "==", targetEmail)
                .get();
        }

        // If no records found and email was placeholder or empty, fallback to primary user with trade-in records
        if (!snapshot || snapshot.empty) {
            if (!targetEmail || targetEmail === 'customer@rebyte.com') {
                const fallbackSnap = await db.collection("tradeInRequests")
                    .where("userEmail", "==", "lolincoln021@gmail.com")
                    .get();
                if (!fallbackSnap.empty) {
                    snapshot = fallbackSnap;
                }
            }
        }

        if (!snapshot || snapshot.empty) {
            return res.status(200).json({
                success: true,
                requests: [],
                pagination: { page: 1, limit: 10, total: 0, hasMore: false },
                counts: { active: 0, in_progress: 0, completed: 0, cancelled: 0, activeFilters: { all: 0, confirmed: 0, evaluated: 0, quoted: 0, agreed: 0, accepted: 0 } }
            });
        }

        const toMs = (ts) => {
            if (!ts) return 0;
            if (ts.toDate && typeof ts.toDate === "function") return ts.toDate().getTime();
            if (ts._seconds) return ts._seconds * 1000 + (ts._nanoseconds || 0) / 1e6;
            if (typeof ts === "string" || typeof ts === "number") return new Date(ts).getTime() || 0;
            if (ts instanceof Date) return ts.getTime();
            return 0;
        };

        const isCompletedDoc = (d) => {
            const s = (d.requestStatus || '').toString().toLowerCase().trim();
            const b = (d.bookingStatus || '').toString().toLowerCase().trim();
            const st = (d.status || '').toString().toLowerCase().trim();
            return s === 'completed' || s === 'complete' || s === 'paid' || b === 'completed' || st === 'accepted' || st === 'completed' || st === 'paid' || d.isPaid === true;
        };

        const isCancelledDoc = (d) => {
            const s = (d.requestStatus || '').toString().toLowerCase().trim();
            const st = (d.status || '').toString().toLowerCase().trim();
            return s === 'cancelled' || s === 'canceled' || s === 'rejected' || s === 'declined' || st === 'declined' || st === 'rejected';
        };

        const isInProgressDoc = (d) => {
            if (isCompletedDoc(d) || isCancelledDoc(d)) return false;
            const s = (d.requestStatus || '').toString().toLowerCase().trim();
            const b = (d.bookingStatus || '').toString().toLowerCase().trim();
            return s === 'inspecting' ||
                s.includes('inspect') ||
                s === 'scheduled' ||
                s.includes('schedul') ||
                s === 'in progress' ||
                s === 'on progress' ||
                s === 'on hold' ||
                s.includes('hold') ||
                b === 'inspecting' ||
                b === 'confirmed' ||
                b === 'on hold' ||
                d.appointmentDate != null ||
                d.appointmentID != null;
        };

        const isActiveDoc = (d) => {
            return !isCompletedDoc(d) && !isCancelledDoc(d) && !isInProgressDoc(d);
        };

        // Compute global tab counts across all user documents
        let activeCount = 0;
        let inProgressCount = 0;
        let completedCount = 0;
        let cancelledCount = 0;
        let confCount = 0;
        let evalCount = 0;
        let quoteCount = 0;
        let agreedCount = 0;

        snapshot.docs.forEach((doc) => {
            const d = doc.data();
            if (isCompletedDoc(d)) {
                completedCount++;
            } else if (isCancelledDoc(d)) {
                cancelledCount++;
            } else if (isInProgressDoc(d)) {
                inProgressCount++;
            } else {
                activeCount++;
                const s = (d.requestStatus || '').toString().toLowerCase();
                const st = (d.status || '').toString().toLowerCase();
                if (s.includes('submit') || s.includes('transit') || s === 'confirmed') confCount++;
                if (s.includes('evaluat')) evalCount++;
                if (s.includes('quote')) quoteCount++;
                if (s.includes('agree') || s.includes('accept') || st === 'agreed' || st === 'accepted') agreedCount++;
            }
        });

        // Filter documents matching the requested tab & status
        const requestedTab = (tab || 'all').toLowerCase().trim();
        const requestedStatus = (status || 'all').toLowerCase().trim();

        let filteredDocs = snapshot.docs.filter((doc) => {
            const d = doc.data();
            if (requestedTab === 'active') {
                if (!isActiveDoc(d)) return false;
                if (requestedStatus && requestedStatus !== 'all') {
                    const s = (d.requestStatus || '').toString().toLowerCase();
                    const st = (d.status || '').toString().toLowerCase();
                    if (requestedStatus === 'confirmed' || requestedStatus === 'submitted') {
                        return s.includes('submit') || s.includes('transit') || s === 'confirmed';
                    } else if (requestedStatus === 'evaluated') {
                        return s.includes('evaluat');
                    } else if (requestedStatus === 'quoted') {
                        return s.includes('quote');
                    } else if (requestedStatus === 'agreed' || requestedStatus === 'accepted') {
                        return s.includes('agree') || s.includes('accept') || st === 'agreed' || st === 'accepted';
                    }
                }
                return true;
            } else if (requestedTab === 'in_progress') {
                return isInProgressDoc(d);
            } else if (requestedTab === 'completed') {
                return isCompletedDoc(d);
            } else if (requestedTab === 'cancelled') {
                return isCancelledDoc(d);
            }
            return true;
        });

        // Sort filtered parent docs by submittedAt descending
        filteredDocs.sort((a, b) => {
            const timeA = toMs(a.data().submittedAt || a.data().createdAt);
            const timeB = toMs(b.data().submittedAt || b.data().createdAt);
            return timeB - timeA;
        });

        const totalFiltered = filteredDocs.length;
        let pagedDocs = filteredDocs;
        let hasMore = false;
        let pageInt = 1;
        let limitInt = totalFiltered || 10;

        if (page != null || limit != null) {
            pageInt = Math.max(1, parseInt(page, 10) || 1);
            limitInt = Math.max(1, parseInt(limit, 10) || 10);
            const startIndex = (pageInt - 1) * limitInt;
            pagedDocs = filteredDocs.slice(startIndex, startIndex + limitInt);
            hasMore = (startIndex + limitInt) < totalFiltered;
        }

        // Enrich ONLY the sliced page documents
        const requests = await Promise.all(pagedDocs.map(async (doc) => {
            const data = doc.data();
            const reqID = data.tradeInRequestID || doc.id;
            const cleanReqId = reqID.replace(/^#/, '');

            // Parallel fetch for device, images, and appointment
            const devicePromise = data.deviceID
                ? db.collection("devices").doc(data.deviceID).get().catch(() => null)
                : Promise.resolve(null);

            const imagesPromise = doc.ref.collection("images").get().catch(() => null);

            const appointmentPromise = (async () => {
                try {
                    let appDoc = null;
                    if (data.appointmentID) {
                        const aSnap = await db.collection("tradeInAppointment").doc(data.appointmentID).get();
                        if (aSnap.exists) appDoc = aSnap;
                    }
                    if (!appDoc && data.requestStatus !== 'Cancelled' && data.requestStatus !== 'Rejected') {
                        const candidateIds = Array.from(new Set([reqID, cleanReqId, `#${cleanReqId}`, doc.id]));
                        const snap = await db.collection("tradeInAppointment")
                            .where("tradeInRequestID", "in", candidateIds.slice(0, 10))
                            .limit(1)
                            .get();
                        if (!snap.empty) {
                            appDoc = snap.docs[0];
                        }
                    }
                    return appDoc;
                } catch (_) {
                    return null;
                }
            })();

            const [devDoc, imgSnap, appDoc] = await Promise.all([
                devicePromise,
                imagesPromise,
                appointmentPromise
            ]);

            const deviceData = devDoc && devDoc.exists ? devDoc.data() : null;

            let firstImageUrl = null;
            const deviceImages = [];
            const deviceImagesDetailed = [];
            if (imgSnap && !imgSnap.empty) {
                imgSnap.docs.forEach(iDoc => {
                    const iData = iDoc.data();
                    if (iData && iData.imageUrl) {
                        deviceImages.push(iData.imageUrl);
                        deviceImagesDetailed.push({
                            imageID: iDoc.id,
                            imageUrl: iData.imageUrl,
                            imageView: iData.imageView || 'device'
                        });
                    }
                });
                if (deviceImages.length > 0) {
                    firstImageUrl = deviceImages[0];
                }
            }

            let appointmentID = data.appointmentID || null;
            let appointmentDate = data.appointmentDate || null;
            let appointmentTime = data.appointmentTime || null;
            let appointmentLocation = null;
            let inspectionMethod = data.inspectionMethod || null;
            let bookingStatus = data.bookingStatus || null;

            if (appDoc) {
                const app = appDoc.data();
                appointmentID = app.appointmentID || appDoc.id;
                const isCancelledAppt = app.appointmentStatus === "Cancelled" || app.bookingStatus === "Cancelled" || app.status === "Cancelled";
                const isOnHold = !isCancelledAppt && (app.appointmentStatus === "On Hold" || data.requestStatus === "On Hold" || app.bookingStatus === "On Hold");
                const isInProgress = !isCancelledAppt && !isOnHold && (app.appointmentStatus === "In Progress" || data.requestStatus === "In Progress" || app.bookingStatus === "In Progress");
                bookingStatus = isCancelledAppt ? "Cancelled" : (isOnHold ? "On Hold" : (isInProgress ? "In Progress" : (bookingStatus || "Confirmed")));

                if (isCancelledAppt) {
                    data.requestStatus = "Cancelled";
                    data.status = "Cancelled";
                    if (doc.data().requestStatus !== "Cancelled") {
                        doc.ref.update({ requestStatus: "Cancelled", status: "Cancelled", bookingStatus: "Cancelled", cancelledAt: new Date() }).catch(() => {});
                    }
                } else if (isOnHold && data.requestStatus !== "Cancelled") {
                    data.requestStatus = "On Hold";
                    if (doc.data().requestStatus !== "On Hold") {
                        doc.ref.update({ requestStatus: "On Hold", bookingStatus: "On Hold" }).catch(() => {});
                    }
                } else if (isInProgress && !isOnHold && data.requestStatus !== "Cancelled" && data.requestStatus !== "Completed" && data.requestStatus !== "Inspected" && data.requestStatus !== "Collected") {
                    data.requestStatus = "In Progress";
                    if (doc.data().requestStatus !== "In Progress") {
                        doc.ref.update({ requestStatus: "In Progress", bookingStatus: "In Progress" }).catch(() => {});
                    }
                }
                inspectionMethod = inspectionMethod || app.appointmentType || "On-Site Inspection";
                if (!appointmentDate && app.scheduledAt) {
                    const dateObj = app.scheduledAt.toDate ? app.scheduledAt.toDate() : new Date(app.scheduledAt);
                    appointmentDate = dateObj.toISOString().split("T")[0];
                    const hh = String(dateObj.getHours()).padStart(2, "0");
                    const mm = String(dateObj.getMinutes()).padStart(2, "0");
                    appointmentTime = `${hh}:${mm}`;
                }
                const effAddressID = app.addressID || data.addressID;
                if (effAddressID) {
                    try {
                        const aDoc = await db.collection("address").doc(effAddressID).get();
                        if (aDoc.exists) {
                            const aData = aDoc.data();
                            appointmentLocation = [aData.addressLine, aData.postcode, aData.city, aData.state]
                                .filter(Boolean)
                                .join(", ");
                        }
                    } catch (_) {}
                }
            }

            if (!appointmentLocation) {
                if (typeof data.address === 'string' && data.address.trim()) {
                    appointmentLocation = data.address.trim();
                } else if (data.address && typeof data.address === 'object') {
                    appointmentLocation = [data.address.addressLine, data.address.postcode, data.address.city, data.address.state]
                        .filter(Boolean)
                        .join(", ");
                }
            }

            return {
                tradeInRequestID: data.tradeInRequestID || doc.id,
                status: data.status || data.requestStatus || 'Submitted',
                requestStatus: data.requestStatus || 'Submitted',
                bookingStatus,
                appointmentStatus: appDoc ? (appDoc.data().appointmentStatus || null) : null,
                appointmentID,
                appointmentDate,
                appointmentTime,
                appointmentLocation,
                inspectionMethod,
                submittedAt: data.submittedAt || data.createdAt || null,
                deviceID: data.deviceID,
                device: deviceData,
                deviceImage: firstImageUrl,
                deviceImages,
                deviceImagesDetailed,
                estimatedValue: data.estimatedValue ? parseEstimatedValueObject(data.estimatedValue) : null,
                finalQuotation: data.finalQuotation || null,
                finalOfferPrice: data.finalQuotation?.finalOfferPrice || data.finalOfferPrice || null,
                offeredPrice: data.offeredPrice || null,
                isPaid: Boolean(data.isPaid),
                paidAt: data.paidAt || null,
                transactionID: data.transactionID || null,
                inspectedAt: data.inspectedAt || null,
                declinedAt: data.declinedAt || data.rejectedAt || data.updatedAt || null,
                rejectedAt: data.rejectedAt || data.declinedAt || data.updatedAt || null,
                acceptedAt: data.acceptedAt || data.updatedAt || null,
                updatedAt: data.updatedAt || null,
            };
        }));

        return res.status(200).json({
            success: true,
            requests,
            pagination: {
                page: pageInt,
                limit: limitInt,
                total: totalFiltered,
                hasMore
            },
            counts: {
                active: activeCount,
                in_progress: inProgressCount,
                completed: completedCount,
                cancelled: cancelledCount,
                activeFilters: {
                    all: activeCount,
                    confirmed: confCount,
                    evaluated: evalCount,
                    quoted: quoteCount,
                    agreed: agreedCount,
                    accepted: agreedCount
                }
            }
        });
    } catch (err) {
        console.error("user-requests error:", err);
        return res.status(500).json({ success: false, message: err.message });
    }
});

// GET /request-details - Fetch a single trade-in request with all uploaded images and appointment info
router.get("/request-details", async (req, res) => {
    try {
        await autoResolveOverdueTradeInTasks().catch(() => {});
        const { tradeInRequestID } = req.query;
        if (!tradeInRequestID || !db) {
            return res.status(400).json({ success: false, message: "Missing tradeInRequestID" });
        }

        const cleanId = tradeInRequestID.replace(/^#/, '');
        const docRef = db.collection("tradeInRequests").doc(cleanId);
        const doc = await docRef.get();
        if (!doc.exists) {
            return res.status(404).json({ success: false, message: "Trade-in request not found" });
        }

        const data = doc.data();
        let deviceData = null;
        if (data.deviceID) {
            const devDoc = await db.collection("devices").doc(data.deviceID).get();
            if (devDoc.exists) {
                deviceData = devDoc.data();
            }
        }

        let firstImageUrl = null;
        let deviceImages = [];
        let deviceImagesDetailed = [];
        try {
            const imgSnap = await docRef.collection("images").get();
            if (!imgSnap.empty) {
                imgSnap.docs.forEach(iDoc => {
                    const iData = iDoc.data();
                    if (iData && iData.imageUrl) {
                        deviceImages.push(iData.imageUrl);
                        deviceImagesDetailed.push({
                            imageID: iDoc.id,
                            imageUrl: iData.imageUrl,
                            imageView: iData.imageView || 'device'
                        });
                    }
                });
                if (deviceImages.length > 0) {
                    firstImageUrl = deviceImages[0];
                }
            }
        } catch (_) {}

        let appointmentID = data.appointmentID || null;
        let appointmentDate = data.appointmentDate || null;
        let appointmentTime = data.appointmentTime || null;
        let appointmentLocation = null;
        let inspectionMethod = data.inspectionMethod || null;
        let bookingStatus = data.bookingStatus || null;
        let appDoc = null;

        try {

            if (appointmentID) {
                const aSnap = await db.collection("tradeInAppointment").doc(appointmentID).get();
                if (aSnap.exists) {
                    appDoc = aSnap;
                }
            }

            if (!appDoc) {
                for (const candidateId of [cleanId, `#${cleanId}`, doc.id, data.tradeInRequestID].filter(Boolean)) {
                    const snap = await db.collection("tradeInAppointment")
                        .where("tradeInRequestID", "==", candidateId)
                        .limit(1)
                        .get();
                    if (!snap.empty) {
                        appDoc = snap.docs[0];
                        break;
                    }
                }
            }

            if (appDoc) {
                const app = appDoc.data();
                appointmentID = app.appointmentID || appDoc.id;
                const isCancelledAppt = app.appointmentStatus === "Cancelled" || app.bookingStatus === "Cancelled" || app.status === "Cancelled";
                const isOnHold = !isCancelledAppt && (app.appointmentStatus === "On Hold" || data.requestStatus === "On Hold" || app.bookingStatus === "On Hold");
                const isInProgress = !isCancelledAppt && !isOnHold && (app.appointmentStatus === "In Progress" || data.requestStatus === "In Progress" || app.bookingStatus === "In Progress");
                bookingStatus = isCancelledAppt ? "Cancelled" : (isOnHold ? "On Hold" : (isInProgress ? "In Progress" : (bookingStatus || "Confirmed")));

                if (isCancelledAppt) {
                    data.requestStatus = "Cancelled";
                    data.status = "Cancelled";
                    if (doc.data().requestStatus !== "Cancelled") {
                        docRef.update({ requestStatus: "Cancelled", status: "Cancelled", bookingStatus: "Cancelled", cancelledAt: new Date() }).catch(() => {});
                    }
                } else if (isOnHold && data.requestStatus !== "Cancelled") {
                    data.requestStatus = "On Hold";
                    if (doc.data().requestStatus !== "On Hold") {
                        docRef.update({ requestStatus: "On Hold", bookingStatus: "On Hold" }).catch(() => {});
                    }
                } else if (isInProgress && !isOnHold && data.requestStatus !== "Cancelled" && data.requestStatus !== "Completed" && data.requestStatus !== "Inspected" && data.requestStatus !== "Collected") {
                    data.requestStatus = "In Progress";
                    if (doc.data().requestStatus !== "In Progress") {
                        docRef.update({ requestStatus: "In Progress", bookingStatus: "In Progress" }).catch(() => {});
                    }
                }
                inspectionMethod = inspectionMethod || app.appointmentType || "On-Site Inspection";
                if (!appointmentDate && app.scheduledAt) {
                    const dateObj = app.scheduledAt.toDate ? app.scheduledAt.toDate() : new Date(app.scheduledAt);
                    appointmentDate = dateObj.toISOString().split("T")[0];
                    const hh = String(dateObj.getHours()).padStart(2, "0");
                    const mm = String(dateObj.getMinutes()).padStart(2, "0");
                    appointmentTime = `${hh}:${mm}`;
                }
                const effAddressID = app.addressID || data.addressID;
                if (effAddressID) {
                    const aDoc = await db.collection("address").doc(effAddressID).get();
                    if (aDoc.exists) {
                        const aData = aDoc.data();
                        appointmentLocation = [aData.addressLine, aData.postcode, aData.city, aData.state]
                            .filter(Boolean)
                            .join(", ");
                    }
                }
            }
        } catch (_) {}

        if (!appointmentLocation) {
            if (typeof data.address === 'string' && data.address.trim()) {
                appointmentLocation = data.address.trim();
            } else if (data.address && typeof data.address === 'object') {
                appointmentLocation = [data.address.addressLine, data.address.postcode, data.address.city, data.address.state]
                    .filter(Boolean)
                    .join(", ");
            }
        }

        const requestDetails = {
            tradeInRequestID: data.tradeInRequestID || doc.id,
            status: data.status || data.requestStatus || 'Submitted',
            requestStatus: data.requestStatus || 'Submitted',
            bookingStatus,
            appointmentStatus: appDoc ? (appDoc.data().appointmentStatus || null) : null,
            appointmentID,
            appointmentDate,
            appointmentTime,
            appointmentLocation,
            addressID: data.addressID || (appDoc ? appDoc.data().addressID : null) || null,
            inspectionMethod,
            submittedAt: data.submittedAt || data.createdAt || null,
            deviceID: data.deviceID,
            device: deviceData,
            deviceImage: firstImageUrl,
            deviceImages,
            deviceImagesDetailed,
            estimatedValue: data.estimatedValue ? parseEstimatedValueObject(data.estimatedValue) : null,
            finalQuotation: data.finalQuotation || null,
            finalOfferPrice: data.finalQuotation?.finalOfferPrice || data.finalOfferPrice || null,
            offeredPrice: data.offeredPrice || null,
            isPaid: Boolean(data.isPaid),
            paidAt: data.paidAt || null,
            transactionID: data.transactionID || null,
            inspectedAt: data.inspectedAt || null,
            declinedAt: data.declinedAt || data.rejectedAt || data.updatedAt || null,
            rejectedAt: data.rejectedAt || data.declinedAt || data.updatedAt || null,
            acceptedAt: data.acceptedAt || data.updatedAt || null,
            updatedAt: data.updatedAt || null,
        };

        return res.status(200).json({
            success: true,
            request: requestDetails
        });
    } catch (err) {
        console.error("request-details error:", err);
        return res.status(500).json({ success: false, message: err.message });
    }
});

// POST /cancel-requests - Cancel existing Pending trade-in requests for a user when starting a new flow
router.post("/cancel-requests", async (req, res) => {
    try {
        const { userEmail } = req.body;
        if (!userEmail || !db) {
            return res.status(200).json({ success: true, count: 0 });
        }

        const snapshot = await db.collection("tradeInRequests")
            .where("userEmail", "==", userEmail)
            .where("requestStatus", "in", ["Pending", "pending"])
            .get();

        let count = 0;
        for (const doc of snapshot.docs) {
            const data = doc.data();
            const status = (data.requestStatus || '').toLowerCase();
            if (status === 'pending') {
                await doc.ref.update({
                    requestStatus: 'Cancelled',
                    cancelledAt: new Date()
                }).catch(() => {});

                // Also update associated device status
                if (data.deviceID) {
                    await db.collection("devices").doc(data.deviceID).update({
                        status: 'cancelled'
                    }).catch(() => {});
                }
                count++;
            }
        }

        return res.status(200).json({ success: true, count });
    } catch (err) {
        console.error("cancel-requests error:", err);
        return res.status(500).json({ success: false, message: err.message });
    }
});

// Helper: Luhn Checksum Algorithm for IMEI
function isValidLuhnIMEI(imei) {
    if (!/^\d{15}$/.test(imei)) return false;
    let sum = 0;
    for (let i = 0; i < 15; i++) {
        let digit = parseInt(imei.charAt(i), 10);
        if (i % 2 === 1) { // Double every second digit from left (0-indexed 1, 3, 5...)
            digit *= 2;
            if (digit > 9) digit = (digit % 10) + 1;
        }
        sum += digit;
    }
    return sum % 10 === 0;
}

// Global In-Memory TAC Database loaded from MoazEb/tac-database (248,000+ entries)
const CSV_TAC_MAP = new Map();
const readline = require("readline");

function initTacDatabase() {
    const csvPath = path.join(__dirname, "tac_full.csv");
    if (!fs.existsSync(csvPath)) {
        console.warn("tac_full.csv not found at", csvPath);
        return;
    }

    const t0 = Date.now();
    const rl = readline.createInterface({
        input: fs.createReadStream(csvPath),
        crlfDelay: Infinity
    });

    rl.on("line", (line) => {
        const comma1 = line.indexOf(",");
        if (comma1 === -1) return;
        const comma2 = line.indexOf(",", comma1 + 1);
        if (comma2 === -1) return;
        const tac = line.substring(comma1 + 1, comma2).trim();
        if (tac.length === 8) {
            const rawBrand = line.substring(0, comma1).trim();
            let rawSpecs = line.substring(comma2 + 1).trim();
            if (rawSpecs.startsWith('"') && rawSpecs.endsWith('"')) {
                rawSpecs = rawSpecs.substring(1, rawSpecs.length - 1);
            }
            CSV_TAC_MAP.set(tac, { brand: rawBrand, specs: rawSpecs });
        }
    });

    rl.on("close", () => {
        console.log(`Loaded ${CSV_TAC_MAP.size} official TAC records from tac-database in ${Date.now() - t0}ms`);
    });
}

initTacDatabase();

// Device published specs database: Available storage options, official published colors, and release year
const PHONE_MODEL_SPECS_CATALOG = {
    // Apple iPhones
    "iphone 16 pro max": { storage: ["256GB", "512GB", "1TB"], colors: ["Natural Titanium", "Desert Titanium", "White Titanium", "Black Titanium"], year: 2024 },
    "iphone 16 pro": { storage: ["128GB", "256GB", "512GB", "1TB"], colors: ["Natural Titanium", "Desert Titanium", "White Titanium", "Black Titanium"], year: 2024 },
    "iphone 16": { storage: ["128GB", "256GB", "512GB"], colors: ["Black", "White", "Pink", "Teal", "Ultramarine"], year: 2024 },
    "iphone 15 pro max": { storage: ["256GB", "512GB", "1TB"], colors: ["Natural Titanium", "Blue Titanium", "White Titanium", "Black Titanium"], year: 2023 },
    "iphone 15 pro": { storage: ["128GB", "256GB", "512GB", "1TB"], colors: ["Natural Titanium", "Blue Titanium", "White Titanium", "Black Titanium"], year: 2023 },
    "iphone 15": { storage: ["128GB", "256GB", "512GB"], colors: ["Black", "Blue", "Green", "Yellow", "Pink"], year: 2023 },
    "iphone 14 pro max": { storage: ["128GB", "256GB", "512GB", "1TB"], colors: ["Space Black", "Silver", "Gold", "Deep Purple"], year: 2022 },
    "iphone 14 pro": { storage: ["128GB", "256GB", "512GB", "1TB"], colors: ["Space Black", "Silver", "Gold", "Deep Purple"], year: 2022 },
    "iphone 14": { storage: ["128GB", "256GB", "512GB"], colors: ["Midnight", "Starlight", "Blue", "Purple", "Yellow", "Red"], year: 2022 },
    "iphone 13 pro max": { storage: ["128GB", "256GB", "512GB", "1TB"], colors: ["Graphite", "Gold", "Silver", "Sierra Blue", "Alpine Green"], year: 2021 },
    "iphone 13 pro": { storage: ["128GB", "256GB", "512GB", "1TB"], colors: ["Graphite", "Gold", "Silver", "Sierra Blue", "Alpine Green"], year: 2021 },
    "iphone 13": { storage: ["128GB", "256GB", "512GB"], colors: ["Midnight", "Starlight", "Blue", "Pink", "Green", "Red"], year: 2021 },
    "iphone 13 mini": { storage: ["128GB", "256GB", "512GB"], colors: ["Midnight", "Starlight", "Blue", "Pink", "Green", "Red"], year: 2021 },
    "iphone 12 pro max": { storage: ["128GB", "256GB", "512GB"], colors: ["Graphite", "Silver", "Gold", "Pacific Blue"], year: 2020 },
    "iphone 12 pro": { storage: ["128GB", "256GB", "512GB"], colors: ["Graphite", "Silver", "Gold", "Pacific Blue"], year: 2020 },
    "iphone 12": { storage: ["64GB", "128GB", "256GB"], colors: ["Black", "White", "Red", "Green", "Blue", "Purple"], year: 2020 },
    "iphone 12 mini": { storage: ["64GB", "128GB", "256GB"], colors: ["Black", "White", "Red", "Green", "Blue", "Purple"], year: 2020 },
    "iphone 11 pro max": { storage: ["64GB", "256GB", "512GB"], colors: ["Space Gray", "Silver", "Gold", "Midnight Green"], year: 2019 },
    "iphone 11 pro": { storage: ["64GB", "256GB", "512GB"], colors: ["Space Gray", "Silver", "Gold", "Midnight Green"], year: 2019 },
    "iphone 11": { storage: ["64GB", "128GB", "256GB"], colors: ["Black", "Green", "Yellow", "Purple", "White", "Red"], year: 2019 },
    "iphone xr": { storage: ["64GB", "128GB", "256GB"], colors: ["Black", "White", "Blue", "Yellow", "Coral", "Red"], year: 2018 },
    "iphone xs max": { storage: ["64GB", "256GB", "512GB"], colors: ["Space Gray", "Silver", "Gold"], year: 2018 },
    "iphone xs": { storage: ["64GB", "256GB", "512GB"], colors: ["Space Gray", "Silver", "Gold"], year: 2018 },
    "iphone x": { storage: ["64GB", "256GB"], colors: ["Space Gray", "Silver"], year: 2017 },

    // Samsung Galaxy
    "galaxy s24 ultra": { storage: ["256GB", "512GB", "1TB"], colors: ["Titanium Black", "Titanium Gray", "Titanium Violet", "Titanium Yellow"], year: 2024 },
    "galaxy s24+": { storage: ["256GB", "512GB"], colors: ["Onyx Black", "Marble Gray", "Cobalt Violet", "Amber Yellow"], year: 2024 },
    "galaxy s24": { storage: ["128GB", "256GB"], colors: ["Onyx Black", "Marble Gray", "Cobalt Violet", "Amber Yellow"], year: 2024 },
    "galaxy s23 ultra": { storage: ["256GB", "512GB", "1TB"], colors: ["Phantom Black", "Cream", "Green", "Lavender"], year: 2023 },
    "galaxy s23+": { storage: ["256GB", "512GB"], colors: ["Phantom Black", "Cream", "Green", "Lavender"], year: 2023 },
    "galaxy s23": { storage: ["128GB", "256GB"], colors: ["Phantom Black", "Cream", "Green", "Lavender"], year: 2023 },
    "galaxy s22 ultra": { storage: ["128GB", "256GB", "512GB", "1TB"], colors: ["Phantom Black", "Phantom White", "Green", "Burgundy"], year: 2022 },
    "galaxy s22": { storage: ["128GB", "256GB"], colors: ["Phantom Black", "Phantom White", "Green", "Pink Gold"], year: 2022 },
    "galaxy z flip 6": { storage: ["256GB", "512GB"], colors: ["Blue", "Mint", "Silver Shadow", "Yellow"], year: 2024 },
    "galaxy z flip 5": { storage: ["256GB", "512GB"], colors: ["Mint", "Graphite", "Cream", "Lavender"], year: 2023 },
    "galaxy z fold 6": { storage: ["256GB", "512GB", "1TB"], colors: ["Silver Shadow", "Pink", "Navy"], year: 2024 },
    "galaxy z fold 5": { storage: ["256GB", "512GB", "1TB"], colors: ["Icy Blue", "Phantom Black", "Cream"], year: 2023 },
};

// Helper: Normalize brand names (e.g. APPLE -> Apple, Apple (iPhone) -> Apple)
function formatBrandName(b) {
    if (!b) return "";
    const lower = b.toLowerCase();
    if (lower.includes("apple") || lower.includes("iphone")) return "Apple";
    if (lower.includes("samsung")) return "Samsung";
    if (lower.includes("xiaomi") || lower.includes("redmi")) return "Xiaomi";
    if (lower.includes("poco")) return "POCO";
    if (lower.includes("huawei")) return "Huawei";
    if (lower.includes("oppo")) return "Oppo";
    if (lower.includes("vivo")) return "Vivo";
    if (lower.includes("google") || lower.includes("pixel")) return "Google";
    if (lower.includes("oneplus")) return "OnePlus";
    if (lower.includes("sony")) return "Sony";
    return b.charAt(0).toUpperCase() + b.slice(1).toLowerCase();
}

// POST /validate-imei - Validates IMEI via MoazEb/tac-database, and validates brand, modelCode, storage, color & age
router.post("/validate-imei", async (req, res) => {
    try {
        const {
            imei,
            expectedBrand,
            expectedModel,
            expectedModelCode,
            expectedStorage,
            expectedColour,
            expectedDeviceAge
        } = req.body;

        if (!imei || typeof imei !== 'string' || imei.trim().length !== 15) {
            return res.status(400).json({
                success: false,
                isValid: false,
                message: "Please enter a valid 15-digit IMEI number."
            });
        }

        const cleanImei = imei.trim();
        const isValidChecksum = isValidLuhnIMEI(cleanImei);

        // 1. If Luhn checksum fails, it is an invalid / counterfeit IMEI
        if (!isValidChecksum) {
            return res.status(200).json({
                success: false,
                isValid: false,
                imei: cleanImei,
                message: "Invalid IMEI number. Please check the number on your device by dialing *#06#."
            });
        }

        const tac = cleanImei.substring(0, 8);

        // 2. Query 248,000+ entries from MoazEb/tac-database
        const tacRecord = CSV_TAC_MAP.get(tac);

        let detectedBrand = null;
        let detectedModel = null;
        let detectedModelCode = null;
        let detectedYear = null;

        if (tacRecord) {
            detectedBrand = formatBrandName(tacRecord.brand);
            // Parse specs (e.g., "APPLE IPHONE 13 PRO, Apple iPhone 13 Pro, A2638, 2021, QC SD X60 Modem")
            const parts = tacRecord.specs.split(",").map(p => p.trim());
            detectedModel = parts[1] || parts[0] || tacRecord.specs;

            // Extract model code from TAC specs (e.g. A2638, SM-S928B, 2407FPN8EG, GKV4X)
            detectedModelCode = extractModelCodeFromSpecs(tacRecord.specs);

            // Retrieve consistent, official model name from Google Play devices list using detected modelCode
            if (detectedModelCode && detectedBrand) {
                const bLower = detectedBrand.toLowerCase().trim();
                const codeKey = bLower + ":::" + detectedModelCode.toUpperCase().replace(/[^A-Z0-9]/g, '');
                const gpNames = googlePlayBrandCodeToNames[codeKey];
                if (gpNames && gpNames.length > 0) {
                    // If multiple aliases exist, pick the best matching or primary one
                    let bestName = gpNames[0];
                    if (expectedModel) {
                        const expLower = expectedModel.toLowerCase();
                        const match = gpNames.find(n => n.toLowerCase() === expLower || expLower.includes(n.toLowerCase()));
                        if (match) bestName = match;
                    }
                    detectedModel = bestName;
                }
            }

            // Extract 4-digit release year from specs
            for (const part of parts) {
                const yearMatch = part.match(/\b(20[0-2][0-9])\b/);
                if (yearMatch) {
                    detectedYear = parseInt(yearMatch[1], 10);
                    break;
                }
            }
        }

        // If not found in 248k TAC database, it is an unrecognized device
        if (!detectedModel) {
            return res.status(200).json({
                success: true,
                isValid: true,
                imei: cleanImei,
                tac: tac,
                isMismatch: true,
                mismatchType: "modelCode",
                expectedModel: expectedModel || "Phone",
                expectedModelCode: expectedModelCode || null,
                detectedModel: "Unrecognized Device",
                detectedModelCode: "Unknown Code",
                detectedBrand: "Unknown Brand",
                mismatchReason: "The scanned IMEI could not be identified in the global TAC registry."
            });
        }

        // 3. Multi-Attribute Verification Logic:
        const currentYear = new Date().getFullYear();
        let isMismatch = false;
        let mismatchType = null;
        let mismatchReason = null;
        let mismatchExpected = null;
        let mismatchDetected = null;

        const expBrandClean = formatBrandName(expectedBrand);
        const detBrandClean = formatBrandName(detectedBrand);

        // A. Check Brand Mismatch
        if (expBrandClean && detBrandClean && expBrandClean !== detBrandClean) {
            isMismatch = true;
            mismatchType = "brand";
            mismatchExpected = expBrandClean;
            mismatchDetected = detBrandClean;
            mismatchReason = `Brand mismatch: Quoted ${expBrandClean}, but scanned IMEI is ${detBrandClean}.`;
        }

        // B. Check Model Code Mismatch (Strictly match by modelCode, NEVER by model name)
        // Resolve target model code from expectedModelCode or fallback lookup of expectedModel
        const targetModelCode = (expectedModelCode && String(expectedModelCode).trim().length > 0)
            ? String(expectedModelCode).trim()
            : getModelCodeForModel(expectedBrand, expectedModel);

        if (!isMismatch && targetModelCode && detectedModelCode) {
            const matchesCode = isModelCodeMatch(detectedModelCode, targetModelCode);
            if (!matchesCode) {
                isMismatch = true;
                mismatchType = "modelCode";
                mismatchExpected = targetModelCode;
                const expName = expectedModel || "Quoted Model";
                const detName = detectedModel || "Scanned Device";
                mismatchReason = `Model mismatch: Quoted model is "${expName}", but scanned IMEI belongs to "${detName}".`;
            }
        }

        // Look up published specifications for detected model
        const modelCatalogKey = (expectedModel || detectedModel).toLowerCase().trim();
        let matchedCatalog = PHONE_MODEL_SPECS_CATALOG[modelCatalogKey];
        if (!matchedCatalog) {
            for (const [key, val] of Object.entries(PHONE_MODEL_SPECS_CATALOG)) {
                const normKey = key.replace(/[^a-z0-9]/g, '');
                const normExp = modelCatalogKey.replace(/[^a-z0-9]/g, '');
                if (normExp.includes(normKey) || normKey.includes(normExp)) {
                    matchedCatalog = val;
                    break;
                }
            }
        }

        // C. Check Storage Mismatch (Validate against model's published storage options)
        if (!isMismatch && expectedStorage && matchedCatalog && matchedCatalog.storage) {
            const expStorageNorm = expectedStorage.replace(/\s+/g, '').toUpperCase();
            const allowedStorages = matchedCatalog.storage.map(s => s.replace(/\s+/g, '').toUpperCase());

            if (!allowedStorages.includes(expStorageNorm)) {
                isMismatch = true;
                mismatchType = "storage";
                mismatchExpected = expectedStorage;
                mismatchDetected = allowedStorages.join(", ");
                mismatchReason = `The model ${detectedModel} is not published with ${expectedStorage} storage. Available options: ${allowedStorages.join(", ")}.`;
            }
        }

        // D. Check Color Mismatch (Validate against model's published color palette)
        if (!isMismatch && expectedColour && matchedCatalog && matchedCatalog.colors && expectedColour !== 'Other Color') {
            const expColorLower = expectedColour.toLowerCase();
            const colorMatched = matchedCatalog.colors.some(c => {
                const cLower = c.toLowerCase();
                return expColorLower.includes(cLower) || cLower.includes(expColorLower);
            });

            if (!colorMatched) {
                isMismatch = true;
                mismatchType = "color";
                mismatchExpected = expectedColour;
                mismatchDetected = matchedCatalog.colors.join(", ");
                mismatchReason = `The color "${expectedColour}" is not a published color for ${detectedModel}. Published colors: ${matchedCatalog.colors.join(", ")}.`;
            }
        }

        // E. Check Device Age Mismatch (Cannot exceed currentYear - releaseYear)
        const releaseYear = detectedYear || (matchedCatalog ? matchedCatalog.year : null);
        if (!isMismatch && expectedDeviceAge && releaseYear) {
            // Parse age number (e.g. "2 year(s)" -> 2, "< 1 year" -> 0)
            const ageMatch = expectedDeviceAge.toString().match(/\d+/);
            const quotedAge = ageMatch ? parseInt(ageMatch[0], 10) : 0;
            const maxPossibleAge = Math.max(0, currentYear - releaseYear);

            if (quotedAge > maxPossibleAge + 1) { // Allowing +1 year grace for model pre-orders
                isMismatch = true;
                mismatchType = "age";
                mismatchExpected = `${quotedAge} year(s)`;
                mismatchDetected = `Max ${maxPossibleAge} year(s) (Released in ${releaseYear})`;
                mismatchReason = `This device was released in ${releaseYear}. Its age cannot exceed ${maxPossibleAge} year(s).`;
            }
        }

        return res.status(200).json({
            success: true,
            isValid: true,
            imei: cleanImei,
            tac: tac,
            isMismatch: isMismatch,
            mismatchType: mismatchType,
            mismatchReason: mismatchReason,
            expectedModel: expectedModel || detectedModel,
            expectedModelCode: targetModelCode,
            detectedModel: detectedModel,
            detectedModelCode: detectedModelCode,
            detectedBrand: detectedBrand,
            expectedStorage: expectedStorage,
            mismatchExpected: mismatchExpected,
            mismatchDetected: mismatchDetected,
            status: "Clean"
        });
    } catch (err) {
        console.error("validate-imei error:", err);
        return res.status(500).json({ success: false, message: err.message });
    }
});

// POST /detect-phone - Page 3 instant verification: Runs model1_phone_detection on the image
const { execFile } = require("child_process");

router.post("/detect-phone", upload.single("image"), async (req, res) => {
    let tempFilePath = null;
    try {
        if (!req.file) {
            return res.status(400).json({ success: false, isPhone: false, message: "No image file provided." });
        }

        // Save buffer to system temporary file for python model inference
        const os = require("os");
        const ext = path.extname(req.file.originalname) || ".jpg";
        const tempName = `temp_detect_${Date.now()}_${Math.random().toString(36).substring(7)}`;
        tempFilePath = path.join(os.tmpdir(), `${tempName}${ext}`);
        fs.writeFileSync(tempFilePath, req.file.buffer);

        const detectorScript = path.resolve(__dirname, "..", "model1_phone_detection", "run_detector.py");
        // Prefer anaconda python where torch is installed
        const pythonBin = fs.existsSync("C:\\Users\\User\\anaconda3\\python.exe") 
            ? "C:\\Users\\User\\anaconda3\\python.exe" 
            : "python";

        const cleanupTemp = () => {
            if (tempFilePath && fs.existsSync(tempFilePath)) {
                try { fs.unlinkSync(tempFilePath); } catch (_) {}
            }
            const possiblePred = path.join(os.tmpdir(), `${tempName}_prediction.jpg`);
            if (fs.existsSync(possiblePred)) {
                try { fs.unlinkSync(possiblePred); } catch (_) {}
            }
        };

        execFile(pythonBin, [detectorScript, tempFilePath], { timeout: 30000 }, (error, stdout, stderr) => {
            cleanupTemp();

            if (error) {
                console.error("Detector process error:", error, stderr);
                return res.status(500).json({
                    success: false,
                    isPhone: false,
                    error: "Detector execution error: " + (stderr || error.message)
                });
            }

            try {
                const output = JSON.parse(stdout.trim());
                return res.json(output);
            } catch (jsonErr) {
                console.error("Failed to parse detector stdout:", stdout);
                return res.status(500).json({
                    success: false,
                    isPhone: false,
                    error: "Invalid detector output format."
                });
            }
        });
    } catch (err) {
        if (tempFilePath && fs.existsSync(tempFilePath)) {
            try { fs.unlinkSync(tempFilePath); } catch (_) {}
        }
        console.error("detect-phone endpoint error:", err);
        return res.status(500).json({ success: false, isPhone: false, message: err.message });
    }
});

module.exports = router;

