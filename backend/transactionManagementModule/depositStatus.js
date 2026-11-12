function normalizeDepositStatus(value) {
    const status = String(value || "").trim().toLowerCase();
    if (status === "forfeited") return "Forfeited";
    if (["returned", "refunded"].includes(status)) return "Returned";
    if (["pending", "pending_return", "pending return"].includes(status)) return "Pending";
    return "Active";
}

module.exports = normalizeDepositStatus;
