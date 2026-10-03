const { v4: uuidv4 } = require('uuid');

class User {
    constructor({ fullName, email, phoneNumber, loginMethod = 'Email' }) {
        this.userId = uuidv4();
        this.fullName = fullName;
        this.email = email;
        this.phoneNumber = phoneNumber;
        this.loginMethod = loginMethod;
        this.status = 'Active';
        this.createdAt = new Date().toISOString();
        this.updatedAt = new Date().toISOString();
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

class Customer extends User {
    constructor({ fullName, email, phoneNumber, loginMethod, birthDate, gender }) {
        super({ fullName, email, phoneNumber, loginMethod });
        this.birthDate = birthDate || null;
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

module.exports = { User, Customer };
