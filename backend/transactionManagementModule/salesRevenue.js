const { Timestamp } = require("firebase-admin/firestore");

function malaysiaMonthBoundary(year, monthIndex) {
    return new Date(Date.UTC(year, monthIndex, 1) - 8 * 60 * 60 * 1000);
}

function timestampMillis(value) {
    if (!value) return 0;
    if (typeof value.toDate === "function") return value.toDate().getTime() || 0;
    if (typeof value._seconds === "number") return value._seconds * 1000;
    const time = new Date(value).getTime();
    return Number.isFinite(time) ? time : 0;
}

function transactionCategory(data) {
    const type = String(data.transactionType || "").toLowerCase().trim();
    if (["payout", "trade-in", "tradein"].includes(type)) return "trade-in";
    if (type.includes("deposit")) return "deposit";
    if (type.includes("refund")) return "refund";
    if (type.includes("rental")) return "rental";
    if (type === "purchase" || data.orderID) return "purchase";
    if (data.rentalID) return "rental";
    if (data.tradeInRequestID) return "trade-in";
    return "other";
}

function isFailedOrCancelled(status) {
    const value = String(status || "").toLowerCase();
    return value.includes("fail") || value.includes("cancel");
}

function salesContribution(data, order, category = transactionCategory(data)) {
    if (isFailedOrCancelled(data.transactionStatus || data.status)
        || isFailedOrCancelled(order?.orderStatus || order?.status)) return 0;

    const amount = Number(data.transactionAmount ?? data.amount ?? data.totalAmount ?? 0) || 0;
    if (category === "purchase") return amount;
    if (category === "refund" && !data.rentalID && String(data.orderID || "").trim()) return -amount;
    return 0;
}

async function loadAnalyticsTransactions(db, windowStart, selectedEnd) {
    const transactionCollection = db.collection("transaction");
    const windowStartIso = windowStart.toISOString();
    const selectedEndIso = selectedEnd.toISOString();
    const [transactionDateSnap, createdAtSnap, transactionDateStringSnap, createdAtStringSnap] = await Promise.all([
        transactionCollection
            .where("transactionDate", ">=", Timestamp.fromDate(windowStart))
            .where("transactionDate", "<", Timestamp.fromDate(selectedEnd))
            .get(),
        transactionCollection
            .where("createdAt", ">=", Timestamp.fromDate(windowStart))
            .where("createdAt", "<", Timestamp.fromDate(selectedEnd))
            .get(),
        transactionCollection
            .where("transactionDate", ">=", windowStartIso)
            .where("transactionDate", "<", selectedEndIso)
            .get(),
        transactionCollection
            .where("createdAt", ">=", windowStartIso)
            .where("createdAt", "<", selectedEndIso)
            .get()
    ]);
    const transactionDocs = new Map();
    transactionDateSnap.forEach(doc => transactionDocs.set(doc.id, doc.data() || {}));
    createdAtSnap.forEach(doc => transactionDocs.set(doc.id, doc.data() || {}));
    transactionDateStringSnap.forEach(doc => transactionDocs.set(doc.id, doc.data() || {}));
    createdAtStringSnap.forEach(doc => transactionDocs.set(doc.id, doc.data() || {}));
    // Older transactions may store dates as epoch milliseconds or another legacy
    // representation that Firestore range queries cannot match. Scan only when
    // the indexed queries found nothing, then keep records in the requested window.
    if (transactionDocs.size === 0) {
        const fallbackSnap = await transactionCollection.get();
        fallbackSnap.forEach(doc => {
            const data = doc.data() || {};
            const millis = timestampMillis(data.transactionDate) || timestampMillis(data.createdAt);
            if (millis >= windowStart.getTime() && millis < selectedEnd.getTime()) {
                transactionDocs.set(doc.id, data);
            }
        });
    }
    return transactionDocs;
}

async function loadLinkedDocuments(db, collectionName, ids, alternateField) {
    const collection = db.collection(collectionName);
    const uniqueIds = [...new Set(ids.filter(Boolean))];
    const docs = new Map();
    const jobs = uniqueIds.map(id => collection.doc(id).get().catch(() => null));
    if (alternateField) {
        for (let i = 0; i < uniqueIds.length; i += 10) {
            jobs.push(collection.where(alternateField, "in", uniqueIds.slice(i, i + 10)).get());
        }
    }
    const results = await Promise.all(jobs);
    results.forEach(result => {
        if (!result) return;
        if (Array.isArray(result)) return;
        if (typeof result.forEach !== "function") {
            if (result.exists) docs.set(result.id, result.data() || {});
            return;
        }
        result.forEach(doc => {
            const data = doc.data() || {};
            docs.set(doc.id, data);
            if (data[alternateField]) docs.set(String(data[alternateField]), data);
        });
    });
    return docs;
}

module.exports = {
    transactionCategory, isFailedOrCancelled, salesContribution, timestampMillis,
    malaysiaMonthBoundary, loadAnalyticsTransactions, loadLinkedDocuments
};
