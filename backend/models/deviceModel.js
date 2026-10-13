const { v4: uuidv4 } = require('uuid');
const { FieldValue } = require("firebase-admin/firestore");

class Device {
    constructor({
        deviceID,
        deviceCategory = 'smartphone',
        brand,
        model,
        modelCode = null,
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
        let codes = [];
        if (Array.isArray(modelCode)) {
            codes = modelCode.map(c => String(c).trim()).filter(Boolean);
        } else if (typeof modelCode === 'string' && modelCode.trim().length > 0) {
            codes = modelCode.split(',').map(c => c.trim()).filter(Boolean);
        }
        this.modelCode = codes.length > 0 ? codes : null;
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
            modelCode: this.modelCode, // Array of strings e.g. ["STK-L21", "STK-L22", "STK-LX3"]
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
