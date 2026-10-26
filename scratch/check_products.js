const db = require("./backend/config/firebase");

async function checkProducts() {
  const snapshot = await db.collection("product").limit(10).get();
  console.log("Total docs fetched:", snapshot.size);
  snapshot.docs.forEach(doc => {
    console.log("ID:", doc.id, "Data:", JSON.stringify(doc.data(), null, 2));
  });
  process.exit(0);
}

checkProducts().catch(err => {
  console.error("Error:", err);
  process.exit(1);
});
