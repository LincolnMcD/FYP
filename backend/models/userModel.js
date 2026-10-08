const { v4: uuidv4 } = require('uuid');
const { FieldValue } = require("firebase-admin/firestore");

class User {
    constructor({ fullName, email, phoneNumber, loginMethod = 'Email' }) {
        this.userId = uuidv4();
        this.fullName = fullName;
        this.email = email;
        this.phoneNumber = phoneNumber;
        this.loginMethod = loginMethod;
        this.status = 'Active';
        this.createdAt = FieldValue.serverTimestamp();
        this.updatedAt = FieldValue.serverTimestamp();
    }

    toJSON() {
        return {
            userId: this.userId,
            fullName: this.fullName,
            email: this.email,
            phoneNumber: this.phoneNumber,
            loginMethod: this.loginMethod,
            status: this.status,
            createdAt: this.createdAt,
            updatedAt: this.updatedAt,
        };
    }
}

module.exports = User;
