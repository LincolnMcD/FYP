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
                if (data.error.message === "EMAIL_NOT_FOUND" || data.error.message === "INVALID_LOGIN_CREDENTIALS") {
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

    const passwordValidation = validatePassword(newPassword);
    if (!passwordValidation.isValid) return res.status(400).json({ error: passwordValidation.message });

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

        // Successfully verified! Apply the password change using Admin SDK
        await getAuth().updateUser(data.localId, { password: newPassword });

        return res.status(200).json({ success: true, message: "Password updated successfully" });
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
module.exports = router;
