const db = require('./config/firebase');

async function getDetailedRecords() {
    const tradeInSnap = await db.collection('tradeInRequests').get();
    const records = [];

    for (const doc of tradeInSnap.docs) {
        const trData = doc.data();
        // Skip bulk cancelled if there are 40+ of the same test, but keep representative ones
        records.push({ id: doc.id, ...trData });
    }

    // Sort by submittedAt desc
    const toMs = (ts) => {
        if (!ts) return 0;
        if (ts.toDate) return ts.toDate().getTime();
        if (ts._seconds) return ts._seconds * 1000;
        return new Date(ts).getTime() || 0;
    };
    records.sort((a, b) => toMs(b.submittedAt) - toMs(a.submittedAt));

    console.log(`Total Trade-In Requests: ${records.length}`);

    // Group by status
    const byStatus = {};
    for (const r of records) {
        const s = r.requestStatus || 'Unknown';
        if (!byStatus[s]) byStatus[s] = [];
        byStatus[s].push(r);
    }

    console.log('Statuses found:', Object.keys(byStatus).map(k => `${k}: ${byStatus[k].length}`));

    // For each unique status, let's print the full chain tradeInRequest -> device -> user
    for (const status of Object.keys(byStatus)) {
        console.log(`\n======================================================`);
        console.log(`STATUS: [${status}] (Showing up to 2 exact records)`);
        console.log(`======================================================`);

        const samples = byStatus[status].slice(0, 2);
        for (const sample of samples) {
            console.log(`\n>>> TRADE IN REQUEST: ${sample.tradeInRequestID || sample.id}`);
            console.log(JSON.stringify(sample, null, 2));

            if (sample.deviceID) {
                const devDoc = await db.collection('devices').doc(sample.deviceID).get();
                if (devDoc.exists) {
                    console.log(`\n  >>> LINKED DEVICE: ${sample.deviceID}`);
                    console.log(JSON.stringify(devDoc.data(), null, 2));
                } else {
                    console.log(`\n  >>> LINKED DEVICE: ${sample.deviceID} (NOT FOUND in devices collection)`);
                }
            } else {
                console.log(`\n  >>> LINKED DEVICE: None (deviceID field is missing)`);
            }

            const email = sample.userEmail;
            if (email) {
                const userQuery = await db.collection('users').where('email', '==', email).get();
                if (!userQuery.empty) {
                    const uData = userQuery.docs[0].data();
                    delete uData.password;
                    console.log(`\n  >>> LINKED USER: ${email}`);
                    console.log(JSON.stringify(uData, null, 2));
                } else {
                    console.log(`\n  >>> LINKED USER: ${email} (NOT FOUND in users collection)`);
                }
            }

            // Subcollection images
            const imgSnap = await db.collection('tradeInRequests').doc(sample.id).collection('images').get();
            console.log(`\n  >>> IMAGES SUBCOLLECTION: ${imgSnap.size} image(s)`);
            imgSnap.forEach(img => {
                console.log(`    * [${img.id}]`, JSON.stringify(img.data()));
            });
        }
    }

    process.exit(0);
}

getDetailedRecords().catch(e => {
    console.error(e);
    process.exit(1);
});
