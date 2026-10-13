const { FieldValue } = require("firebase-admin/firestore");

class TradeInRequest {
    constructor({
        tradeInRequestID,
        tradeInId,
        requestStatus = 'Pending',
        status,
        submittedAt,
        deviceID,
        userEmail = null,
    }) {
        this.tradeInRequestID = tradeInRequestID || tradeInId;
        this.requestStatus = requestStatus || status || 'Pending';
        this.submittedAt = submittedAt || FieldValue.serverTimestamp();
        this.deviceID = deviceID;
        this.userEmail = userEmail;
    }

    toJSON() {
        return {
            tradeInRequestID: this.tradeInRequestID,
            requestStatus: this.requestStatus,
            submittedAt: this.submittedAt,
            deviceID: this.deviceID,
            userEmail: this.userEmail,
        };
    }
}

module.exports = TradeInRequest;
