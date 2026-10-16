const db = require("./config/firebase");
const { FieldValue, Timestamp } = require("firebase-admin/firestore");
const { v4: uuidv4 } = require("uuid");

async function migrateProductCollection() {
    console.log("Starting migration from 'Product' to 'product' with subcollection 'image'...");

    const oldProductSnap = await db.collection("Product").get();
    console.log(`Found ${oldProductSnap.size} documents in 'Product' collection.`);

    if (oldProductSnap.empty) {
        console.log("No documents found in 'Product'. Checking 'product' collection...");
        const existingNewSnap = await db.collection("product").get();
        console.log(`Existing in 'product': ${existingNewSnap.size}`);
        return;
    }

    let processedCount = 0;
    let imageSubcolCount = 0;

    for (const oldDoc of oldProductSnap.docs) {
        const data = oldDoc.data();
        const docId = oldDoc.id;
        const targetDocRef = db.collection("product").doc(docId);

        // Extract imageUrl if present
        const imageUrl = data.imageUrl;

        // Copy product fields to new document
        // We can keep or clean up imageUrl on root doc, but let's keep all product fields
        const newProductData = { ...data };

        // Write to `product` collection
        await targetDocRef.set(newProductData);

        // If this record has imageUrl (the 20 records), create a record in the subcollection `image`
        if (imageUrl) {
            // e.g. IMG-PROD-XXXXXXXX or IMG-XXXXXXXX
            const imageID = `IMG-${uuidv4().substring(0, 8).toUpperCase()}`;
            const uploadedAt = data.createdAt || FieldValue.serverTimestamp();

            const imageData = {
                imageID: imageID,
                imageUrl: imageUrl,
                uploadedAt: uploadedAt,
                productID: data.productID || docId
            };

            await targetDocRef.collection("image").doc(imageID).set(imageData);
            imageSubcolCount++;
        }

        // Delete old document from 'Product'
        await oldDoc.ref.delete();

        processedCount++;
    }

    console.log(`Migration finished!`);
    console.log(`- Migrated ${processedCount} products to collection 'product'.`);
    console.log(`- Created ${imageSubcolCount} subcollection 'image' documents.`);
    console.log(`- Deleted old documents from 'Product'.`);
}

migrateProductCollection()
    .then(() => process.exit(0))
    .catch(err => {
        console.error("Migration error:", err);
        process.exit(1);
    });
