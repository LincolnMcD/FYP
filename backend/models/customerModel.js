const User = require('./userModel');
const { Timestamp } = require("firebase-admin/firestore");

class Customer extends User {
    constructor({ fullName, email, phoneNumber, loginMethod, birthDate, gender }) {
        super({ fullName, email, phoneNumber, loginMethod });
        
        if (birthDate) {
            const dateObj = new Date(birthDate);
            this.birthDate = Timestamp.fromDate(dateObj);
        } else {
            this.birthDate = null;
        }

        this.gender = gender || 'Not Specified';
        this.role = 'Customer';
    }

    toJSON() {
        const base = super.toJSON();
        return {
            ...base,
            birthDate: this.birthDate,
            gender: this.gender,
            role: this.role,
        };
    }
}

module.exports = Customer;
