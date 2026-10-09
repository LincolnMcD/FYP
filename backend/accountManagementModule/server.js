const express = require("express");
const cors = require("cors");
const { getAuth } = require("firebase-admin/auth");
const { FieldValue } = require("firebase-admin/firestore");
const nodemailer = require("nodemailer");
const crypto = require("crypto");

const transporter = nodemailer.createTransport({
    service: "gmail",
    auth: {
        user: "lolincoln021@gmail.com",
        pass: "uooc wvdf zoqy nujh"
    }
});

async function sendOTPEmail(email, otp) {
    const mailOptions = {
        from: "\"ReByte Secure\" <lolincoln021@gmail.com>",
        to: email,
        subject: "Your ReByte Verification Code",
        text: `Your verification code is: ${otp}`,
        html: `
        <div style="font-family: Arial, sans-serif; max-width: 400px; margin: 0 auto; padding: 20px; text-align: center; border: 1px solid #E2E8F0; border-radius: 12px;">
            <h1 style="color: #0C5AD2; font-size: 32px; font-weight: bold; letter-spacing: 1px; margin-bottom: 20px; margin-top: 5px;">ReByte</h1>
            <h2 style="color: #0F172A; font-size: 20px; margin-bottom: 8px;">Verify Your Account</h2>
            <p style="color: #475569; font-size: 14px; margin-bottom: 24px;">Please enter this 6-digit code in the ReByte app to verify your email address. This code expires in 10 minutes.</p>
            <div style="background-color: #F8FAFC; border-radius: 8px; padding: 16px; font-size: 28px; font-weight: bold; letter-spacing: 6px; color: #0C5AD2;">
                ${otp}
            </div>
        </div>
        `
    };
    return transporter.sendMail(mailOptions);
}
const { validateEmail, validatePassword } = require("./validation");
const Customer = require("../models/customerModel");
const Staff = require("../models/staffModel");
const db = require("../config/firebase");

const router = express.Router();
const CUSTOMER_SUSPENSION_MS = 7 * 24 * 60 * 60 * 1000;
let suspensionSweepInProgress = false;

function timestampMillis(value) {
    if (!value) return NaN;
    if (typeof value.toMillis === "function") return value.toMillis();
    if (typeof value.toDate === "function") return value.toDate().getTime();
    if (value instanceof Date) return value.getTime();
    if (typeof value === "number") return value;
    const parsed = new Date(value).getTime();
    return Number.isFinite(parsed) ? parsed : NaN;
}

function escapeHtml(value) {
    return String(value || "").replace(/[&<>"']/g, character => ({
        "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;"
    })[character]);
}

async function sendCustomerStatusEmail(customer, status, reason) {
    const suspended = status === "Suspended";
    const subject = suspended ? "Your ReByte account is temporarily suspended" : "Your ReByte account has been banned";
    const accessText = suspended
        ? "Your account is suspended for 7 days and will automatically reactivate when this period ends."
        : "Your account access has been disabled until an administrator reviews and removes the ban.";
    const safeName = escapeHtml(customer.fullName || "ReByte customer");
    const safeReason = escapeHtml(reason).replace(/\r?\n/g, "<br>");
    return transporter.sendMail({
        from: "\"ReByte Support\" <lolincoln021@gmail.com>",
        to: customer.email,
        subject,
        text: `Hello ${customer.fullName || "ReByte customer"},\n\n${accessText}\n\nReason: ${reason}\n\nPlease contact ReByte support if you have questions.`,
        html: `<div style="font-family:Arial,sans-serif;max-width:520px;margin:auto;padding:24px;color:#172033"><h2 style="color:#082f72">ReByte account notice</h2><p>Hello ${safeName},</p><p>${accessText}</p><p><strong>Reason:</strong><br>${safeReason}</p><p>Please contact ReByte support if you have questions.</p></div>`
    });
}

async function reactivateExpiredCustomerSuspensions() {
    if (suspensionSweepInProgress) return;
    suspensionSweepInProgress = true;
    try {
        const snapshot = await db.collection("users").where("status", "==", "Suspended").get();
        const now = Date.now();
        for (const customerDoc of snapshot.docs) {
            const customer = customerDoc.data();
            if (timestampMillis(customer.suspendedUntil) > now) continue;
            if (!Number.isFinite(timestampMillis(customer.suspendedUntil))) continue;
            const authUid = customer.userId || customerDoc.id;
            try {
                await getAuth().updateUser(authUid, { disabled: false });
                const reactivated = await db.runTransaction(async transaction => {
                    const latestDoc = await transaction.get(customerDoc.ref);
                    if (!latestDoc.exists) return false;
                    const latest = latestDoc.data();
                    if (latest.status !== "Suspended" || timestampMillis(latest.suspendedUntil) > Date.now()) return false;
                    transaction.update(customerDoc.ref, {
                        status: "Active",
                        suspensionReason: FieldValue.delete(),
                        suspendedAt: FieldValue.delete(),
                        suspendedUntil: FieldValue.delete(),
                        updatedAt: FieldValue.serverTimestamp()
                    });
                    return true;
                });
                if (reactivated) {
                    await db.collection("customerAccountAudit").add({
                        customerId: customerDoc.id,
                        userId: authUid,
                        customerName: customer.fullName || "Customer",
                        email: customer.email || "",
                        action: "Automatic Reactivation",
                        reason: "The seven-day suspension period expired.",
                        performedBy: "system",
                        createdAt: FieldValue.serverTimestamp()
                    });
                }
                if (!reactivated) {
                    const latestDoc = await customerDoc.ref.get();
                    const latestStatus = latestDoc.exists ? String(latestDoc.data().status || "Active") : "Active";
                    await getAuth().updateUser(authUid, { disabled: latestStatus !== "Active" });
                }
            } catch (err) {
                console.error(`Could not auto-reactivate suspended customer ${customerDoc.id}:`, err.message);
            }
        }
    } catch (err) {
        console.error("Suspension expiry sweep failed:", err.message);
    } finally {
        suspensionSweepInProgress = false;
    }
}

async function requireAdmin(req, res, next) {
    const idToken = req.headers.authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
    if (!idToken) return res.status(401).json({ error: "Please sign in as an administrator." });
    try {
        const decoded = await getAuth().verifyIdToken(idToken);
        const usersRef = db.collection("users");
        let userData = null;

        const uidDoc = await usersRef.doc(decoded.uid).get();
        if (uidDoc.exists) userData = uidDoc.data();

        if (!userData) {
            const uidSnapshot = await usersRef.where("userId", "==", decoded.uid).limit(1).get();
            if (!uidSnapshot.empty) userData = uidSnapshot.docs[0].data();
        }

        if (!userData && decoded.email) {
            for (const email of new Set([decoded.email, decoded.email.toLowerCase()])) {
                const emailSnapshot = await usersRef.where("email", "==", email).limit(1).get();
                if (!emailSnapshot.empty) {
                    userData = emailSnapshot.docs[0].data();
                    break;
                }
            }
        }

        const role = userData?.systemRole || userData?.role;
        if (typeof role !== "string" || role.trim().toLowerCase() !== "admin") {
            return res.status(403).json({ error: "Administrator access is required." });
        }
        req.adminUid = decoded.uid;
        return next();
    } catch (err) {
        return res.status(401).json({ error: "Your admin session has expired. Please sign in again." });
    }
}

