const db = require('../backend/config/firebase');

async function run() {
  const snap = await db.collection('devices').get();
  console.log('Total devices:', snap.size);
  snap.forEach(doc => {
    const d = doc.data();
    if ((d.brand && d.brand.toLowerCase().includes('oneplus')) ||
        (d.model && d.model.toLowerCase().includes('oneplus')) ||
        (d.model && d.model.toLowerCase().includes('12'))) {
      console.log(`Device ID: ${doc.id}, Brand: ${d.brand}, Model: ${d.model}, IMEI: ${d.imeiNum}`);
    }
  });

  const pSnap = await db.collection('product').get();
  console.log('\nTotal products:', pSnap.size);
  pSnap.forEach(doc => {
    const p = doc.data();
    console.log(`Product ID: ${doc.id}, deviceID: ${p.deviceID}, description: ${p.description ? p.description.substring(0, 40) : 'null'}`);
  });
}

run().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
