const db = require('./config/firebase');

async function getExactChains() {
    if (!db) {
        console.error('Firebase DB is not initialized');
        process.exit(1);
    }

    console.log('--- Fetching all Trade-In Requests ---');
    const reqsSnapshot = await db.collection('tradeInRequests').get();
    console.log(`Found ${reqsSnapshot.size} Trade-In Request(s) in Firestore.`);

    const nonCancelledOrUnique = [];
    reqsSnapshot.forEach(doc => {
        const data = doc.data();
        nonCancelledOrUnique.push({ id: doc.id, ...data });
    });

    // Group or display non-cancelled / key representative records
    const statuses = {};
    for (const req of nonCancelledOrUnique) {
        const s = req.requestStatus || 'Unknown';
        statuses[s] = (statuses[s] || 0) + 1;
    }
    console.log('\nStatus Distribution:', statuses);

    console.log('\n================ EXACT RECORDS: tradeInRequest -> device -> user ================');

    for (const req of nonCancelledOrUnique) {
        // Only inspect if not one of the bulk cancelled ones, or inspect first few of each status
        console.log(`\n------------------------------------------------------------`);
        console.log(`[TRADE-IN REQUEST] ID: ${req.tradeInRequestID || req.id}`);
        console.log(`  - Status: ${req.requestStatus}`);
        console.log(`  - Submitted At: ${req.submittedAt ? req.submittedAt.toDate ? req.submittedAt.toDate().toISOString() : req.submittedAt : 'N/A'}`);
        console.log(`  - Evaluated At: ${req.evaluatedAt ? req.evaluatedAt.toDate ? req.evaluatedAt.toDate().toISOString() : req.evaluatedAt : 'N/A'}`);
        console.log(`  - Completed At: ${req.completedAt ? req.completedAt.toDate ? req.completedAt.toDate().toISOString() : req.completedAt : 'N/A'}`);
        console.log(`  - Cancelled At: ${req.cancelledAt ? req.cancelledAt.toDate ? req.cancelledAt.toDate().toISOString() : req.cancelledAt : 'N/A'}`);
        console.log(`  - IMEI: ${req.imeiNum || 'N/A'}`);
        console.log(`  - Estimated Value: ${req.preliminaryValuation ? 'RM ' + req.preliminaryValuation : 'N/A'}`);
        console.log(`  - Linked DeviceID: ${req.deviceID || 'N/A'}`);
        console.log(`  - User Email: ${req.userEmail || 'N/A'}`);

        // Fetch Device
        let deviceData = null;
        if (req.deviceID) {
            const devDoc = await db.collection('devices').doc(req.deviceID).get();
            if (devDoc.exists) {
                deviceData = devDoc.data();
                console.log(`  [DEVICE] (Found: ${devDoc.id})`);
                console.log(`    * Brand: ${deviceData.brand}`);
                console.log(`    * Model: ${deviceData.model}`);
                console.log(`    * Model Code: ${deviceData.modelCode || 'N/A'}`);
                console.log(`    * Storage: ${deviceData.storageCapacity || 'N/A'}`);
                console.log(`    * Colour: ${deviceData.colour || 'N/A'}`);
                console.log(`    * Age: ${deviceData.age ? deviceData.age + ' year(s)' : 'N/A'}`);
                console.log(`    * Device Status: ${deviceData.status || 'N/A'}`);
                console.log(`    * Device Owner Email: ${deviceData.userEmail || 'N/A'}`);
            } else {
                console.log(`  [DEVICE] Doc ${req.deviceID} NOT FOUND in 'devices' collection.`);
            }
        } else {
            console.log(`  [DEVICE] No deviceID stored on request.`);
        }

        // Fetch User
        const targetEmail = req.userEmail || (deviceData ? deviceData.userEmail : null);
        if (targetEmail) {
            const userQuery = await db.collection('users').where('email', '==', targetEmail).get();
            if (!userQuery.empty) {
                const uDoc = userQuery.docs[0];
                const u = uDoc.data();
                console.log(`  [USER] (Doc ID: ${uDoc.id})`);
                console.log(`    * Full Name: ${u.fullName || (u.firstName + ' ' + u.lastName)}`);
                console.log(`    * Email: ${u.email}`);
                console.log(`    * Role: ${u.role || 'Customer'}`);
                console.log(`    * Contact Number: ${u.contactNumber || u.phoneNumber || 'N/A'}`);
            } else {
                console.log(`  [USER] No record found in 'users' collection for email ${targetEmail}`);
            }
        } else {
            console.log(`  [USER] No email available to query user.`);
        }

        // Fetch Images subcollection count
        const imgSnap = await db.collection('tradeInRequests').doc(req.id).collection('images').get();
        if (imgSnap.size > 0) {
            console.log(`  [INSPECTION IMAGES] Count: ${imgSnap.size}`);
            imgSnap.forEach(i => {
                const imgData = i.data();
                console.log(`    - Side: ${imgData.side || i.id}, URL: ${imgData.imageUrl || imgData.url}`);
            });
        }
    }

    process.exit(0);
}

getExactChains().catch(err => {
    console.error('Error fetching records:', err);
    process.exit(1);
});