function registeredAccountType(userData = {}) {
    const roles = [userData.systemRole, userData.role, userData.accountType, userData.userType]
        .filter(value => typeof value === "string")
        .map(value => value.trim().toLowerCase());
    if (roles.includes("admin")) return "Admin";
    if (roles.includes("staff")) return "Staff";
    return "Customer";
}

async function findRegisteredAccount(email) {
    const usersRef = db.collection("users");
    const snapshot = await usersRef.where("email", "==", email).get();
    if (!snapshot.empty) return snapshot.docs[0].data();
    try {
        const authUser = await getAuth().getUserByEmail(email);
        const userDoc = await usersRef.doc(authUser.uid).get();
        return userDoc.exists ? userDoc.data() : { role: "Customer" };
    } catch (err) {
        if (err.code !== "auth/user-not-found") throw err;
        return null;
    }
}

router.post("/register-staff", requireAdmin, async (req, res) => {
    const { password, fullName, phoneNumber, staffNo, specialization, position } = req.body;
    const email = typeof req.body.email === "string" ? req.body.email.trim().toLowerCase() : "";
    if (!email || !password || !fullName?.trim() || !phoneNumber || !staffNo || !position) {
        return res.status(400).json({ error: "Missing required fields" });
    }

    const emailValidation = validateEmail(email);
    if (!emailValidation.isValid) return res.status(400).json({ error: emailValidation.message });
    const passwordValidation = validatePassword(password);
    if (!passwordValidation.isValid) return res.status(400).json({ error: passwordValidation.message });
    const normalizedPhone = String(phoneNumber).replace(/^\+60/, "");
    const expectedPhoneLength = normalizedPhone.startsWith("11") ? 10 : 9;
    if (!/^1\d+$/.test(normalizedPhone) || normalizedPhone.length !== expectedPhoneLength) {
        return res.status(400).json({ error: "Please enter a valid Malaysian mobile number." });
    }
    if (!["Inspector", "Deliverer", "Both"].includes(position)) {
        return res.status(400).json({ error: "Please select a valid staff position." });
    }
    const mobileBrands = ["Apple", "Samsung", "Xiaomi", "Huawei", "Oppo", "Vivo", "Google Pixel", "OnePlus"];
    const selectedBrands = Array.isArray(specialization) ? specialization : [];
    if (selectedBrands.some(brand => !mobileBrands.includes(brand)) ||
        (position !== "Deliverer" && (selectedBrands.length < 1 || selectedBrands.length > 3)) ||
        (position === "Deliverer" && selectedBrands.length > 0)) {
        return res.status(400).json({ error: "Choose between 1 and 3 device specializations for Inspector or Both roles. Deliverers do not have device specialization." });
    }

    try {
        const usersRef = db.collection("users");
        const existingAccount = await findRegisteredAccount(email);
        if (existingAccount) return res.status(409).json({ error: `This email is already registered as ${registeredAccountType(existingAccount)}.` });

        const authPayload = { email, password, displayName: fullName.trim() };
        const userRecord = await getAuth().createUser(authPayload);

        const newStaff = new Staff({
            fullName: fullName.trim(),
            email: email,
            phoneNumber: `+60${normalizedPhone}`,
            loginMethod: "Email",
            staffNo: staffNo || "S0001",
            specialization: position === "Deliverer" ? [] : selectedBrands,
            position: position
        });
        
        newStaff.userId = userRecord.uid;
        
        const staffData = newStaff.toJSON();
        staffData.createdAt = FieldValue.serverTimestamp();
        staffData.updatedAt = FieldValue.serverTimestamp();

        try {
            await usersRef.doc(userRecord.uid).set(staffData);
        } catch (writeError) {
            await getAuth().deleteUser(userRecord.uid);
            throw writeError;
        }

        return res.status(200).json({ message: "Staff account created successfully" });
    } catch (err) {
        if (err.code === "auth/email-already-exists") return res.status(400).json({ error: "Email is already registered" });
        console.error(err);
        return res.status(500).json({ error: "Internal Server Error" });
    }
});


router.post("/check-staff-email", requireAdmin, async (req, res) => {
    const email = typeof req.body.email === "string" ? req.body.email.trim().toLowerCase() : "";
    if (!email) return res.status(400).json({ error: "Email is required" });
    try {
        const existingAccount = await findRegisteredAccount(email);
        if (existingAccount) return res.status(409).json({ error: `This email is already registered as ${registeredAccountType(existingAccount)}.` });
        return res.status(200).json({ message: "Email is available" });
    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: "Internal Server Error" });
    }
});

router.get("/staff-session", async (req, res) => {
    const idToken = req.headers.authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
    if (!idToken) return res.status(401).json({ error: "Staff session is missing." });
    try {
        // Check disabled status before revocation: archiving disables the Firebase
        // user and revokes tokens, and the archive reason should take precedence.
        const decoded = await getAuth().verifyIdToken(idToken, false);
        const authUser = await getAuth().getUser(decoded.uid);
        if (authUser.disabled) return res.status(401).json({ archived: true, error: "This staff account has been archived." });
        await getAuth().verifyIdToken(idToken, true);

        const usersRef = db.collection("users");
        let userData = null;
        const uidDoc = await usersRef.doc(decoded.uid).get();
        if (uidDoc.exists) userData = uidDoc.data();
        if (!userData) {
            const uidSnapshot = await usersRef.where("userId", "==", decoded.uid).limit(1).get();
            if (!uidSnapshot.empty) userData = uidSnapshot.docs[0].data();
        }
        if (!userData && decoded.email) {
            const emailSnapshot = await usersRef.where("email", "==", decoded.email.toLowerCase()).limit(1).get();
            if (!emailSnapshot.empty) userData = emailSnapshot.docs[0].data();
        }

        const role = String(userData?.role || userData?.systemRole || "").trim().toLowerCase();
        if (role !== "staff" || String(userData?.status || "active").trim().toLowerCase() === "archived") {
            return res.status(403).json({ archived: String(userData?.status || "").trim().toLowerCase() === "archived", error: "This staff account is no longer active." });
        }
        return res.status(200).json({
            active: true,
            profile: {
                fullName: userData.fullName || authUser.displayName || "Staff Member",
                email: userData.email || decoded.email || "",
                phoneNumber: userData.phoneNumber || "",
                position: userData.position || "",
                specialization: Array.isArray(userData.specialization) ? userData.specialization : []
            }
        });
    } catch (err) {
        if (err.code === "auth/user-disabled") {
            return res.status(401).json({ archived: true, error: "This staff account has been archived." });
        }
        const statusCode = ["auth/id-token-revoked", "auth/id-token-expired", "auth/argument-error"].includes(err.code) ? 401 : 500;
        if (statusCode === 500) console.error("Staff session check failed:", err);
        return res.status(statusCode).json({ archived: false, error: statusCode === 401 ? "Your staff session has expired. Please sign in again." : "Could not verify staff session." });
    }
});

