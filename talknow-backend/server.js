import express from "express";
import http from "http";
import { Server } from "socket.io";
import { v4 as uuidv4 } from "uuid";
import cors from "cors";

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: "*" },
});

let meetings = {};

app.use(cors());
app.use(express.json());

// Create a meeting
app.post("/create-meeting", (req, res) => {
  const meetingId = uuidv4();
  meetings[meetingId] = { participants: [] };
  res.json({ meetingId });
});

// Join a meeting
app.post("/join-meeting", (req, res) => {
  const { meetingId, username } = req.body;
  if (!meetings[meetingId]) {
    return res.status(404).json({ error: "Meeting not found" });
  }
  meetings[meetingId].participants.push(username);
  res.json({ success: true });
});

// WebSocket for real-time
io.on("connection", (socket) => {
  console.log("User connected");

  socket.on("joinRoom", (meetingId, username) => {
    socket.join(meetingId);
    io.to(meetingId).emit("newParticipant", username);
  });

  socket.on("sendMessage", (meetingId, message) => {
    io.to(meetingId).emit("receiveMessage", message);
  });

  socket.on("disconnect", () => {
    console.log("User disconnected");
  });
});

server.listen(5000, () => console.log("✅ Server running on port 5000"));
