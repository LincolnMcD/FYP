const { v4: uuidv4 } = require('uuid');
const { FieldValue } = require("firebase-admin/firestore");

class TradeInRequest {
    constructor({
        tradeInId,
        userId = null,
        userEmail = null,
        deviceCategory = 'Smartphone',
        brand,
        model,
        storageCapacity,
        color,
        deviceAge,
        conditionAnswers = {},
        images = [],
        imei = null,
        selfTestResults = {},
        estimatedValue = 0,
        finalOfferedValue = 0,
        status = 'Draft'
    }) {
        this.tradeInId = tradeInId || uuidv4();
        this.userId = userId;
        this.userEmail = userEmail;
        this.deviceCategory = deviceCategory;
        this.brand = brand;
        this.model = model;
        this.storageCapacity = storageCapacity;
        this.color = color;
        this.deviceAge = deviceAge;
        this.conditionAnswers = conditionAnswers;
        this.images = images;
        this.imei = imei;
        this.selfTestResults = selfTestResults;
        this.estimatedValue = estimatedValue;
        this.finalOfferedValue = finalOfferedValue;
        this.status = status;
        this.createdAt = FieldValue.serverTimestamp();
        this.updatedAt = FieldValue.serverTimestamp();
    }

    toJSON() {
        return {
            tradeInId: this.tradeInId,
            userId: this.userId,
            userEmail: this.userEmail,
            deviceCategory: this.deviceCategory,
            brand: this.brand,
            model: this.model,
            storageCapacity: this.storageCapacity,
            color: this.color,
            deviceAge: this.deviceAge,
            conditionAnswers: this.conditionAnswers,
            images: this.images,
            imei: this.imei,
            selfTestResults: this.selfTestResults,
            estimatedValue: this.estimatedValue,
            finalOfferedValue: this.finalOfferedValue,
            status: this.status,
            createdAt: this.createdAt,
            updatedAt: this.updatedAt,
        };
    }
}

module.exports = TradeInRequest;
