const path = require('path');
const db = require('./config/firebase');

async function inspectRecords() {
    if (!db) {
        console.error('Firebase DB is not initialized');
        process.exit(1);
    }

    console.log('=== 1. TRADE IN REQUESTS ===');
    const reqsSnapshot = await db.collection('tradeInRequests').get();
    console.log(`Total tradeInRequests: ${reqsSnapshot.size}`);

    const tradeInDocs = [];
    reqsSnapshot.forEach(doc => {
        tradeInDocs.push({ id: doc.id, ...doc.data() });
    });

    console.log(JSON.stringify(tradeInDocs, null, 2));

    console.log('\n=== 2. LINKED DEVICES ===');
    const deviceIds = [...new Set(tradeInDocs.map(r => r.deviceID).filter(Boolean))];
    console.log(`Found ${deviceIds.length} unique deviceIDs:`, deviceIds);

    const devices = [];
    for (const devId of deviceIds) {
        const devDoc = await db.collection('devices').doc(devId).get();
        if (devDoc.exists) {
            devices.push({ id: devDoc.id, ...devDoc.data() });
        } else {
            console.log(`Device ID ${devId} not found in devices collection!`);
        }
    }
    console.log(JSON.stringify(devices, null, 2));

    console.log('\n=== 3. ALL DEVICES IN COLLECTION (Sample 10) ===');
    const allDevsSnap = await db.collection('devices').limit(10).get();
    console.log(`Total devices (sample 10): ${allDevsSnap.size}`);
    allDevsSnap.forEach(d => console.log(d.id, d.data().brand, d.data().model, d.data().userEmail));

    console.log('\n=== 4. LINKED USERS ===');
    const userEmails = [...new Set([
        ...tradeInDocs.map(r => r.userEmail).filter(Boolean),
        ...devices.map(d => d.userEmail).filter(Boolean)
    ])];
    console.log('Unique user emails:', userEmails);

    for (const email of userEmails) {
        const userQuery = await db.collection('users').where('email', '==', email).get();
        if (!userQuery.empty) {
            userQuery.forEach(u => {
                const uData = u.data();
                delete uData.password; // hide sensitive fields
                console.log(`User for ${email}:`, u.id, uData);
            });
        } else {
            console.log(`No user document found in 'users' collection for email: ${email}`);
        }
    }

    console.log('\n=== 5. CHECK SUBCOLLECTIONS (Images for tradeInRequests) ===');
    for (const req of tradeInDocs) {
        const imgSnap = await db.collection('tradeInRequests').doc(req.id).collection('images').get();
        console.log(`Request ${req.id} has ${imgSnap.size} images:`);
        imgSnap.forEach(i => console.log('  -', i.id, i.data()));
    }

    process.exit(0);
}

inspectRecords().catch(err => {
    console.error('Inspection failed:', err);
    process.exit(1);
});
