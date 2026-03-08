const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const User = require('../models/User');
const { JWT_SECRET } = require('../middleware/auth');

// Register
router.post('/register', async (req, res) => {
    try {
        const { username, password } = req.body;

        const existingUser = await User.findOne({ username });
        if (existingUser) {
            return res.status(400).json({ message: "This username is already taken" });
        }

        const hashedPassword = await bcrypt.hash(password, 10);

        const newUser = new User({
            username,
            password: hashedPassword
        });

        await newUser.save();

        // Notify connected clients about new user
        const io = req.app.get('io');
        io.emit('user_registered', {
            id: newUser._id,
            username: newUser.username
        });

        res.status(201).json({ message: "User succesfully registered!" });

    } catch (error) {
        console.error("Register error(js):", error);
        res.status(500).json({ message: "Server error occurred(js)." });
    }
});

// Login
router.post('/login', async (req, res) => {
    try {
        const { username, password } = req.body;

        const user = await User.findOne({ username });
        if (!user) {
            return res.status(400).json({ message: "User could not be found!" });
        }

        const isMatch = await bcrypt.compare(password, user.password);
        if (!isMatch) {
            return res.status(400).json({ message: "Incorrect password" });
        }

        const token = jwt.sign(
            { userId: user._id, username: user.username },
            JWT_SECRET,
            { expiresIn: '365d' }
        );

        res.json({ token, userId: user._id, username: user.username });

    } catch (error) {
        console.error("Login Error:", error);
        res.status(500).json({ message: "Server error(js)." });
    }
});

module.exports = router;