router.get("/account-session", async (req, res) => {
    const idToken = req.headers.authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
    if (!idToken) return res.status(401).json({ expired: true, error: "Session expired. Please log in again." });
    try {
        // Check disabled status before revocation so archived accounts are
        // distinguishable from active accounts with an expired session.
        const decoded = await getAuth().verifyIdToken(idToken, false);
        const authUser = await getAuth().getUser(decoded.uid);
        const usersRef = db.collection("users");
        let userDoc = await usersRef.doc(decoded.uid).get();
        if (!userDoc.exists) {
            const uidSnapshot = await usersRef.where("userId", "==", decoded.uid).limit(1).get();
            if (!uidSnapshot.empty) userDoc = uidSnapshot.docs[0];
        }
        if (!userDoc.exists && decoded.email) {
            const emailSnapshot = await usersRef.where("email", "==", decoded.email.toLowerCase()).limit(1).get();
            if (!emailSnapshot.empty) userDoc = emailSnapshot.docs[0];
        }
        if (!userDoc.exists) {
            return res.status(401).json({ expired: true, error: "Session expired. Please log in again." });
        }

        const userData = userDoc.data();
        const role = String(userData.role || userData.systemRole || "").trim().toLowerCase();
        const status = String(userData.status || "active").trim().toLowerCase();
        if (role === "customer" && ["suspended", "banned"].includes(status)) {
            const accountStatus = status === "suspended" ? "Suspended" : "Banned";
            const message = status === "suspended"
                ? "Your account has been suspended. Please check your email for more details."
                : "Your account has been banned. Please check your email for more details.";
            return res.status(401).json({ expired: true, status: accountStatus, error: message });
        }
        if (authUser.disabled) {
            const archived = status === "archived" || role === "staff";
            return res.status(401).json({ archived, expired: true, error: archived ? "This account has been archived." : "Your account is disabled." });
        }
        await getAuth().verifyIdToken(idToken, true);
        if (role === "staff" && status === "archived") {
            return res.status(401).json({ archived: true, expired: true, error: "This staff account has been archived." });
        }
        return res.status(200).json({ active: true, role: userData.role || userData.systemRole || "Customer" });
    } catch (err) {
        const expiredCodes = ["auth/id-token-revoked", "auth/id-token-expired", "auth/argument-error", "auth/user-disabled", "auth/user-not-found"];
        const statusCode = expiredCodes.includes(err.code) ? 401 : 500;
        if (statusCode === 500) console.error("Account session check failed:", err);
        return res.status(statusCode).json({ expired: statusCode === 401, archived: err.code === "auth/user-disabled", error: statusCode === 401 ? "Session expired. Please log in again." : "Could not verify account session." });
    }
});

router.get("/staff-profile", async (req, res) => {
    const idToken = req.headers.authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
    if (!idToken) return res.status(401).json({ error: "Please sign in to view your staff profile." });
    try {
        const decoded = await getAuth().verifyIdToken(idToken, true);
        const usersRef = db.collection("users");
        let staffDoc = await usersRef.doc(decoded.uid).get();
        if (!staffDoc.exists) {
            const uidSnapshot = await usersRef.where("userId", "==", decoded.uid).limit(1).get();
            if (!uidSnapshot.empty) staffDoc = uidSnapshot.docs[0];
        }
        if (!staffDoc.exists) return res.status(404).json({ error: "Staff account not found." });
        const staff = staffDoc.data();
        const role = String(staff.role || staff.systemRole || "").trim().toLowerCase();
        if (role !== "staff" || String(staff.status || "active").trim().toLowerCase() === "archived") {
            return res.status(403).json({ error: "This staff account is not active." });
        }
        return res.status(200).json({ profile: { ...staff, id: staffDoc.id, email: staff.email || decoded.email || "" } });
    } catch (err) {
        const statusCode = ["auth/id-token-revoked", "auth/user-disabled", "auth/id-token-expired", "auth/argument-error"].includes(err.code) ? 401 : 500;
        if (statusCode === 500) console.error("Staff profile fetch failed:", err);
        return res.status(statusCode).json({ error: statusCode === 401 ? "Your staff session has expired. Please sign in again." : "Could not load staff profile." });
    }
});

router.patch("/staff-profile", async (req, res) => {
    const idToken = req.headers.authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
    if (!idToken) return res.status(401).json({ error: "Please sign in to update your staff profile." });

    const { fullName, phoneNumber, position, specialization } = req.body;
    const normalizedName = typeof fullName === "string" ? fullName.trim() : "";
    if (!/^[A-Za-z]+(?:\s+[A-Za-z]+)*$/.test(normalizedName)) {
        return res.status(400).json({ error: "Full name can contain letters and spaces only." });
    }

    let phoneDigits = String(phoneNumber || "").replace(/\D/g, "");
    if (phoneDigits.startsWith("60")) phoneDigits = phoneDigits.slice(2);
    const expectedPhoneLength = phoneDigits.startsWith("11") ? 10 : 9;
    if (!/^1\d+$/.test(phoneDigits) || phoneDigits.length !== expectedPhoneLength) {
        return res.status(400).json({ error: "Please enter a valid Malaysian mobile number." });
    }
    if (!["Inspector", "Deliverer", "Both"].includes(position)) {
        return res.status(400).json({ error: "Please select a valid staff position." });
    }

    const allowedSpecializations = ["Apple", "Samsung", "Xiaomi", "Huawei", "Oppo", "Vivo", "Google Pixel", "OnePlus"];
    const selectedSpecializations = Array.isArray(specialization) ? specialization : [];
    const uniqueSpecializations = [...new Set(selectedSpecializations)];
    if (uniqueSpecializations.length !== selectedSpecializations.length ||
        selectedSpecializations.some(value => !allowedSpecializations.includes(value)) ||
        (position === "Deliverer" && selectedSpecializations.length !== 0) ||
        (position !== "Deliverer" && (selectedSpecializations.length < 1 || selectedSpecializations.length > 3))) {
        return res.status(400).json({ error: "Choose between 1 and 3 device specializations for Inspector or Both roles. Deliverers do not have device specialization." });
    }

    try {
        const decoded = await getAuth().verifyIdToken(idToken, true);
        const authUid = decoded.uid;
        const usersRef = db.collection("users");
        let staffRef = usersRef.doc(authUid);
        let staffDoc = await staffRef.get();
        if (!staffDoc.exists) {
            const uidSnapshot = await usersRef.where("userId", "==", authUid).limit(1).get();
            if (!uidSnapshot.empty) {
                staffDoc = uidSnapshot.docs[0];
                staffRef = staffDoc.ref;
            }
        }
        if (!staffDoc.exists) return res.status(404).json({ error: "Staff account not found." });

        const staff = staffDoc.data();
        const role = String(staff.role || staff.systemRole || "").trim().toLowerCase();
        if (role !== "staff" || String(staff.status || "active").trim().toLowerCase() === "archived") {
            return res.status(403).json({ error: "This staff account is not active." });
        }

        const profile = {
            fullName: normalizedName,
            phoneNumber: `+60${phoneDigits}`,
            position,
            specialization: position === "Deliverer" ? [] : selectedSpecializations
        };
        await staffRef.update({ ...profile, updatedAt: FieldValue.serverTimestamp() });
        try {
            await getAuth().updateUser(authUid, { displayName: normalizedName });
        } catch (authError) {
            console.warn("Staff profile saved, but Firebase Auth display name could not be synchronized:", authError.message);
        }

        return res.status(200).json({
            success: true,
            message: "Staff profile updated successfully.",
            profile: {
                ...profile,
                staffNo: staff.staffNo || "",
                email: staff.email || decoded.email || ""
            }
        });
    } catch (err) {
        const statusCode = ["auth/id-token-revoked", "auth/user-disabled", "auth/id-token-expired", "auth/argument-error"].includes(err.code) ? 401 : 500;
        if (statusCode === 500) console.error("Staff profile update failed:", err);
        return res.status(statusCode).json({ error: statusCode === 401 ? "Your staff session has expired. Please sign in again." : "Could not update staff profile." });
    }
});


