const db = require("./config/firebase");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");

// Helper to pad alphanumeric hex/letter format like 000A, 000B, ..., 0032
function getAlphaSuffix(num) {
    // Generate base-36 or sequential letters like 000A, 000B, etc.
    // 0 -> 000A, 1 -> 000B, ... 25 -> 000Z, 26 -> 001A, ...
    const letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    const high = Math.floor(num / 26);
    const low = num % 26;
    const prefix = String(high).padStart(3, "0");
    return `${prefix}${letters[low]}`;
}

const phoneCatalog = [
    { brand: "Apple", model: "iPhone 15 Pro Max", storage: "256 GB", basePrice: 899.00 },
    { brand: "Apple", model: "iPhone 15 Pro", storage: "128 GB", basePrice: 799.00 },
    { brand: "Apple", model: "iPhone 14 Pro Max", storage: "256 GB", basePrice: 699.00 },
    { brand: "Apple", model: "iPhone 14", storage: "128 GB", basePrice: 499.00 },
    { brand: "Apple", model: "iPhone 13", storage: "128 GB", basePrice: 399.00 },
    { brand: "Samsung", model: "Galaxy S24 Ultra", storage: "512 GB", basePrice: 949.00 },
    { brand: "Samsung", model: "Galaxy S24", storage: "256 GB", basePrice: 649.00 },
    { brand: "Samsung", model: "Galaxy S23 Ultra", storage: "256 GB", basePrice: 599.00 },
    { brand: "Samsung", model: "Galaxy S23", storage: "128 GB", basePrice: 449.00 },
    { brand: "Samsung", model: "Galaxy Z Flip 5", storage: "256 GB", basePrice: 529.00 },
    { brand: "Xiaomi", model: "Xiaomi 14 Pro", storage: "512 GB", basePrice: 619.00 },
    { brand: "Xiaomi", model: "Xiaomi 13 Ultra", storage: "512 GB", basePrice: 549.00 },
    { brand: "Xiaomi", model: "Xiaomi 13T Pro", storage: "256 GB", basePrice: 389.00 },
    { brand: "Google", model: "Pixel 8 Pro", storage: "256 GB", basePrice: 679.00 },
    { brand: "Google", model: "Pixel 7 Pro", storage: "128 GB", basePrice: 429.00 },
    { brand: "OnePlus", model: "OnePlus 12", storage: "256 GB", basePrice: 589.00 }
];

const conditions = [
    "Pristine condition, verified screen & battery health 95%+",
    "Grade A refurbished, minor micro-scratches on frame, flawless display",
    "Excellent condition, fully tested, certified OEM parts",
    "Like new with original accessories, battery health 98%",
    "Certified pre-owned, zero blemishes, 100% operational"
];

const staffList = ["S0001", "S0002", "S0004", "S0005", "S0006"];

async function createProducts() {
    console.log("Preparing to generate 50 Product records in Firebase Firestore...");
    const batchSize = 50;
    const batch = db.batch();
    const productCollection = db.collection("Product");

    // Reference dates around October 2026
    const baseDate = new Date("2026-10-15T09:00:00.000Z");

    const createdRecords = [];

    for (let i = 0; i < batchSize; i++) {
        const fakeSuffix = getAlphaSuffix(i); // '000A', '000B', ...

        // Date components: YY = 26, MM = 10, DD = 15
        const yy = "26";
        const mm = "10";
        const dd = "15";

        const productID = `${yy}${mm}${fakeSuffix}`; // e.g. 2610000A
        const createdByStaffID = staffList[i % staffList.length];
        const deviceID = `DEV-TEST${fakeSuffix}`; // DEV-TEST000A
        const tradeInRequestID = `TR${yy}${mm}${dd}${fakeSuffix}`; // TR261015000A

        const phone = phoneCatalog[i % phoneCatalog.length];
        const cond = conditions[i % conditions.length];
        const description = `${phone.brand} ${phone.model} (${phone.storage}) - ${cond}`;
        
        // sellingPrice format: (XXX.XX) e.g. 599.00 or 749.50
        const priceVariation = (i * 7.5) % 150;
        const rawPrice = (phone.basePrice + priceVariation).toFixed(2);
        const sellingPrice = parseFloat(rawPrice);

        // CreatedAt incremented across several hours/days
        const recordDate = new Date(baseDate.getTime() - (batchSize - i) * 3600 * 1000 * 3);
        const createdAt = Timestamp.fromDate(recordDate);

        const productData = {
            productID,
            description,
            sellingPrice,
            listingStatus: "listed",
            reviewStatus: "success",
            createdAt,
            createdByStaffID,
            deviceID,
            tradeInRequestID
        };

        const docRef = productCollection.doc(productID);
        batch.set(docRef, productData);
        createdRecords.push(productData);
    }

    await batch.commit();
    console.log(`Successfully created ${createdRecords.length} records under Product collection!`);
    console.log("Sample first 3 records:", JSON.stringify(createdRecords.slice(0, 3), null, 2));
    console.log("Sample last record:", JSON.stringify(createdRecords[createdRecords.length - 1], null, 2));
}

createProducts()
    .then(() => process.exit(0))
    .catch((err) => {
        console.error("Failed to seed Product collection:", err);
        process.exit(1);
    });
