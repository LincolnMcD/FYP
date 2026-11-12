const normalizeDepositStatus = require("../transactionManagementModule/depositStatus");

const malaysiaDate = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Kuala_Lumpur",
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
});

function dateKey(milliseconds) {
    const parts = Object.fromEntries(malaysiaDate.formatToParts(milliseconds).map(({ type, value }) => [type, value]));
    return `${parts.year}-${parts.month}-${parts.day}`;
}

function timestamp(value) {
    const milliseconds = typeof value?.toMillis === "function" ? value.toMillis() : Date.parse(value);
    return Number.isFinite(milliseconds) ? milliseconds : null;
}

const normalize = value => String(value || "").trim().toLowerCase();
const iso = value => value == null ? null : new Date(value).toISOString();
const metric = (label, value, format = "count") => ({ label, value, format });
const panel = (title, rows, limit = 6) => ({
    title,
    rows: rows.sort((a, b) => (b.date || "").localeCompare(a.date || "")).slice(0, limit)
});

async function records(db, name) {
    const snapshot = await db.collection(name).get();
    return snapshot.docs.map(doc => ({ ...doc.data(), id: doc.id, documentUpdatedAt: doc.updateTime }));
}

function transactionRow(transaction) {
    return {
        id: transaction.transactionID || transaction.id,
        title: transaction.transactionType || "Transaction",
        status: transaction.transactionStatus || transaction.status,
        amount: Number.isFinite(Number(transaction.transactionAmount)) && transaction.transactionAmount != null
            ? Number(transaction.transactionAmount) : null,
        date: iso(timestamp(transaction.transactionDate || transaction.createdAt))
    };
}

async function administrator(db) {
    const { getDashboardTaskCounts } = require("../taskAssignmentModule/server");
    const [users, leaves, taskCounts] = await Promise.all([
        records(db, "users"), records(db, "leaveApplication"), getDashboardTaskCounts()
    ]);
    const customers = users.filter(user => normalize(user.role || user.systemRole) === "customer");
    const activeStaff = users.filter(user =>
        normalize(user.role || user.systemRole) === "staff" && normalize(user.status || user.staffStatus || "active") === "active"
    );
    const pendingLeaves = leaves.filter(leave => normalize(leave.leaveStatus) === "pending").map(leave => ({
        id: leave.leaveID || leave.id,
        title: leave.leaveType ? `${leave.leaveType} leave` : "Leave application",
        detail: leave.applicantStaffName,
        status: leave.leaveStatus,
        date: iso(timestamp(leave.createdAt))
    }));
    const decisions = leaves.filter(leave => ["approved", "rejected"].includes(normalize(leave.leaveStatus))).map(leave => ({
        id: leave.applicantStaffName || "—",
        title: leave.leaveType ? `${leave.leaveType} leave` : "Leave application",
        status: leave.leaveStatus,
        date: iso(timestamp(leave.reviewedAt))
    }));
    return {
        title: "Administrator Dashboard",
        metrics: [
            metric("Total Customers", customers.length),
            metric("Active Staff", activeStaff.length),
            metric("Pending Leave Requests", pendingLeaves.length),
            metric("Unassigned Tasks", taskCounts.unassigned)
        ],
        panels: [
            panel("Pending Leave Actions", pendingLeaves),
            panel("Recent Leave Decisions", decisions, 5)
        ]
    };
}

async function customerService(db, today) {
    const tickets = await records(db, "supportTicket");
    const open = tickets.filter(ticket => ["pending", "in progress", "escalated"].includes(normalize(ticket.ticketStatus)));
    const resolvedToday = tickets.filter(ticket => {
        const date = timestamp(ticket.resolvedAt);
        return normalize(ticket.ticketStatus) === "resolved" && date != null && dateKey(date) === today;
    }).length;
    const ticketRow = ticket => ({
        id: ticket.ticketID || ticket.id,
        title: ticket.ticketCategory || "Support request",
        status: ticket.ticketStatus,
        date: iso(timestamp(ticket.lastMessageAt || ticket.createdDate))
    });
    return {
        title: "Customer Service Dashboard",
        metrics: [
            metric("Pending Requests", tickets.filter(ticket => normalize(ticket.ticketStatus) === "pending").length),
            metric("In Progress", tickets.filter(ticket => normalize(ticket.ticketStatus) === "in progress").length),
            metric("Unread Chats", null, "unread"),
            metric("Resolved Today", resolvedToday)
        ],
        unreadCandidates: open.filter(ticket => timestamp(ticket.lastCustomerMessageAt) != null).map(ticket => ({
            id: ticket.ticketID || ticket.id,
            date: iso(timestamp(ticket.lastCustomerMessageAt))
        })),
        panels: [
            panel("Pending Support", open.map(ticketRow)),
            panel("Recent Conversations", tickets.filter(ticket => ticket.lastMessageAt).map(ticketRow))
        ]
    };
}

async function operations(db) {
    const { getDashboardTaskCounts } = require("../taskAssignmentModule/server");
    const [products, transactions, rentals, taskCounts] = await Promise.all([
        ...["product", "transaction", "rental"].map(name => records(db, name)),
        getDashboardTaskCounts()
    ]);
    const listingStatus = product => normalize(product.listingStatus || product.status);
    const drafts = products.filter(product => listingStatus(product) === "draft");
    const draftRows = drafts.map(product => ({
        id: product.productID || product.id,
        title: product.listingTitle || [product.brand, product.model].filter(Boolean).join(" ") || "Draft listing",
        amount: product.sellingPrice != null && product.sellingPrice !== "" && Number.isFinite(Number(product.sellingPrice))
            ? Number(product.sellingPrice) : null,
        status: "Draft",
        date: iso(timestamp(product.updatedAt || product.documentUpdatedAt || product.createdAt))
    }));
    return {
        title: "Operations Dashboard",
        metrics: [
            metric("Active Listings", products.filter(product => listingStatus(product) === "listed").length),
            metric("Listings Awaiting Publication", drafts.length),
            metric("Inspecting Tasks", taskCounts.inspecting),
            metric("Pending Returns", rentals.filter(rental => normalizeDepositStatus(rental.depositStatus) === "Pending").length)
        ],
        panels: [
            panel("Listings to Review", draftRows, 5),
            panel("Recent Transactions", transactions.map(transactionRow))
        ]
    };
}

async function dashboardSummary(db, role, now = Date.now()) {
    const today = dateKey(now);
    switch (role) {
        case "admin": return administrator(db);
        case "customer support": return customerService(db, today);
        case "operator": return operations(db);
        default: throw new Error("Unsupported dashboard role");
    }
}

module.exports = dashboardSummary;
