const User = require('../models/User');
const Message = require('../models/Message');
const { sendPushNotification, sendVoipPushNotification } = require('../services/notificationService');

function setupSocketHandlers(io, onlineUsers, pendingOffers, pendingIceCandidates) {

    io.on('connection', (socket) => {
        console.log(' A user connected:', socket.id);

        // --- User Registration (maps userId -> socketId) ---
        socket.on("register", (userId) => {
            onlineUsers.set(userId, socket.id);
            console.log(`✅ User Registered: ${userId} -> ${socket.id}`);

            // Flush buffered ICE candidates
            if (pendingIceCandidates.has(userId)) {
                const candidates = pendingIceCandidates.get(userId);
                candidates.forEach(candidate => {
                    socket.emit("ice-candidate", { candidate });
                });
                console.log(`✨ ${candidates.length} buffered ICE candidate(s) flushed to User: ${userId}`);
                pendingIceCandidates.delete(userId);
            }
        });

        // --- Disconnect ---
        socket.on("disconnect", () => {
            for (let [userId, socketId] of onlineUsers.entries()) {
                if (socketId === socket.id) {
                    onlineUsers.delete(userId);
                    console.log(`❌ User Disconnected: ${userId}`);
                    break;
                }
            }
        });

        // ==========================================
        //              VIDEO CALL
        // ==========================================

        // 1. Call Request (Offer)
        socket.on("call-user", async (data) => {
            pendingOffers.set(data.to, {
                offer: data.offer,
                callerId: data.callerId,
                callerName: data.callerName,
                callerAvatarUrl: data.callerAvatarUrl
            });

            try {
                const targetUser = await User.findById(data.to);

                if (targetUser && targetUser.voipToken) {
                    sendVoipPushNotification(
                        targetUser.voipToken,
                        data.callerId,
                        data.callerName,
                        data.callerAvatarUrl
                    );
                    console.log(`📱 PushKit VoIP signal sent to User: ${data.to} (Token: ${targetUser.voipToken.substring(0, 10)}...)`);
                } else {
                    console.log(`⚠️ User ${data.to} has no voipToken in Database. CallKit will NOT ring.`);
                }
            } catch (error) {
                console.error("❌ Error fetching user from DB:", error);
            }

            const targetSocketId = onlineUsers.get(data.to);

            if (targetSocketId) {
                io.to(targetSocketId).emit("call-made", {
                    offer: data.offer,
                    callerId: data.callerId,
                    callerName: data.callerName,
                    callerAvatarUrl: data.callerAvatarUrl
                });
                console.log(`📞 Call emitted from ${data.callerName} to User: ${data.to}`);
            } else {
                console.log(`❌ Target User ${data.to} is offline from Socket. (But VoIP Push will wake them up!)`);
            }
        });

        // 2. Answer
        socket.on("answer-call", (data) => {
            const targetSocketId = onlineUsers.get(data.to);

            if (targetSocketId) {
                io.to(targetSocketId).emit("call-answered", {
                    answer: data.answer
                });
                console.log(`📞 Answer SDP successfully sent back to User: ${data.to}`);
            } else {
                console.log(`❌ Caller ${data.to} is offline (could not send answer).`);
            }
        });

        // 3. ICE Candidates
        socket.on("ice-candidate", (data) => {
            const targetSocketId = onlineUsers.get(data.to);

            if (targetSocketId) {
                io.to(targetSocketId).emit("ice-candidate", {
                    candidate: data.candidate
                });
                console.log(`✨ ICE Candidate routed to User: ${data.to}`);
            } else {
                if (!pendingIceCandidates.has(data.to)) {
                    pendingIceCandidates.set(data.to, []);
                }
                pendingIceCandidates.get(data.to).push(data.candidate);
                console.log(`✨ ICE Candidate BUFFERED for offline User: ${data.to} (${pendingIceCandidates.get(data.to).length} total)`);
            }
        });

        // 4. End Call
        socket.on("end-call", (data) => {
            const targetSocketId = onlineUsers.get(data.to);

            if (targetSocketId) {
                io.to(targetSocketId).emit("end-call", {});
                console.log(`📴 Call End signal immediately sent to User: ${data.to}`);
            }

            pendingOffers.delete(data.to);
            pendingIceCandidates.delete(data.to);
        });

        // 5. Camera Toggle
        socket.on('camera-toggled', (data) => {
            io.emit('camera-toggled', [data]);
        });

        // ==========================================
        //             MESSAGING
        // ==========================================

        socket.on('chat_message', async (data) => {
            console.log("📨 Message received:", data);

            try {
                const { text, senderId, receiverId, clientId, imageUrl } = data;

                const senderUser = await User.findById(senderId);
                const senderName = senderUser ? senderUser.username : '';

                const newMessage = new Message({
                    text,
                    senderId,
                    receiverId,
                    senderName,
                    clientId: clientId || null,
                    isRead: false,
                    readAt: null,
                    imageUrl: imageUrl || null,
                });

                const savedMessage = await newMessage.save();

                // Auto-add both users to each other's contacts
                await User.findByIdAndUpdate(senderId, { $addToSet: { contacts: receiverId } });
                await User.findByIdAndUpdate(receiverId, { $addToSet: { contacts: senderId } });

                const payload = {
                    _id: savedMessage._id.toString(),
                    text: savedMessage.text,
                    senderId: savedMessage.senderId.toString(),
                    receiverId: savedMessage.receiverId.toString(),
                    date: savedMessage.date.toISOString(),
                    senderName: savedMessage.senderName,
                    isRead: savedMessage.isRead,
                    readAt: savedMessage.readAt,
                    clientId: savedMessage.clientId,
                    imageUrl: savedMessage.imageUrl,
                };

                io.emit('receive_message', payload);

                // Push Notification
                try {
                    const receiverUser = await User.findById(receiverId);

                    if (receiverUser && receiverUser.deviceToken && senderId !== receiverId) {
                        console.log(`🔔 Triggering notification to: ${receiverUser.username} person...`);

                        sendPushNotification(
                            receiverUser.deviceToken,
                            senderName,
                            text || "An attachment was sent",
                            senderId
                        );
                    }
                } catch (notifError) {
                    console.log("⚠️ Non-critical notification error:", notifError.message);
                }

            } catch (err) {
                console.error("Message saving error:", err);
            }
        });

        // ==========================================
        //           PROFILE & READ RECEIPTS
        // ==========================================

        socket.on('profile_updated', (data) => {
            io.emit('profile_updated', data);
        });

        socket.on('mark_as_read', async (data) => {
            try {
                const { messageIds, readerId } = data;

                if (!messageIds || !Array.isArray(messageIds) || messageIds.length === 0) {
                    return;
                }

                const now = new Date();

                await Message.updateMany(
                    {
                        _id: { $in: messageIds },
                        receiverId: readerId,
                        isRead: false,
                    },
                    {
                        $set: {
                            isRead: true,
                            readAt: now,
                        },
                    }
                );

                const firstMessage = await Message.findById(messageIds[0]);
                if (firstMessage) {
                    io.emit('read_receipt', {
                        messageIds: messageIds,
                        readerId: readerId,
                        readAt: now.toISOString(),
                    });
                }

            } catch (err) {
                console.error('mark_as_read error:', err);
            }
        });

    }); // io.on('connection') ends
}

module.exports = setupSocketHandlers;
