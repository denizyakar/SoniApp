const path = require('path');
const fs = require('fs');
const multer = require('multer');

// --- Chat Image Upload ---
const chatUploadDir = path.join(__dirname, '..', 'uploads/messages');
if (!fs.existsSync(chatUploadDir)) {
    fs.mkdirSync(chatUploadDir, { recursive: true });
}

const chatStorage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, chatUploadDir);
    },
    filename: (req, file, cb) => {
        const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
        cb(null, uniqueSuffix + '.jpg');
    }
});
const chatUpload = multer({ storage: chatStorage });

// --- Avatar Upload ---
const uploadDir = path.join(__dirname, '..', 'uploads/avatars');
if (!fs.existsSync(uploadDir)) {
    fs.mkdirSync(uploadDir, { recursive: true });
}

const avatarStorage = multer.diskStorage({
    destination: function (req, file, cb) {
        cb(null, uploadDir)
    },
    filename: function (req, file, cb) {
        cb(null, req.params.userId + '.jpg')
    }
});
const avatarUpload = multer({ storage: avatarStorage });

module.exports = { chatUpload, avatarUpload };
