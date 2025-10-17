import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:clipboard/clipboard.dart';
import 'dart:io';

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
      theme: ThemeData.dark(),
      home: const LandingPage(),
    );
  }
}

// Landing Page
class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final usernameController = TextEditingController();
  final roomController = TextEditingController();

  Future<void> _createMeeting() async {
    final username = usernameController.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name')),
      );
      return;
    }

    try {
      final res = await http.post(
        Uri.parse('$backendBaseUrl/create-meeting'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username}),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final meetingId = data['meetingId'];
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MeetingPage(meetingId: meetingId, username: username),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create meeting. Server responded with ${res.statusCode}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reach server: $e')),
      );
    }
  }

  void _joinMeeting() {
    final username = usernameController.text.trim();
    final meetingId = roomController.text.trim();

    if (username.isEmpty || meetingId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter name and meeting ID')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeetingPage(meetingId: meetingId, username: username),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.deepPurple, Colors.purpleAccent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Icon(Icons.videocam_rounded, size: 100, color: Colors.white),
                const SizedBox(height: 10),
                const Text(
                  "Welcome to Talk Now",
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 30),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  color: Colors.white.withOpacity(0.1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: TextField(
                      controller: usernameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Your Name',
                        prefixIcon: Icon(Icons.person, color: Colors.white),
                        labelStyle: TextStyle(color: Colors.white70),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 15),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  color: Colors.white.withOpacity(0.1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: TextField(
                      controller: roomController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Meeting ID',
                        prefixIcon: Icon(Icons.meeting_room, color: Colors.white),
                        labelStyle: TextStyle(color: Colors.white70),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                ElevatedButton.icon(
                  onPressed: _createMeeting,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Create Meeting'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: Colors.deepPurpleAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 5,
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _joinMeeting,
                  icon: const Icon(Icons.login),
                  label: const Text('Join Meeting'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: Colors.purple,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Meeting Page
class MeetingPage extends StatefulWidget {
  final String meetingId;
  final String username;
  const MeetingPage({super.key, required this.meetingId, required this.username});

  @override
  State<MeetingPage> createState() => _MeetingPageState();
}

class _MeetingPageState extends State<MeetingPage> {
  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  WebSocket? socket;
  List<String> participants = [];

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _initMeeting();
  }

  Future<void> _initRenderers() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();
  }

  Future<void> _initLocalStream() async {
    localStream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': {'facingMode': 'user'}});
    localRenderer.srcObject = localStream;
  }

  Future<void> _createPeerConnection() async {
    peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'}
      ]
    });

    peerConnection!.onIceCandidate = (candidate) {
      if (candidate != null) {
        socket!.add(jsonEncode({
          'type': 'candidate',
          'meetingId': widget.meetingId,
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex
        }));
      }
    };

    peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
        setState(() {});
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
        case 'participant-joined':
          final newUser = data['username'];
          if (!participants.contains(newUser)) {
            setState(() => participants.add(newUser));
          }
          break;

        case 'offer':
          await _createPeerConnection();
          await peerConnection!.setRemoteDescription(RTCSessionDescription(data['sdp'], data['type']));
          final answer = await peerConnection!.createAnswer();
          await peerConnection!.setLocalDescription(answer);
          socket!.add(jsonEncode({'type': 'answer','meetingId': widget.meetingId,'sdp': answer.sdp}));
          break;

        case 'answer':
          await peerConnection!.setRemoteDescription(RTCSessionDescription(data['sdp'], data['type']));
          break;

        case 'candidate':
          await peerConnection!.addCandidate(RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']));
          break;
      }
    });

    socket!.add(jsonEncode({'type': 'joinRoom', 'meetingId': widget.meetingId, 'username': widget.username}));
    participants.add(widget.username);
  }

  Future<void> _initMeeting() async {
    await _initLocalStream();
    await _connectSocket();
    await _createPeerConnection();
    final offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);
    socket!.add(jsonEncode({'type': 'offer','meetingId': widget.meetingId,'sdp': offer.sdp}));
  }

  void _endMeeting() {
    localStream?.getTracks().forEach((track) => track.stop());
    peerConnection?.close();
    socket?.close();
    Navigator.pop(context);
  }

  void _shareMeetingId() {
    FlutterClipboard.copy(widget.meetingId).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Meeting ID copied!')));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Meeting ID: ${widget.meetingId}'),
        backgroundColor: Colors.deepPurpleAccent,
        actions: [IconButton(onPressed: _shareMeetingId, icon: const Icon(Icons.share))],
      ),
      body: Column(
        children: [
          Expanded(
              child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.purpleAccent, width: 2),
                      borderRadius: BorderRadius.circular(12)
                  ),
                  child: RTCVideoView(localRenderer, mirror: true)
              )
          ),
          Expanded(
              child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.purpleAccent, width: 2),
                      borderRadius: BorderRadius.circular(12)
                  ),
                  child: RTCVideoView(remoteRenderer)
              )
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Text('Participants: ${participants.join(", ")}', style: const TextStyle(fontSize: 16, color: Colors.white)),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _endMeeting,
                  icon: const Icon(Icons.call_end),
                  label: const Text('End Meeting'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
