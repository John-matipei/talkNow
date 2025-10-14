import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:share_plus/share_plus.dart';
import 'package:fluttertoast/fluttertoast.dart';

// ✅ Define your backend IP here
const backendIP = '192.168.0.107'; // Replace with your PC LAN IP

void main() {
  runApp(const TalkNowApp());
}

class TalkNowApp extends StatelessWidget {
  const TalkNowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Talk Now',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const MeetingHomePage(),
    );
  }
}

class MeetingHomePage extends StatefulWidget {
  const MeetingHomePage({super.key});

  @override
  State<MeetingHomePage> createState() => _MeetingHomePageState();
}

class _MeetingHomePageState extends State<MeetingHomePage> {
  final roomController = TextEditingController();
  final usernameController = TextEditingController();
  final commentController = TextEditingController();
  final List<String> comments = [];

  late IO.Socket socket;
  String? meetingId;
  bool meetingActive = false;
  String? meetingLink;

  @override
  void initState() {
    super.initState();
    connectSocket();
  }

  void connectSocket() {
    socket = IO.io(
      'http://$backendIP:5000', // Use backendIP constant
      IO.OptionBuilder().setTransports(['websocket']).build(),
    );

    socket.onConnect((_) {
      print('Connected to Socket Server ✅');
    });

    socket.on('newParticipant', (username) {
      Fluttertoast.showToast(msg: "👋 $username joined the meeting");
    });

    socket.on('receiveMessage', (message) {
      setState(() {
        comments.add(message);
      });
    });
  }

  Future<void> createMeeting() async {
    final response =
    await http.post(Uri.parse('http://$backendIP:5000/create-meeting'));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        meetingId = data['meetingId'];
        meetingLink = "http://$backendIP:5000/meeting/$meetingId";
        meetingActive = true;
      });
      Fluttertoast.showToast(msg: "✅ Meeting created!");
    }
  }

  Future<void> joinMeeting() async {
    final id = roomController.text.trim();
    final username = usernameController.text.trim();

    if (id.isEmpty || username.isEmpty) {
      Fluttertoast.showToast(msg: "Enter Meeting ID and Username");
      return;
    }

    final response = await http.post(
      Uri.parse('http://$backendIP:5000/join-meeting'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'meetingId': id, 'username': username}),
    );

    if (response.statusCode == 200) {
      socket.emit('joinRoom', {'meetingId': id, 'username': username});

      setState(() {
        meetingId = id;
        meetingLink = "http://$backendIP:5000/meeting/$id";
        meetingActive = true;
      });
      Fluttertoast.showToast(msg: "✅ Joined meeting successfully!");
    } else {
      Fluttertoast.showToast(msg: "❌ Meeting not found!");
    }
  }

  void sendMessage() {
    final msg = commentController.text.trim();
    if (msg.isEmpty || meetingId == null) return;

    socket.emit('sendMessage', {'meetingId': meetingId, 'message': msg});

    setState(() {
      comments.add("Me: $msg");
      commentController.clear();
    });
  }

  void endMeeting() {
    socket.disconnect();
    setState(() {
      meetingActive = false;
      meetingId = null;
      meetingLink = null;
      comments.clear();
    });
    Fluttertoast.showToast(msg: "❌ Meeting ended.");
  }

  void shareMeetingLink() {
    if (meetingLink != null) {
      Share.share("Join my meeting: $meetingLink");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Talk Now"),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: !meetingActive
            ? Column(
          children: [
            TextField(
              controller: usernameController,
              decoration: InputDecoration(
                labelText: "Your Name",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                labelStyle: const TextStyle(color: Colors.black),
              ),
              style: const TextStyle(color: Colors.black),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: roomController,
              decoration: InputDecoration(
                labelText: "Meeting ID (optional to join existing)",
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                labelStyle: const TextStyle(color: Colors.black),
              ),
              style: const TextStyle(color: Colors.black),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: createMeeting,
              icon: const Icon(Icons.video_call),
              label: const Text("Create Meeting"),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: joinMeeting,
              icon: const Icon(Icons.meeting_room),
              label: const Text("Join Meeting"),
              style:
              ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            ),
          ],
        )
            : Column(
          children: [
            Text("Meeting ID: $meetingId"),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: shareMeetingLink,
              icon: const Icon(Icons.link),
              label: const Text("Share Meeting Link"),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: endMeeting,
              icon: const Icon(Icons.call_end),
              label: const Text("End Meeting"),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: comments.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(comments[index]),
                  );
                },
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: commentController,
                    decoration: const InputDecoration(
                      hintText: "Type message...",
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    style: const TextStyle(color: Colors.black),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.teal),
                  onPressed: sendMessage,
                )
              ],
            )
          ],
        ),
      ),
    );
  }
}