router.post("/request-otp", async (req, res) => {
    const { email } = req.body;
    if (!email) return res.status(400).json({ error: "Email is required" });

    try {
        const usersRef = db.collection("users");
        const snapshot = await usersRef.where("email", "==", email).get();
        if (!snapshot.empty) {
            const registeredMethod = snapshot.docs[0].data().loginMethod;
            if (registeredMethod && registeredMethod !== "Email") {
                return res.status(400).json({ error: `Your email address is registered at ${registeredMethod}. Please login using ${registeredMethod}.` });
            }
            return res.status(400).json({ error: "Email is already registered" });
        }

        const otpCode = crypto.randomInt(100000, 999999).toString();
        const otpExpiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

        await db.collection("otps").doc(email).set({
            otpCode,
            otpExpiresAt
        });

        await sendOTPEmail(email, otpCode);
        return res.status(200).json({ message: "Verification code sent." });
    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: "Internal Server Error" });
    }
});

router.post("/verify-registration-otp", async (req, res) => {
    const { email, otp } = req.body;
    if (!email || !otp) return res.status(400).json({ error: "Email and OTP are required" });

    try {
        const otpRef = db.collection("otps").doc(email);
        const otpDoc = await otpRef.get();

        if (!otpDoc.exists) return res.status(400).json({ error: "No OTP requested for this email" });

        const otpData = otpDoc.data();
        if (otpData.otpCode !== otp.toString()) return res.status(400).json({ error: "Invalid verification code" });

        const now = new Date();
        const expiresAt = new Date(otpData.otpExpiresAt);
        if (now > expiresAt) return res.status(400).json({ error: "OTP has expired. Please request a new one." });

        return res.status(200).json({ message: "OTP Verified successfully" });
    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: "Internal Server Error" });
    }
});

router.post("/register", async (req, res) => {
    // RE-ARCHITECTED: ONLY REQUIRE EMAIL, PASSWORD, and OTP!
    const { email, password, otp, fullName, phoneNumber, gender, birthDate } = req.body;

    if (!email || !password || !otp) {
        return res.status(400).json({ error: "Email, Password, and OTP are required" });
    }

    const emailValidation = validateEmail(email);
    if (!emailValidation.isValid) return res.status(400).json({ error: emailValidation.message });

    const passwordValidation = validatePassword(password);
    if (!passwordValidation.isValid) return res.status(400).json({ error: passwordValidation.message });

    try {
        const usersRef = db.collection("users");
        const snapshot = await usersRef.where("email", "==", email).get();
        if (!snapshot.empty) {
            const registeredMethod = snapshot.docs[0].data().loginMethod;
            if (registeredMethod && registeredMethod !== "Email") {
                return res.status(400).json({ error: `Your email address is registered at ${registeredMethod}. Please login using ${registeredMethod}.` });
            }
            return res.status(400).json({ error: "Email is already registered" });
        }

        const otpRef = db.collection("otps").doc(email);
        const otpDoc = await otpRef.get();

        if (!otpDoc.exists) return res.status(400).json({ error: "No OTP requested for this email" });

        const otpData = otpDoc.data();
        if (otpData.otpCode !== otp.toString()) return res.status(400).json({ error: "Invalid verification code" });

        const now = new Date();
        const expiresAt = new Date(otpData.otpExpiresAt);
        if (now > expiresAt) return res.status(400).json({ error: "OTP has expired. Please request a new one." });

        // OTP Validated! 
        await otpRef.delete();

        const authPayload = { email, password };

        const userRecord = await getAuth().createUser(authPayload);

        // Save full schema using the Customer model
        const newCustomer = new Customer({
            fullName: fullName || "",
            email: email,
            phoneNumber: phoneNumber || "",
            loginMethod: "Email",
            birthDate: birthDate,
            gender: gender
        });
        
        // Override generated userId with Firebase Auth UID
        newCustomer.userId = userRecord.uid;
        
        // Use JSON representation
        const customerData = newCustomer.toJSON();
        
        // Merge createdAt and updatedAt natively via Firestore FieldValue
        customerData.createdAt = FieldValue.serverTimestamp();
        customerData.updatedAt = FieldValue.serverTimestamp();

        await usersRef.doc(userRecord.uid).set(customerData);

        return res.status(200).json({ message: "Registration successful" });
    } catch (err) {
        if (err.code === "auth/email-already-exists") return res.status(400).json({ error: "Email is already registered" });
        console.error(err);
        return res.status(500).json({ error: "Internal Server Error connecting to Database" });
    }
});

router.post("/forgot-password/request-otp", async (req, res) => {
    const { email } = req.body;
    if (!email) return res.status(400).json({ error: "Email is required" });

    try {
        const usersRef = db.collection("users");
        const snapshot = await usersRef.where("email", "==", email).get();

        if (snapshot.empty) {
            return res.status(404).json({ error: "Email not registered. Please register first." });
        }

        const userDoc = snapshot.docs[0].data();
        if (userDoc.loginMethod && userDoc.loginMethod !== "Email") {
            return res.status(400).json({ error: `Email registered via ${userDoc.loginMethod}. Please use social sign-in.` });
        }
        if (userDoc.role === "Admin") {
            return res.status(403).json({ error: "Password resets are heavily constrained for Administrator accounts. Please contact system administrators." });
        }

        const otpCode = crypto.randomInt(100000, 999999).toString();
        const otpExpiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

        await db.collection("otps").doc(email + "_reset").set({
            otpCode,
            otpExpiresAt
        });

        await sendOTPEmail(email, otpCode);
        return res.status(200).json({ message: "Verification code sent." });
    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: "Internal Server Error" });
    }
});

router.post("/forgot-password/verify-otp", async (req, res) => {
    const { email, otp, exchangeForResetToken } = req.body;
    if (!email || !otp) return res.status(400).json({ error: "Email and OTP are required" });

    try {
        const otpRef = db.collection("otps").doc(email + "_reset");
        const otpDoc = await otpRef.get();

        if (!otpDoc.exists) return res.status(400).json({ error: "No OTP requested for this email" });

        const otpData = otpDoc.data();
        if (otpData.otpCode !== otp.toString()) return res.status(400).json({ error: "Invalid verification code" });

        const now = new Date();
        const expiresAt = new Date(otpData.otpExpiresAt);
        if (now > expiresAt) return res.status(400).json({ error: "OTP has expired. Please request a new one." });

        // Website exchanges the verified OTP for a separate, short-lived reset session.
        // Older mobile clients can continue using their existing OTP flow.
        if (exchangeForResetToken) {
            const resetToken = crypto.randomBytes(32).toString('hex');
            await db.runTransaction(async transaction => {
                const current = await transaction.get(otpRef);
                if (!current.exists || current.data().otpCode !== otp.toString() ||
                    Date.now() >= Date.parse(current.data().otpExpiresAt)) {
                    throw new Error('Reset code changed during verification');
                }
                transaction.set(otpRef, {
                    resetTokenHash: crypto.createHash('sha256').update(resetToken).digest('hex'),
                    resetExpiresAt: new Date(Date.now() + 15 * 60 * 1000).toISOString()
                });
            });
            return res.status(200).json({ success: true, resetToken, message: "Email verified successfully" });
        }
        return res.status(200).json({ success: true, message: "OTP is valid!" });
    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: "Internal Server Error during OTP verification" });
    }
});

