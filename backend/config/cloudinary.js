const cloudinary = require('cloudinary').v2;
require('dotenv').config();

cloudinary.config({
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME || 'spyhcckw',
    api_key: process.env.CLOUDINARY_API_KEY || '784437544564975',
    api_secret: process.env.CLOUDINARY_API_SECRET || 'NMkOybgxbjx41y4v4ncEWsGQK3Q',
    secure: true
});

module.exports = cloudinary;
