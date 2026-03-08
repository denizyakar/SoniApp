const express = require('express');
const http = require('http');
const path = require('path');
const { Server } = require('socket.io');
const mongoose = require('mongoose');
const cors = require('cors');

// Shared state for video calls
const pendingOffers = new Map();
const pendingIceCandidates = new Map();
const onlineUsers = new Map();

// Import routes
const authRoutes = require('./routes/auth');
const usersRoutes = require('./routes/users');
const contactsRoutes = require('./routes/contacts');
const messagesRoutes = require('./routes/messages');
const tokensRoutes = require('./routes/tokens');
const callsRoutes = require('./routes/calls');

// Import socket handlers
const setupSocketHandlers = require('./socket/handlers');

// App setup
const app = express();
const server = http.createServer(app);
const port = 10000;
const uri = "YOUR_MONGODB_URI";

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));
app.use(express.static(path.join(__dirname, 'public')));
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// MongoDB
mongoose.connect(uri)
    .then(() => console.log('✅ MongoDB Connected!'))
    .catch(err => console.error('❌ MongoDB Error:', err));
mongoose.connection.setMaxListeners(30);

// Socket.IO
const io = new Server(server, {
    cors: {
        origin: "YOUR_DOMAIN",
        methods: ["GET", "POST"],
        credentials: true
    },
    transports: ['websocket', 'polling'],
    allowEIO3: true
});

// Share io and pendingOffers with routes (for register emit and pending calls)
app.set('io', io);
app.set('pendingOffers', pendingOffers);

// Mount routes
app.use('/', authRoutes);         // POST /login, POST /register
app.use('/users', usersRoutes);   // GET /users, profile CRUD
app.use('/contacts', contactsRoutes); // GET /contacts, POST /contacts/add, DELETE /contacts/remove
app.use('/messages', messagesRoutes); // GET /messages, POST /messages/upload
app.use('/', tokensRoutes);       // POST /update-token, /remove-token, /update-voip-token, /remove-voip-token
app.use('/', callsRoutes);        // GET /api/calls/pending/:userId

// Home page (browser)
app.get('/home', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'home.html'));
});

// Setup socket handlers
setupSocketHandlers(io, onlineUsers, pendingOffers, pendingIceCandidates);

// Start
server.listen(port, '0.0.0.0', () => {
    console.log(` System is live on port:${port} and YOUR_DOMAIN!`);
});
