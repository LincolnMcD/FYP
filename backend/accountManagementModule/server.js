const express = require("express");
const cors = require("cors");
const { getAuth } = require("firebase-admin/auth");
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
const { Customer } = require("./models");
const db = require("../config/firebase");

const app = express();
app.use(express.json());
app.use(cors());

app.post("/request-otp", async (req, res) => {
    const { email } = req.body;
    if (!email) return res.status(400).json({ error: "Email is required" });

    try {
        const usersRef = db.collection("users");
        const snapshot = await usersRef.where("email", "==", email).get();
        if (!snapshot.empty) {
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

app.post("/register", async (req, res) => {
    // RE-ARCHITECTED: ONLY REQUIRE EMAIL, PASSWORD, and OTP!
    const { email, password, otp } = req.body;

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
        if (!snapshot.empty) return res.status(400).json({ error: "Email is already registered" });

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

        // Save initial incomplete schema 
        await usersRef.doc(userRecord.uid).set({
            birthDate: null,
            createdAt: new Date().toISOString(),
            email: email,
            fullName: "",
            gender: "Not Specified",
            loginMethod: "Email",
            phoneNumber: "",
            role: "Customer",
            status: "Active",
            updatedAt: new Date().toISOString(),
            userId: userRecord.uid
        });

        return res.status(200).json({ message: "Registration successful" });
    } catch (err) {
        if (err.code === "auth/email-already-exists") return res.status(400).json({ error: "Email is already registered" });
        console.error(err);
        return res.status(500).json({ error: "Internal Server Error connecting to Database" });
    }
});

app.post("/update-profile", async (req, res) => {
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
            updatedAt: new Date().toISOString()
        });

        return res.status(200).json({ message: "Profile updated successfully!" });
    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: "Failed to update profile" });
    }
});

app.post("/login", async (req, res) => {
    const { email, password } = req.body;
    const emailValidation = validateEmail(email);
    if (!emailValidation.isValid) return res.status(400).json({ error: emailValidation.message });

    try {
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

        const snapshot = await db.collection("users").where("email", "==", email).get();
        let fullName = "ReByte User";
        if (!snapshot.empty) {
            fullName = snapshot.docs[0].data().fullName || "ReByte User";
        }

        return res.status(200).json({ message: "Login successful", token: data.idToken, uid: data.localId, name: fullName });
    } catch (err) {
        console.error(err);
        return res.status(500).json({ error: "Internal Server Error connecting to Identity Toolkit" });
    }
});

const PORT = 3000;
app.listen(PORT, "0.0.0.0", () => {
    console.log(`Server running on port ${PORT}`);
});
