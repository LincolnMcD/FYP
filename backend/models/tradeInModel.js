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
        estimatedValue = null,
        ownershipProofImageUrl = null,
        finalOfferPrice = null,
    }) {
        this.tradeInRequestID = tradeInRequestID || tradeInId;
        this.requestStatus = requestStatus || status || 'Pending';
        this.submittedAt = submittedAt || FieldValue.serverTimestamp();
        this.deviceID = deviceID;
        this.userEmail = userEmail;
        this.ownershipProofImageUrl = ownershipProofImageUrl || null;
        this.finalOfferPrice = finalOfferPrice != null ? Number(finalOfferPrice) : null;

        if (estimatedValue) {
            let est = { min: 2340.50, max: 2355.30 };
            if (typeof estimatedValue === 'object') {
                const min = Number(estimatedValue.min != null ? estimatedValue.min : (estimatedValue.minEstimatedValue != null ? estimatedValue.minEstimatedValue : 2340.50));
                const max = Number(estimatedValue.max != null ? estimatedValue.max : (estimatedValue.maxEstimatedValue != null ? estimatedValue.maxEstimatedValue : 2355.30));
                est = {
                    min: isNaN(min) ? 2340.50 : Number(min.toFixed(2)),
                    max: isNaN(max) ? 2355.30 : Number(max.toFixed(2))
                };
            } else if (typeof estimatedValue === 'string') {
                const matches = estimatedValue.replace(/,/g, '').match(/\d+(?:\.\d+)?/g);
                if (matches && matches.length >= 2) {
                    est = {
                        min: Number(parseFloat(matches[0]).toFixed(2)),
                        max: Number(parseFloat(matches[1]).toFixed(2))
                    };
                } else if (matches && matches.length === 1) {
                    const val = Number(parseFloat(matches[0]).toFixed(2));
                    est = { min: val, max: val };
                }
            } else if (typeof estimatedValue === 'number') {
                const val = Number(estimatedValue.toFixed(2));
                est = { min: val, max: val };
            }
            this.estimatedValue = est;
        } else {
            this.estimatedValue = null;
        }
    }

    toJSON() {
        const data = {
            tradeInRequestID: this.tradeInRequestID,
            requestStatus: this.requestStatus,
            submittedAt: this.submittedAt,
            deviceID: this.deviceID,
            userEmail: this.userEmail,
        };
        if (this.ownershipProofImageUrl) {
            data.ownershipProofImageUrl = this.ownershipProofImageUrl;
        }
        if (this.finalOfferPrice != null) {
            data.finalOfferPrice = this.finalOfferPrice;
        }
        if (this.estimatedValue) {
            data.estimatedValue = this.estimatedValue;
        }
        return data;
    }
}

module.exports = TradeInRequest;
