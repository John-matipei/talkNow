import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:fluttertoast/fluttertoast.dart';

// ✅ Replace with your backend IP
const backendIP = '192.168.0.107';
final backendBaseUrl = 'http://$backendIP:5000';

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
        scaffoldBackgroundColor: const Color(0xFF0E0E10),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E1E2C),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Colors.deepPurple),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: Colors.purpleAccent, width: 2),
          ),
          labelStyle: const TextStyle(color: Colors.white70),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurpleAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
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

  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();

  late IO.Socket socket;
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  bool inMeeting = false;
  String? meetingId;

  @override
  void initState() {
    super.initState();
    localRenderer.initialize();
    remoteRenderer.initialize();
    connectSocket();
  }

  @override
  void dispose() {
    localRenderer.dispose();
    remoteRenderer.dispose();
    super.dispose();
  }

  void connectSocket() {
    socket = IO.io(
      backendBaseUrl,
      IO.OptionBuilder().setTransports(['websocket']).build(),
    );

    socket.onConnect((_) {
      print('✅ Connected to Socket Server');
    });

    socket.on('offer', (data) async {
      await _handleOffer(data);
    });

    socket.on('answer', (data) async {
      await peerConnection?.setRemoteDescription(
        RTCSessionDescription(data['sdp'], data['type']),
      );
    });

    socket.on('candidate', (data) async {
      await peerConnection?.addCandidate(
        RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']),
      );
    });
  }

  Future<void> _initLocalStream() async {
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {'facingMode': 'user'}
    });
    localRenderer.srcObject = localStream;
  }

  Future<void> _createPeerConnection(String roomId) async {
    peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ]
    });

    peerConnection!.onIceCandidate = (candidate) {
      if (candidate != null) {
        socket.emit('candidate', {
          'meetingId': roomId,
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
      }
    };

    localStream?.getTracks().forEach((track) {
      peerConnection!.addTrack(track, localStream!);
    });
  }

  Future<void> createMeeting() async {
    await _initLocalStream();

    final res = await http.post(Uri.parse('$backendBaseUrl/create-meeting'));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final id = data['meetingId'];
      setState(() {
        meetingId = id;
        inMeeting = true;
      });

      socket.emit('createRoom', {'meetingId': id});
      await _createPeerConnection(id);
      Fluttertoast.showToast(msg: '✅ Meeting created: $id');
    }
  }

  Future<void> joinMeeting() async {
    await _initLocalStream();

    final id = roomController.text.trim();
    final username = usernameController.text.trim();
    if (id.isEmpty || username.isEmpty) {
      Fluttertoast.showToast(msg: 'Enter meeting ID and username');
      return;
    }

    setState(() {
      meetingId = id;
      inMeeting = true;
    });

    socket.emit('joinRoom', {'meetingId': id, 'username': username});
    await _createPeerConnection(id);
  }

  Future<void> _handleOffer(Map data) async {
    await _createPeerConnection(data['meetingId']);
    await peerConnection!.setRemoteDescription(
      RTCSessionDescription(data['sdp'], data['type']),
    );
    final answer = await peerConnection!.createAnswer();
    await peerConnection!.setLocalDescription(answer);
    socket.emit('answer', {
      'meetingId': data['meetingId'],
      'sdp': answer.sdp,
      'type': answer.type,
    });
  }

  void endMeeting() {
    localStream?.getTracks().forEach((track) => track.stop());
    peerConnection?.close();
    socket.disconnect();
    setState(() {
      inMeeting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Talk Now'),
        backgroundColor: Colors.deepPurpleAccent.withOpacity(0.8),
        elevation: 10,
        shadowColor: Colors.purpleAccent,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1F1B24), Color(0xFF2C1A4D), Color(0xFF120E43)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: !inMeeting
            ? Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const Icon(Icons.videocam_rounded,
                    size: 100, color: Colors.purpleAccent),
                const SizedBox(height: 10),
                const Text(
                  "Welcome to Talk Now -Developed by John",
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: "Your Name",
                    prefixIcon:
                    Icon(Icons.person, color: Colors.purpleAccent),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: roomController,
                  decoration: const InputDecoration(
                    labelText: "Meeting ID",
                    prefixIcon:
                    Icon(Icons.meeting_room, color: Colors.purpleAccent),
                  ),
                ),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  onPressed: createMeeting,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Create Meeting'),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: joinMeeting,
                  icon: const Icon(Icons.login),
                  label: const Text('Join Meeting'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                  ),
                ),
              ],
            ),
          ),
        )
            : Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: RTCVideoView(localRenderer, mirror: true),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: RTCVideoView(remoteRenderer),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: endMeeting,
              icon: const Icon(Icons.call_end),
              label: const Text('End Meeting'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(
                    horizontal: 60, vertical: 14),
              ),
            ),
            const SizedBox(height: 15),
          ],
        ),
      ),
    );
  }
}
