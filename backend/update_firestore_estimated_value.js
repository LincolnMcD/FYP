const { FieldValue } = require('firebase-admin/firestore');
const db = require('./config/firebase');

async function updateRecords() {
    if (!db) {
        console.error('Firebase DB not initialized');
        process.exit(1);
    }

    console.log('--- Cleaning and updating tradeInRequests in Firestore ---');
    const snap = await db.collection('tradeInRequests').get();
    console.log(`Found ${snap.size} tradeInRequests.`);

    let removedPrelimCount = 0;
    let updatedCount = 0;

    for (const doc of snap.docs) {
        const data = doc.data();
        const updates = {};

        // Remove preliminaryValuation attribute if it exists
        if (data.preliminaryValuation !== undefined) {
            updates.preliminaryValuation = FieldValue.delete();
            removedPrelimCount++;
        }

        // Specifically set float range for the key active test records
        if (doc.id === 'TR26102300001') {
            updates.estimatedValue = { min: 450.5, max: 620.0 };
            updatedCount++;
        } else if (doc.id === 'TR26102300002') {
            updates.estimatedValue = { min: 2340.5, max: 2355.3 };
            updatedCount++;
        } else if (doc.id === 'TR26102300003') {
            updates.estimatedValue = { min: 2100.0, max: 2450.5 };
            updatedCount++;
        } else if (doc.id === 'TR26101400022') {
            updates.estimatedValue = { min: 1800.5, max: 2100.0 };
            updatedCount++;
        }

        if (Object.keys(updates).length > 0) {
            await doc.ref.update(updates);
        }
    }

    console.log(`Removed preliminaryValuation attribute from ${removedPrelimCount} document(s).`);
    console.log(`Updated estimatedValue with float ranges { min, max } on ${updatedCount} document(s).`);

    // Verify key documents
    console.log('\n--- VERIFYING EXACT RECORDS ---');
    const checkIds = ['TR26102300001', 'TR26102300002', 'TR26102300003', 'TR26101400022'];
    for (const id of checkIds) {
        const d = await db.collection('tradeInRequests').doc(id).get();
        if (d.exists) {
            const val = d.data();
            console.log(`ID: ${id}`);
            console.log(`  requestStatus: ${val.requestStatus}`);
            console.log(`  estimatedValue:`, JSON.stringify(val.estimatedValue));
            console.log(`  preliminaryValuation: ${val.preliminaryValuation !== undefined ? val.preliminaryValuation : 'NONE (Deleted)'}`);
        }
    }

    process.exit(0);
}

updateRecords().catch(err => {
    console.error('Update error:', err);
    process.exit(1);
});