router.post("/forgot-password/reset", async (req, res) => {
    const { email, newPassword, otp, resetToken } = req.body;
    if (!email || !newPassword || (!otp && !resetToken)) return res.status(400).json({ error: "Missing required parameters" });

    const passwordValidation = validatePassword(newPassword);
    if (!passwordValidation.isValid) return res.status(400).json({ error: passwordValidation.message });

    try {
        const otpRef = db.collection("otps").doc(email + "_reset");
        const otpDoc = await otpRef.get();

        const sessionError = "Your password reset session has expired or is invalid. Please verify your email again.";
        const tokenHash = typeof resetToken === 'string'
            ? crypto.createHash('sha256').update(resetToken).digest('hex') : null;
        const validSession = data => data && (resetToken
            ? tokenHash && data.resetTokenHash === tokenHash && Date.parse(data.resetExpiresAt) > Date.now()
            : data.otpCode === String(otp) && Date.parse(data.otpExpiresAt) > Date.now());
        if (!otpDoc.exists || !validSession(otpDoc.data())) {
            return res.status(400).json({ error: sessionError });
        }

        const usersRef = db.collection("users");
        const snapshot = await usersRef.where("email", "==", email).get();
        if (snapshot.empty) return res.status(404).json({ error: "User not found" });

        const uid = snapshot.docs[0].data().userId;

        // Check if new password is the same as the current password by attempting to sign in
        const FIREBASE_API_KEY = "AIzaSyA8MQf-isqvndby6N6k2bfbD-KagiawFNE";
        const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_API_KEY}`;
        let fetchParams;
        if (typeof fetch === 'undefined') {
            fetchParams = require('node-fetch')(url, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ email, password: newPassword, returnSecureToken: true })
            });
        } else {
            fetchParams = fetch(url, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ email, password: newPassword, returnSecureToken: true })
            });
        }
        
        const signInResponse = await fetchParams;
        const signInData = await signInResponse.json();
        
        if (!signInData.error) {
            return res.status(400).json({ error: "New password cannot be the same as current password" });
        }

        // Claim only after validation so a rejected password can be corrected and retried.
        const claimed = await db.runTransaction(async transaction => {
            const current = await transaction.get(otpRef);
            if (!current.exists || !validSession(current.data()) || current.data().resetInProgress) return false;
            transaction.update(otpRef, { resetInProgress: true });
            return true;
        });
        if (!claimed) return res.status(400).json({ error: sessionError });
        try {
            await getAuth().updateUser(uid, { password: newPassword });
            await getAuth().revokeRefreshTokens(uid);
        } catch (err) {
            await db.runTransaction(async transaction => {
                const current = await transaction.get(otpRef);
                if (current.exists && validSession(current.data())) transaction.update(otpRef, { resetInProgress: false });
            });
            throw err;
        }
        await db.runTransaction(async transaction => {
            const current = await transaction.get(otpRef);
            if (current.exists && (resetToken ? current.data().resetTokenHash === tokenHash : current.data().otpCode === String(otp))) {
                transaction.delete(otpRef);
            }
        });

        return res.status(200).json({ success: true, message: "Password updated successfully" });
    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: "Internal Server Error during reset" });
    }
});

router.post("/update-profile", async (req, res) => {
    const { email, fullName, phoneNumber, birthDate, gender } = req.body;
    if (!email) return res.status(400).json({ error: "Email identifier is required" });

    try {
        const usersRef = db.collection("users");
        const snapshot = await usersRef.where("email", "==", email).get();

        if (snapshot.empty) return res.status(404).json({ error: "User not found" });

        const userDoc = snapshot.docs[0];

        await userDoc.ref.update({
            fullName: fullName || "",
            phoneNumber: phoneNumber || "",
            birthDate: birthDate || null,
            gender: gender || "Not Specified",
            updatedAt: FieldValue.serverTimestamp()
        });

        return res.status(200).json({ message: "Profile updated successfully!" });
    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: "Failed to update profile" });
    }
});

router.post("/oauth-login", async (req, res) => {
    const { idToken, loginMethod, clientType, fallbackEmail } = req.body;
    if (!idToken) return res.status(400).json({ error: "idToken is required" });

    try {
        const decodedToken = await getAuth().verifyIdToken(idToken);
        const uid = decodedToken.uid;

        let email = decodedToken.email;
        let phone = decodedToken.phone_number;
        let name = decodedToken.name || "ReByte User";

        console.log("=== OAUTH ATTEMPT ===");
        console.log("JWT -> Email:", email, "| Phone:", phone, "| UID:", uid, "| Method:", loginMethod);

        if (!email || !phone) {
            try {
                const userRecord = await getAuth().getUser(uid);
                console.log("UserRecord -> Email:", userRecord.email, "| Phone:", userRecord.phoneNumber);
                console.log("UserRecord -> providerData:", JSON.stringify(userRecord.providerData));

                email = email || userRecord.email;
                phone = phone || userRecord.phoneNumber;
                if (name === "ReByte User" && userRecord.displayName) name = userRecord.displayName;

                // Explicit fallback for nested providerData
                if (!email && userRecord.providerData) {
                    const providerWithEmail = userRecord.providerData.find(p => p.email);
                    if (providerWithEmail) email = providerWithEmail.email;
                }
            } catch (e) {
                console.error("Failed to fetch explicit UserRecord", e);
            }
        }

        if (!email && fallbackEmail) {
            email = fallbackEmail;
        }

        console.log("FINAL EVALUATED IDENTITY -> Email:", email, "| Phone:", phone);

        let snapshot;
        if (email) {
            snapshot = await db.collection("users").where("email", "==", email).get();
        } else if (phone) {
            snapshot = await db.collection("users").where("phoneNumber", "==", phone).get();
        } else {
            snapshot = { empty: true };
        }

        if (!snapshot.empty) {
            // Existing User!
            const userData = snapshot.docs[0].data();

            // Check if login method matches
            if (userData.loginMethod !== loginMethod) {
                try {
                    // Forcefully delete the newly spawned duplicate account from Firebase Auth to keep the console clean!
                    if (uid !== userData.userId) {
                        await getAuth().deleteUser(uid);
                    }
                } catch (e) {
                    console.error("Failed to purge duplicate Firebase user", e);
                }
                return res.status(400).json({ error: `Your ${loginMethod} account's linked email is already registered. Please login using your ${userData.loginMethod} account.` });
            }

            const requireProfileComplete = !userData.phoneNumber || userData.phoneNumber === "";

            if (userData.role === "Admin" && clientType === "Mobile") {
                return res.status(403).json({ error: "Admin access is constrained to the Web portal." });
            }

            return res.status(200).json({ success: true, message: `Login successful through ${loginMethod}`, email: userData.email, name: userData.fullName, requireProfileComplete, role: userData.role });
        } else {
            if (!email && !phone) {
                return res.status(400).json({ error: "Your social account does not have a bound Email or Phone Number. Please link one to your account to proceed." });
            }

            // New OAuth User! Create profile.
            const newUser = new Customer({
                fullName: name,
                email: email || "",
                phoneNumber: phone || "",
                loginMethod: loginMethod || "OAuth"
            });
            newUser.userId = uid; // override the uuidv4 with the actual firebase UID

            await db.collection("users").doc(uid).set(newUser.toJSON());
            return res.status(200).json({ success: true, message: `Login successful through ${loginMethod}`, email: newUser.email, name, phone, requireProfileComplete: true, role: newUser.role });
        }
    } catch (err) {
        console.error(err);
        return res.status(401).json({ error: "Unauthorized OAuth Token" });
    }
});

