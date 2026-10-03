const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const path = require('path');

let db;

try {
    // We use path.join to robustly locate the json file from the backend root
    const serviceAccount = require(path.join(__dirname, '../serviceAccountKey.json'));

    initializeApp({
        credential: cert(serviceAccount)
    });

    db = getFirestore();
    console.log('Firebase Database connected successfully');
} catch (error) {
    console.log('Error initializing Firebase Admin SDK - make sure serviceAccountKey.json exists!');
    console.error(error);
}

module.exports = db;
