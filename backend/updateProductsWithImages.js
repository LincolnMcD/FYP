const path = require("path");
const db = require("./config/firebase");
const cloudinary = require("./config/cloudinary");

const samplePhoneImages = [
    {
        name: "iphone14",
        path: path.join(__dirname, "../reByteWebsite/accountManagementModule/assets/images/iphone14.jpg")
    },
    {
        name: "galaxy_s23",
        path: path.join(__dirname, "../reByteWebsite/accountManagementModule/assets/images/galaxy_s23.jpg")
    },
    {
        name: "hero_phone",
        path: path.join(__dirname, "../reByteWebsite/accountManagementModule/assets/images/hero_phone.jpg")
    }
];

async function uploadSampleImages() {
    console.log("Uploading sample phone images to Cloudinary under folder 'product'...");
    const uploadedUrls = [];

    for (const img of samplePhoneImages) {
        try {
            const res = await cloudinary.uploader.upload(img.path, {
                folder: "product",
                public_id: `sample_${img.name}`,
                overwrite: true,
                resource_type: "image"
            });
            console.log(`Uploaded ${img.name} -> ${res.secure_url}`);
            uploadedUrls.push(res.secure_url);
        } catch (err) {
            console.error(`Error uploading ${img.name}:`, err);
        }
    }

    if (uploadedUrls.length === 0) {
        throw new Error("No images were successfully uploaded to Cloudinary");
    }

    return uploadedUrls;
}

async function update20ProductsWithImageUrl() {
    const urls = await uploadSampleImages();
    console.log(`Available Cloudinary product URLs: ${urls.length}`);

    console.log("Fetching first 20 Product documents from Firestore...");
    const snap = await db.collection("Product").orderBy("productID").limit(20).get();

    if (snap.empty) {
        console.log("No Product records found!");
        return;
    }

    const batch = db.batch();
    const updated = [];

    snap.docs.forEach((doc, idx) => {
        const chosenUrl = urls[idx % urls.length];
        batch.update(doc.ref, { imageUrl: chosenUrl });
        updated.push({ id: doc.id, imageUrl: chosenUrl });
    });

    await batch.commit();
    console.log(`Successfully updated ${updated.length} Product records with imageUrl!`);
    console.log("Updated records sample:", JSON.stringify(updated.slice(0, 5), null, 2));
}

update20ProductsWithImageUrl()
    .then(() => process.exit(0))
    .catch(err => {
        console.error("Execution failed:", err);
        process.exit(1);
    });
