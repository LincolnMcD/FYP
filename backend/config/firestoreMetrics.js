const { AsyncLocalStorage } = require("async_hooks");
const { Firestore, Query, Transaction, DocumentReference } = require("@google-cloud/firestore");

const requestContext = new AsyncLocalStorage();
const WINDOW_MS = 60_000;
const MAX_RETRIES = 2;
const counters = new Map();
let flushTimer = null;
let instrumented = false;

function operationLocation() {
    const frames = new Error().stack?.split("\n").slice(2) || [];
    const frame = frames.find(line => !line.includes("node_modules") && !line.includes("firestoreMetrics.js"));
    return frame ? frame.trim().replace(process.cwd(), ".") : "unknown";
}

function counterFor(key) {
    let counter = counters.get(key);
    if (!counter) {
        counter = { calls: 0, retries: 0, readDocuments: 0, failed: 0, lastError: "" };
        counters.set(key, counter);
    }
    return counter;
}

function startMetricsFlush() {
    if (flushTimer) return;
    flushTimer = setInterval(() => {
        if (counters.size === 0) return;
        const summary = [...counters.entries()]
            .map(([operation, value]) => ({ operation, ...value }))
            .sort((a, b) => b.readDocuments - a.readDocuments || b.calls - a.calls);
        counters.clear();
        if (process.env.ENABLE_FIRESTORE_METRICS === "true") {
            console.info("[firestore-read-metrics] last 60s", JSON.stringify(summary));
        }
    }, WINDOW_MS);
    flushTimer.unref?.();
}

function isQuotaExceeded(error) {
    return error?.code === 8 || error?.code === "8" ||
        /resource[_ -]?exhausted|quota exceeded/i.test(String(error?.code || error?.message || ""));
}

function retryDelay(attempt) {
    return Math.min(250 * (2 ** (attempt - 1)) + Math.floor(Math.random() * 100), 1500);
}

async function runRead(label, read, countRequested, countReturned) {
    const context = requestContext.getStore();
    const route = context?.route || "background";
    const key = `${label} | ${route} | ${operationLocation()}`;
    const counter = counterFor(key);
    counter.calls += 1;
    const requested = countRequested();
    let retry = 0;
    while (true) {
        try {
            const result = await read();
            counter.readDocuments += countReturned(result, requested);
            return result;
        } catch (error) {
            if (isQuotaExceeded(error) && retry < MAX_RETRIES) {
                retry += 1;
                counter.retries += 1;
                await new Promise(resolve => setTimeout(resolve, retryDelay(retry)));
                continue;
            }
            counter.failed += 1;
            counter.lastError = String(error?.code || error?.message || "unknown").slice(0, 100);
            throw error;
        }
    }
}

function wrapRead(proto, method, label, requestedCount, returnedCount) {
    if (!proto || typeof proto[method] !== "function" || proto[method].__rebyteMetricsWrapped) return;
    const original = proto[method];
    const wrapped = function (...args) {
        return runRead(
            label,
            () => original.apply(this, args),
            () => requestedCount(this, args),
            (result, requested) => returnedCount(result, requested)
        );
    };
    wrapped.__rebyteMetricsWrapped = true;
    proto[method] = wrapped;
}

function wrapTrackedRead(proto, method, label, requestedCount, returnedCount) {
    if (!proto || typeof proto[method] !== "function" || proto[method].__rebyteMetricsWrapped) return;
    const original = proto[method];
    const wrapped = function (...args) {
        const context = requestContext.getStore();
        const route = context?.route || "background";
        const counter = counterFor(`${label} | ${route} | ${operationLocation()}`);
        counter.calls += 1;
        const requested = requestedCount(this, args);
        return original.apply(this, args).then(result => {
            counter.readDocuments += returnedCount(result, requested);
            return result;
        }, error => {
            counter.failed += 1;
            counter.lastError = String(error?.code || error?.message || "unknown").slice(0, 100);
            throw error;
        });
    };
    wrapped.__rebyteMetricsWrapped = true;
    proto[method] = wrapped;
}

function wrapSnapshotListener(proto, label) {
    if (!proto || typeof proto.onSnapshot !== "function" || proto.onSnapshot.__rebyteMetricsWrapped) return;
    const original = proto.onSnapshot;
    const wrapped = function (...args) {
        const context = requestContext.getStore();
        const route = context?.route || "listener";
        const counter = counterFor(`${label} | ${route} | ${operationLocation()}`);
        const observerIndex = typeof args[0] === "function" ? 0 : -1;
        const originalObserver = observerIndex === 0 ? args[0] : args[0];
        const wrapNext = (callback) => typeof callback === "function" ? (...values) => {
            const snapshot = values[0];
            let reads = 1;
            if (typeof snapshot?.docChanges === "function") {
                try { reads = Math.max(1, snapshot.docChanges().length); } catch (_) {}
            }
            counter.calls += 1;
            counter.readDocuments += reads;
            return callback(...values);
        } : callback;
        if (observerIndex === 0) args[0] = wrapNext(args[0]);
        else if (originalObserver && typeof originalObserver === "object") {
            args[0] = { ...originalObserver, next: wrapNext(originalObserver.next) };
        }
        const unsubscribe = original.apply(this, args);
        if (typeof unsubscribe === "function") {
            const wrappedUnsubscribe = (...unsubscribeArgs) => unsubscribe(...unsubscribeArgs);
            wrappedUnsubscribe.__rebyteMetricsWrapped = true;
            return wrappedUnsubscribe;
        }
        return unsubscribe;
    };
    wrapped.__rebyteMetricsWrapped = true;
    proto.onSnapshot = wrapped;
}

function instrumentFirestore() {
    if (instrumented) return;
    instrumented = true;
    startMetricsFlush();
    // DocumentReference.get() delegates to Firestore.getAll(), so wrapping that
    // SDK boundary counts single-document reads as well as explicit getAll calls.
    wrapRead(Firestore.prototype, "getAll", "document/getAll", (_firestore, args) =>
        args.filter(arg => arg && typeof arg.path === "string").length,
    (_result, requested) => requested);
    wrapRead(Query.prototype, "get", "query/get", () => 0,
        result => Number.isFinite(result?.size) ? Math.max(1, result.size) : 1);
    wrapTrackedRead(Transaction.prototype, "get", "transaction/get", (_transaction, args) =>
        args[0] && typeof args[0].path === "string" ? 1 : 0,
    (result, requested) => Array.isArray(result?.docs) ? Math.max(1, result.size) : requested);
    wrapTrackedRead(Transaction.prototype, "getAll", "transaction/getAll", (_transaction, args) =>
        args.filter(arg => arg && typeof arg.path === "string").length,
    (_result, requested) => requested);
    wrapSnapshotListener(DocumentReference.prototype, "listener/document");
    wrapSnapshotListener(Query.prototype, "listener/query");
}

function runWithRequest(req, next) {
    const safePath = String(req.path || "/").replace(/(^|\/)([^/]{20,}|[^/]*@[^/]*)/g, "$1:id");
    const route = `${req.method} ${safePath}`;
    requestContext.run({ route }, next);
}

function recordRequest(path) {
    const key = `request | ${path}`;
    const counter = counterFor(key);
    counter.calls += 1;
}

module.exports = { instrumentFirestore, runWithRequest, recordRequest };
