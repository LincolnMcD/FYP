const { v4: uuidv4 } = require('uuid');
const { FieldValue } = require("firebase-admin/firestore");

class Device {
    constructor({
        deviceID,
        deviceCategory = 'smartphone',
        brand,
        model,
        storageCapacity,
        colour,
        color,
        imeiNum = null,
        status = 'pending',
        deviceAge = null,
        userEmail = null
    }) {
        this.deviceID = deviceID || uuidv4();
        this.deviceCategory = deviceCategory || 'smartphone';
        this.brand = brand;
        this.model = model;
        this.storageCapacity = storageCapacity;
        this.colour = colour || color || '';
        this.imeiNum = imeiNum || null;
        this.status = status || 'pending';
        this.deviceAge = deviceAge || null;
        this.userEmail = userEmail || null;
        this.createdAt = FieldValue.serverTimestamp();
        this.updatedAt = FieldValue.serverTimestamp();
    }

    toJSON() {
        return {
            deviceID: this.deviceID,
            deviceCategory: this.deviceCategory,
            brand: this.brand,
            model: this.model,
            storageCapacity: this.storageCapacity,
            colour: this.colour,
            imeiNum: this.imeiNum,
            status: this.status,
            deviceAge: this.deviceAge,
            userEmail: this.userEmail,
            createdAt: this.createdAt,
            updatedAt: this.updatedAt,
        };
    }
}

module.exports = Device;