// Firebase rejects OAuth sign-in for disabled users before it can issue an
// ID token. Let the client ask for only the blocked customer's status by the
// email confirmed by their OAuth provider, without exposing profile details.
router.post("/account-access-status", async (req, res) => {
    const email = typeof req.body.email === "string" ? req.body.email.trim().toLowerCase() : "";
    if (!email) return res.status(400).json({ error: "Email is required." });
    try {
        const usersRef = db.collection("users");
        let snapshot = await usersRef.where("email", "==", email).limit(1).get();
        if (snapshot.empty) {
            snapshot = await usersRef.where("email", "==", req.body.email.trim()).limit(1).get();
        }
        if (!snapshot.empty) {
            const account = snapshot.docs[0].data();
            const role = String(account.role || account.systemRole || "").trim().toLowerCase();
            const status = String(account.status || "").trim().toLowerCase();
            if (role === "customer" && ["suspended", "banned"].includes(status)) {
                return res.status(200).json({ status: status === "suspended" ? "Suspended" : "Banned" });
            }
        }
        return res.status(200).json({ status: null });
    } catch (err) {
        console.error("Could not check OAuth account access status:", err.message);
        return res.status(500).json({ error: "Could not check account status." });
    }
});

router.post("/login", async (req, res) => {
    const { email, password, clientType } = req.body;
    const emailValidation = validateEmail(email);
    if (!emailValidation.isValid) return res.status(400).json({ error: emailValidation.message });

    try {
        // PRE-CHECK: Intercept Google/Facebook email usage natively instead of raw FIREBASE errors globally
        const snapshot = await db.collection("users").where("email", "==", email).get();
        if (snapshot.empty) {
            return res.status(404).json({ error: "Please register an account first." });
        } else {
            const registeredMethod = snapshot.docs[0].data().loginMethod;
            if (registeredMethod && registeredMethod !== "Email") {
                return res.status(400).json({ error: `Your email address is registered at ${registeredMethod}. Please login using ${registeredMethod}.` });
            }
        }

        const FIREBASE_API_KEY = "AIzaSyA8MQf-isqvndby6N6k2bfbD-KagiawFNE";
        const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_API_KEY}`;
        const verifyResponse = await fetch(url, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ email: email, password: password, returnSecureToken: true }),
        });
        const data = await verifyResponse.json();

        if (!verifyResponse.ok) {
            let errorMsg = "Login failed";
            if (data.error && data.error.message) {
                if (data.error.message === "USER_DISABLED") {
                    const account = snapshot.docs[0]?.data() || {};
                    const role = String(account.role || account.systemRole || "").trim().toLowerCase();
                    const status = String(account.status || "").trim().toLowerCase();
                    if (role === "customer" && ["suspended", "banned"].includes(status)) {
                        const accountStatus = status === "suspended" ? "Suspended" : "Banned";
                        const statusMessage = status === "suspended"
                            ? "Your account is being suspended. Please view the email for more detail."
                            : "Your account is being banned. Please view the email for more detail.";
                        return res.status(403).json({ status: accountStatus, error: statusMessage });
                    }
                    errorMsg = "This account has been archived. Please contact administrator.";
                } else if (data.error.message === "EMAIL_NOT_FOUND" || data.error.message === "INVALID_LOGIN_CREDENTIALS") {
                    errorMsg = "Incorrect email or password";
                } else {
                    errorMsg = data.error.message;
                }
            }
            return res.status(400).json({ error: errorMsg });
        }

        let fullName = "ReByte User";
        let role = "Customer";
        if (!snapshot.empty) {
            const userData = snapshot.docs[0].data();
            fullName = userData.fullName || "ReByte User";
            role = userData.role || "Customer";
            if (role === "Admin" && clientType === "Mobile") {
                return res.status(403).json({ error: "Admin access is constrained to the Web portal." });
            }
        }

        return res.status(200).json({ message: "Login successful", token: data.idToken, uid: data.localId, name: fullName, role: role });
    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: "Internal Server Error connecting to Identity Toolkit" });
    }
});

router.post("/get-profile", async (req, res) => {
    const { email } = req.body;
    if (!email) return res.status(400).json({ error: "Email is required" });

    try {
        const snapshot = await db.collection("users").where("email", "==", email).get();
        if (snapshot.empty) return res.status(404).json({ error: "User not found" });

        return res.status(200).json({ success: true, data: snapshot.docs[0].data() });
    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: "Failed to fetch profile" });
    }
});

router.post("/change-password", async (req, res) => {
    const { email, currentPassword, newPassword } = req.body;
    if (!email || !currentPassword || !newPassword) return res.status(400).json({ error: "Missing required fields" });

    try {
        const FIREBASE_API_KEY = "AIzaSyA8MQf-isqvndby6N6k2bfbD-KagiawFNE";
        const url = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_API_KEY}`;

        // Verify current password via REST
        let fetchParams;
        if (typeof fetch === 'undefined') {
            fetchParams = require('node-fetch')(url, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ email, password: currentPassword, returnSecureToken: true })
            });
        } else {
            fetchParams = fetch(url, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ email, password: currentPassword, returnSecureToken: true })
            });
        }

        const response = await fetchParams;
        const data = await response.json();

        if (data.error) {
            return res.status(400).json({ error: "Incorrect current password" });
        }
        if (currentPassword === newPassword) {
            return res.status(400).json({ error: "New password cannot be the same as current password." });
        }
        const passwordValidation = validatePassword(newPassword);
        if (!passwordValidation.isValid) return res.status(400).json({ error: passwordValidation.message });

        // Successfully verified! Apply the password change using Admin SDK
        await getAuth().updateUser(data.localId, { password: newPassword });
        await getAuth().revokeRefreshTokens(data.localId);

        // Issue a fresh token after the credential update so staff session checks
        // do not mistake a stale token for an archived account.
        let refreshedParams;
        if (typeof fetch === 'undefined') {
            refreshedParams = require('node-fetch')(url, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ email, password: newPassword, returnSecureToken: true })
            });
        } else {
            refreshedParams = fetch(url, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ email, password: newPassword, returnSecureToken: true })
            });
        }
        const refreshedResponse = await refreshedParams;
        const refreshedData = await refreshedResponse.json();
        if (!refreshedResponse.ok || refreshedData.error) {
            return res.status(200).json({ success: true, message: "Password updated successfully" });
        }

        return res.status(200).json({ success: true, message: "Password updated successfully", idToken: refreshedData.idToken });
    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: "Failed to update password" });
    }
});


