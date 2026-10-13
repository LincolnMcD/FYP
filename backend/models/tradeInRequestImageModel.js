const { v4: uuidv4 } = require('uuid');
const { FieldValue } = require("firebase-admin/firestore");

class TradeInRequestImage {
    constructor({
        imageID,
        imageUrl,
        imageView,
        uploadedAt,
        tradeInRequestID
    }) {
        this.imageID = imageID || `IMG-${uuidv4().substring(0, 8).toUpperCase()}`;
        this.imageUrl = imageUrl;
        this.imageView = imageView; // front, back, left_side, right_side, screen_open, screen_closed, camera_area, any_angles
        this.uploadedAt = uploadedAt || FieldValue.serverTimestamp();
        this.tradeInRequestID = tradeInRequestID;
    }

    toJSON() {
        return {
            imageID: this.imageID,
            imageUrl: this.imageUrl,
            imageView: this.imageView,
            uploadedAt: this.uploadedAt,
            tradeInRequestID: this.tradeInRequestID,
        };
    }
}

module.exports = TradeInRequestImage;
