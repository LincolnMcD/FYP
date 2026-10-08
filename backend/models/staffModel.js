const User = require('./userModel');

class Staff extends User {
    constructor({ fullName, email, phoneNumber, loginMethod, staffNo, specialization, position }) {
        super({ fullName, email, phoneNumber, loginMethod });
        
        this.staffNo = staffNo || '';
        // Ensure specialization is an array
        this.specialization = Array.isArray(specialization) ? specialization : (specialization ? [specialization] : []);
        this.position = position || '';
        this.role = 'Staff';
    }

    toJSON() {
        const base = super.toJSON();
        return {
            ...base,
            staffNo: this.staffNo,
            specialization: this.specialization,
            position: this.position,
            role: this.role,
        };
    }
}

module.exports = Staff;