router.get("/staff-list", requireAdmin, async (req, res) => {
    try {
        const usersRef = db.collection("users");
        // Get both Staff and Admin if possible, or just anyone with staffNo
        const snapshot = await usersRef.get();
        const staffList = [];
        snapshot.forEach(doc => {
            const data = doc.data();
            const isStaff = [data.role, data.systemRole]
                .some(role => typeof role === "string" && role.trim().toLowerCase() === "staff");
            if (isStaff || data.staffNo) {
                staffList.push({
                    id: doc.id,
                    ...data
                });
            }
        });
        
        // Sort by created date descending (newest first)
        staffList.sort((a, b) => {
           const timeA = a.createdAt ? a.createdAt._seconds : 0;
           const timeB = b.createdAt ? b.createdAt._seconds : 0;
           return timeB - timeA;
        });
        
        return res.status(200).json(staffList);
    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: "Internal Server Error" });
    }
});

router.post("/staff/:staffId/archive", requireAdmin, async (req, res) => {
    try {
        const staffRef = db.collection("users").doc(req.params.staffId);
        const staffDoc = await staffRef.get();
        if (!staffDoc.exists) return res.status(404).json({ error: "Staff account not found." });
        const staffData = staffDoc.data();
        const role = String(staffData.role || staffData.systemRole || "").trim().toLowerCase();
        if (role !== "staff" && !staffData.staffNo) return res.status(404).json({ error: "Staff account not found." });
        if (String(staffData.status || "active").trim().toLowerCase() === "archived") {
            return res.status(409).json({ error: "This staff account is already archived." });
        }

        const authUid = staffData.userId || staffDoc.id;
        const authUser = await getAuth().getUser(authUid);
        await getAuth().updateUser(authUid, { disabled: true });
        try {
            await getAuth().revokeRefreshTokens(authUid);
            await staffRef.update({ status: "Archived", archivedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
        } catch (archiveError) {
            await getAuth().updateUser(authUid, { disabled: authUser.disabled }).catch(rollbackError => {
                console.error("Could not restore staff account state after archive failure:", rollbackError);
            });
            throw archiveError;
        }

        return res.status(200).json({ success: true, message: "Staff member archived and signed out." });
    } catch (err) {
        if (err.code === "auth/user-not-found") return res.status(404).json({ error: "Staff sign-in account was not found." });
        console.error("Staff archive failed:", err);
        return res.status(500).json({ error: "Could not archive the staff account." });
    }
});

router.post("/staff/:staffId/restore", requireAdmin, async (req, res) => {
    try {
        const staffRef = db.collection("users").doc(req.params.staffId);
        const staffDoc = await staffRef.get();
        if (!staffDoc.exists) return res.status(404).json({ error: "Staff account not found." });
        const staffData = staffDoc.data();
        const role = String(staffData.role || staffData.systemRole || "").trim().toLowerCase();
        if (role !== "staff" && !staffData.staffNo) return res.status(404).json({ error: "Staff account not found." });
        if (String(staffData.status || "active").trim().toLowerCase() !== "archived") {
            return res.status(409).json({ error: "This staff account is not archived." });
        }

        const authUid = staffData.userId || staffDoc.id;
        const authUser = await getAuth().getUser(authUid);
        await getAuth().updateUser(authUid, { disabled: false });
        try {
            await staffRef.update({
                status: "Active",
                archivedAt: FieldValue.delete(),
                updatedAt: FieldValue.serverTimestamp()
            });
        } catch (restoreError) {
            await getAuth().updateUser(authUid, { disabled: authUser.disabled }).catch(rollbackError => {
                console.error("Could not restore staff account state after restore failure:", rollbackError);
            });
            throw restoreError;
        }

        return res.status(200).json({ success: true, message: "Staff member restored. They must sign in again." });
    } catch (err) {
        if (err.code === "auth/user-not-found") return res.status(404).json({ error: "Staff sign-in account was not found." });
        console.error("Staff restore failed:", err);
        return res.status(500).json({ error: "Could not restore the staff account." });
    }
});

router.delete("/staff/:staffId", requireAdmin, async (req, res) => {
    try {
        const staffRef = db.collection("users").doc(req.params.staffId);
        const staffDoc = await staffRef.get();
        if (!staffDoc.exists) return res.status(404).json({ error: "Staff account not found." });
        const staffData = staffDoc.data();
        const role = String(staffData.role || staffData.systemRole || "").trim().toLowerCase();
        if (role !== "staff" && !staffData.staffNo) return res.status(404).json({ error: "Staff account not found." });
        if (String(staffData.status || "active").trim().toLowerCase() !== "archived") {
            return res.status(409).json({ error: "Only archived staff accounts can be permanently deleted." });
        }

        const authUid = staffData.userId || staffDoc.id;
        try {
            await getAuth().deleteUser(authUid);
        } catch (authError) {
            // Permit retry if Auth deletion succeeded but the Firestore delete failed.
            if (authError.code !== "auth/user-not-found") throw authError;
        }
        await staffRef.delete();

        return res.status(200).json({ success: true, message: "Staff member permanently deleted." });
    } catch (err) {
        console.error("Permanent staff deletion failed:", err);
        return res.status(500).json({ error: "Could not permanently delete this staff account." });
    }
});

router.patch("/staff/:staffId", requireAdmin, async (req, res) => {
    const { fullName, phoneNumber, position, specialization } = req.body;
    const normalizedName = typeof fullName === "string" ? fullName.trim() : "";
    if (!/^[A-Za-z]+(?:\s+[A-Za-z]+)*$/.test(normalizedName)) {
        return res.status(400).json({ error: "Full name can contain letters and spaces only." });
    }

    let phoneDigits = String(phoneNumber || "").replace(/\D/g, "");
    if (phoneDigits.startsWith("60")) phoneDigits = phoneDigits.slice(2);
    const expectedPhoneLength = phoneDigits.startsWith("11") ? 10 : 9;
    if (!/^1\d+$/.test(phoneDigits) || phoneDigits.length !== expectedPhoneLength) {
        return res.status(400).json({ error: "Please enter a valid Malaysian mobile number." });
    }

    if (!["Inspector", "Deliverer", "Both"].includes(position)) {
        return res.status(400).json({ error: "Please select a valid staff position." });
    }
    const allowedSpecializations = ["Apple", "Samsung", "Xiaomi", "Huawei", "Oppo", "Vivo", "Google Pixel", "OnePlus"];
    const selectedSpecializations = Array.isArray(specialization) ? specialization : [];
    const uniqueSpecializations = [...new Set(selectedSpecializations)];
    if (uniqueSpecializations.length !== selectedSpecializations.length ||
        selectedSpecializations.some(value => !allowedSpecializations.includes(value)) ||
        (position === "Deliverer" && selectedSpecializations.length !== 0) ||
        (position !== "Deliverer" && (selectedSpecializations.length < 1 || selectedSpecializations.length > 3))) {
        return res.status(400).json({ error: "Choose between 1 and 3 device specializations for Inspector or Both roles. Deliverers do not have device specialization." });
    }

    try {
        const staffRef = db.collection("users").doc(req.params.staffId);
        const staffDoc = await staffRef.get();
        if (!staffDoc.exists) return res.status(404).json({ error: "Staff account not found." });
        const currentStaff = staffDoc.data();
        const currentRole = String(currentStaff.role || currentStaff.systemRole || "").trim().toLowerCase();
        if (currentRole !== "staff" && !currentStaff.staffNo) {
            return res.status(404).json({ error: "Staff account not found." });
        }

        const updatedFields = {
            fullName: normalizedName,
            phoneNumber: `+60${phoneDigits}`,
            position,
            specialization: position === "Deliverer" ? [] : selectedSpecializations,
            updatedAt: FieldValue.serverTimestamp()
        };
        await staffRef.update(updatedFields);

        const authUid = currentStaff.userId || staffDoc.id;
        try {
            await getAuth().updateUser(authUid, { displayName: normalizedName });
        } catch (authError) {
            console.warn("Staff record updated, but Firebase Auth display name could not be synchronized:", authError.message);
        }

        return res.status(200).json({ success: true, message: "Staff information updated successfully." });
    } catch (err) {
        console.error("Staff update failed:", err);
        return res.status(500).json({ error: "Failed to update staff information." });
    }
});

router.get("/customer-list", requireAdmin, async (req, res) => {
    try {
        await reactivateExpiredCustomerSuspensions();
        const snapshot = await db.collection("users").get();
        const customers = [];
        snapshot.forEach(doc => {
            const data = doc.data();
            const role = String(data.role || data.systemRole || "").trim().toLowerCase();
            if (role !== "customer") return;
            customers.push({ ...data, id: doc.id });
        });
        customers.sort((a, b) => {
            const timeA = a.createdAt?._seconds || 0;
            const timeB = b.createdAt?._seconds || 0;
            return timeB - timeA;
        });
        return res.status(200).json(customers);
    } catch (err) {
        console.error("Could not load customer records:", err);
        return res.status(500).json({ error: "Could not load customer records." });
    }
});

router.post("/customers/:customerId/status", requireAdmin, async (req, res) => {
    const requestedStatus = String(req.body.status || "").trim();
    if (!["Active", "Suspended", "Banned"].includes(requestedStatus)) {
        return res.status(400).json({ error: "Choose a valid customer status." });
    }
    const reason = typeof req.body.reason === "string" ? req.body.reason.trim() : "";
    const notifyByEmail = req.body.notifyByEmail === true;
    if (["Suspended", "Banned"].includes(requestedStatus) && !reason) {
        return res.status(400).json({ error: "Please provide a reason for this account action." });
    }
    if (["Suspended", "Banned"].includes(requestedStatus) && reason.split(/\s+/).filter(Boolean).length > 30) {
        return res.status(400).json({ error: "The reason must be 30 words or fewer." });
    }

    try {
        const customerRef = db.collection("users").doc(req.params.customerId);
        const customerDoc = await customerRef.get();
        if (!customerDoc.exists) return res.status(404).json({ error: "Customer account not found." });
        const customer = customerDoc.data();
        const role = String(customer.role || customer.systemRole || "").trim().toLowerCase();
        if (role !== "customer") return res.status(404).json({ error: "Customer account not found." });

        const authUid = customer.userId || customerDoc.id;
        const authUser = await getAuth().getUser(authUid);
        const shouldDisable = requestedStatus !== "Active";
        const suspendedUntil = requestedStatus === "Suspended"
            ? new Date(Date.now() + CUSTOMER_SUSPENSION_MS)
            : null;
        const updates = { status: requestedStatus, updatedAt: FieldValue.serverTimestamp() };
        if (requestedStatus === "Suspended") {
            updates.suspensionReason = reason;
            updates.suspendedAt = FieldValue.serverTimestamp();
            updates.suspendedUntil = suspendedUntil;
            updates.banReason = FieldValue.delete();
            updates.bannedAt = FieldValue.delete();
        } else if (requestedStatus === "Banned") {
            updates.banReason = reason;
            updates.bannedAt = FieldValue.serverTimestamp();
            updates.suspensionReason = FieldValue.delete();
            updates.suspendedAt = FieldValue.delete();
            updates.suspendedUntil = FieldValue.delete();
        } else {
            updates.suspensionReason = FieldValue.delete();
            updates.suspendedAt = FieldValue.delete();
            updates.suspendedUntil = FieldValue.delete();
            updates.banReason = FieldValue.delete();
            updates.bannedAt = FieldValue.delete();
        }

        // Persist the restriction before disabling/revoking Firebase tokens.
        // Otherwise a concurrent mobile/web session poll can see a disabled
        // account with the old Active Firestore status and log out with a
        // generic session-expired toast before the real status is recorded.
        await customerRef.update(updates);
        try {
            await getAuth().updateUser(authUid, { disabled: shouldDisable });
            if (shouldDisable) await getAuth().revokeRefreshTokens(authUid);
        } catch (statusError) {
            const statusFields = ["status", "suspensionReason", "suspendedAt", "suspendedUntil", "banReason", "bannedAt", "updatedAt"];
            const rollback = {};
            for (const field of statusFields) {
                rollback[field] = Object.prototype.hasOwnProperty.call(customer, field)
                    ? customer[field]
                    : FieldValue.delete();
            }
            await customerRef.update(rollback).catch(rollbackError => {
                console.error("Could not restore customer status after Firebase update failure:", rollbackError);
            });
            await getAuth().updateUser(authUid, { disabled: authUser.disabled }).catch(rollbackError => {
                console.error("Could not restore customer account state after status update failure:", rollbackError);
            });
            throw statusError;
        }

        let message = requestedStatus === "Suspended"
            ? "Customer suspended for 7 days. The account will reactivate automatically."
            : requestedStatus === "Banned"
                ? "Customer banned until an administrator unbans the account."
                : String(customer.status || "").toLowerCase() === "banned"
                    ? "Customer unbanned and access restored."
                    : "Customer reactivated and access restored.";
        let auditLogged = true;
        const action = requestedStatus === "Suspended" ? "Suspended"
            : requestedStatus === "Banned" ? "Banned"
                : String(customer.status || "").toLowerCase() === "banned" ? "Unbanned" : "Reactivated";
        try {
            await db.collection("customerAccountAudit").add({
                customerId: customerDoc.id,
                userId: authUid,
                customerName: customer.fullName || "Customer",
                email: customer.email || "",
                action,
                reason,
                ...(suspendedUntil ? { suspendedUntil } : {}),
                performedBy: req.adminUid || "admin",
                createdAt: FieldValue.serverTimestamp()
            });
        } catch (auditError) {
            auditLogged = false;
            message += " The account status changed, but the audit record could not be saved.";
            console.error("Customer status audit record could not be saved:", auditError.message);
        }
        let notificationSent = null;
        if (notifyByEmail && ["Suspended", "Banned"].includes(requestedStatus) && customer.email) {
            try {
                await sendCustomerStatusEmail(customer, requestedStatus, reason);
                notificationSent = true;
            } catch (mailError) {
                notificationSent = false;
                message += " The status changed, but the email notice could not be sent.";
                console.error("Customer status email could not be sent:", mailError.message);
            }
        }
        return res.status(200).json({ success: true, message, notificationSent, auditLogged });
    } catch (err) {
        if (err.code === "auth/user-not-found") return res.status(404).json({ error: "Customer sign-in account was not found." });
        console.error("Customer status update failed:", err);
        return res.status(500).json({ error: "Could not update this customer account." });
    }
});

// Run an expiry sweep in the long-lived Express process; listing customers also
// runs the same sweep so overdue suspensions are corrected on the next admin load.
const suspensionExpiryTimer = setInterval(() => {
    void reactivateExpiredCustomerSuspensions();
}, 60 * 1000);
suspensionExpiryTimer.unref?.();
void reactivateExpiredCustomerSuspensions();

module.exports = router;
