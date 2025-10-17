import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:io';

// Replace with your backend IP or hosted URL
const backendIP = '192.168.0.107';
final backendBaseUrl = 'http://$backendIP:5000';
final wsUrl = 'ws://$backendIP:5000/ws';

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
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.deepPurpleAccent,
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
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
  final usernameController = TextEditingController();
  final roomController = TextEditingController();

  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  WebSocket? socket;

  bool inMeeting = false;
  String? meetingId;
  String? username;

  @override
  void initState() {
    super.initState();
    _initializeRenderers();
  }

  Future<void> _initializeRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    setState(() {}); // safe to rebuild
  }

  @override
  void dispose() {
    localRenderer.dispose();
    remoteRenderer.dispose();
    socket?.close();
    super.dispose();
  }

  Future<void> _initLocalStream() async {
    localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {'facingMode': 'user'}
    });
    localRenderer.srcObject = localStream;
  }

  Future<void> _createPeerConnection() async {
    peerConnection ??= await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    });

    peerConnection!.onIceCandidate = (candidate) {
      if (candidate != null) {
        socket?.add(jsonEncode({
          'type': 'candidate',
          'meetingId': meetingId,
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex
        }));
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

  Future<void> _connectSocket() async {
    socket = await WebSocket.connect(wsUrl);

    socket!.listen((event) async {
      final data = jsonDecode(event);
      switch (data['type']) {
        case 'offer':
          await _createPeerConnection();
          await peerConnection!.setRemoteDescription(
            RTCSessionDescription(data['sdp'], 'offer'),
          );
          final answer = await peerConnection!.createAnswer();
          await peerConnection!.setLocalDescription(answer);
          socket!.add(jsonEncode({
            'type': 'answer',
            'meetingId': meetingId,
            'sdp': answer.sdp,
          }));
          break;

        case 'answer':
          await peerConnection!.setRemoteDescription(
            RTCSessionDescription(data['sdp'], 'answer'),
          );
          break;

        case 'candidate':
          await peerConnection!.addCandidate(
            RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']),
          );
          break;
      }
    });

    socket!.add(jsonEncode({
      'type': 'joinRoom',
      'meetingId': meetingId,
      'username': username,
    }));
  }

  Future<void> createMeeting() async {
    await _initLocalStream();
    final res = await HttpClient()
        .postUrl(Uri.parse('$backendBaseUrl/create-meeting'))
        .then((req) => req.close());
    final body = await res.transform(utf8.decoder).join();
    final data = jsonDecode(body);

    meetingId = data['meetingId'];
    username = usernameController.text.trim();
    if (username!.isEmpty) return;

    await _connectSocket();
    await _createPeerConnection();

    final offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);

    socket!.add(jsonEncode({
      'type': 'offer',
      'meetingId': meetingId,
      'sdp': offer.sdp,
    }));

    setState(() => inMeeting = true); // update UI after everything is ready
  }

  Future<void> joinMeeting() async {
    await _initLocalStream();
    meetingId = roomController.text.trim();
    username = usernameController.text.trim();
    if (meetingId!.isEmpty || username!.isEmpty) return;

    await _connectSocket();
    await _createPeerConnection();

    setState(() => inMeeting = true); // update UI after setup
  }

  void endMeeting() {
    localStream?.getTracks().forEach((track) => track.stop());
    peerConnection?.close();
    socket?.close();
    peerConnection = null;
    setState(() => inMeeting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Talk Now'),
        backgroundColor: Colors.deepPurpleAccent.withOpacity(0.8),
      ),
      body: Padding(
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
                  "Welcome to Talk Now - Developed by John",
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: "Your Name",
                    prefixIcon: Icon(Icons.person, color: Colors.purpleAccent),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: roomController,
                  decoration: const InputDecoration(
                    labelText: "Meeting ID",
                    prefixIcon: Icon(Icons.meeting_room, color: Colors.purpleAccent),
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
                padding:
                const EdgeInsets.symmetric(horizontal: 60, vertical: 14),
              ),
            ),
            const SizedBox(height: 15),
          ],
        ),
      ),
    );
  }
}
