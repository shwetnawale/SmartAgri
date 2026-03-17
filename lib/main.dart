import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mongo_dart/mongo_dart.dart' as mongo;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MongoConfig.initialize();
  try {
    await ApiService.initialize();
  } catch (_) {
    // Keep app running so user can open Mongo Settings and fix URI.
  }
  runApp(const SmartAgriPlatform());
}

enum AuthMode { login, signup }

enum RetailerDemandAction { acceptOnly, acceptAndForward }

enum AppSection { dashboard, chat }

const String _configuredMongoUri = String.fromEnvironment(
  'MONGO_URI',
  defaultValue:
      'mongodb://SmartAgri:Piyush2006@ac-romjgr4-shard-00-00.epwjdms.mongodb.net:27017,ac-romjgr4-shard-00-01.epwjdms.mongodb.net:27017,ac-romjgr4-shard-00-02.epwjdms.mongodb.net:27017/agri_logistics?ssl=true&replicaSet=atlas-rjt4j9-shard-0&authSource=admin&retryWrites=true&w=majority&appName=SmartAgri',
);
const String _configuredMongoDb = String.fromEnvironment('MONGO_DB', defaultValue: 'agri_logistics');

class MongoConfig {
  static final ValueNotifier<String> activeMongoUri = ValueNotifier<String>(_configuredMongoUri.trim());
  static final ValueNotifier<String> activeMongoDb = ValueNotifier<String>(_configuredMongoDb.trim().isEmpty ? 'agri_logistics' : _configuredMongoDb.trim());

  static String get mongoUri => activeMongoUri.value;
  static String get mongoDb => activeMongoDb.value;

  static Future<void> initialize() async {}
}

class ApiResult {
  final bool ok;
  final String message;
  const ApiResult({required this.ok, required this.message});
}

class ApiService {
  static mongo.Db? _db;
  static final ValueNotifier<String> connectionStatus = ValueNotifier<String>('Disconnected');
  static final ValueNotifier<String?> connectionError = ValueNotifier<String?>(null);
  static mongo.DbCollection get _users => _db!.collection('users');
  static mongo.DbCollection get _events => _db!.collection('events');

  static String _normalizePhone(String phone) => phone.replaceAll(RegExp(r'\D'), '').trim();
  static bool _isValidPhone(String phone) => phone.length == 10 && int.tryParse(phone) != null;

  static Future<void> initialize() async {
    await _ensureConnected();
  }

  static Future<void> reconnect() async {
    try {
      await _db?.close();
    } catch (_) {
      // Ignore close errors.
    }
    _db = null;
    try {
      await _ensureConnected();
    } catch (_) {
      // Keep UI alive and expose error via connection notifiers.
    }
  }

  static Future<void> _ensureConnected() async {
    if (_db != null && _db!.isConnected) return;
    final String uri = MongoConfig.mongoUri.trim();
    if (uri.toLowerCase().startsWith('mongodb+srv://')) {
      connectionStatus.value = 'Disconnected';
      connectionError.value = 'Unsupported URI scheme mongodb+srv. Use mongodb:// URI.';
      throw const FormatException('Unsupported URI scheme mongodb+srv.');
    }
    connectionStatus.value = 'Connecting...';
    try {
      final mongo.Db db = mongo.Db(uri);
      await db.open().timeout(const Duration(seconds: 12));
      db.databaseName = MongoConfig.mongoDb;
      _db = db;
      connectionStatus.value = 'Connected';
      connectionError.value = null;
    } catch (e) {
      connectionStatus.value = 'Disconnected';
      connectionError.value = e.toString();
      rethrow;
    }
  }

  static Map<String, dynamic> _cleanDoc(Map<String, dynamic> doc) {
    final Map<String, dynamic> out = <String, dynamic>{};
    doc.forEach((key, value) {
      if (value is mongo.ObjectId) {
        out[key] = value.toHexString();
      } else if (value is DateTime) {
        out[key] = value.toIso8601String();
      } else if (value is Map) {
        out[key] = _cleanDoc(Map<String, dynamic>.from(value));
      } else if (value is List) {
        out[key] = value
            .map((e) => e is Map
                ? _cleanDoc(Map<String, dynamic>.from(e))
                : (e is mongo.ObjectId ? e.toHexString() : e))
            .toList();
      } else {
        out[key] = value;
      }
    });
    return out;
  }

  static Future<List<Map<String, String>>> fetchUsersByRole(String role) async {
    try {
      await _ensureConnected();
      final List<Map<String, dynamic>> data = await _users.find({'role': role}).toList();
      return data.map((item) => {
        'name': (item['name'] ?? '').toString(),
        'role': (item['role'] ?? '').toString(),
        'phone': (item['phone'] ?? '').toString(),
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<ApiResult> signup(Map<String, String> user) async {
    final String normalizedPhone = _normalizePhone(user['phone'] ?? '');
    if (!_isValidPhone(normalizedPhone)) {
      return const ApiResult(ok: false, message: 'Phone must be exactly 10 digits.');
    }
    try {
      await _ensureConnected();
      final Map<String, dynamic>? existing = await _users.findOne({'phone': normalizedPhone, 'role': user['role']});
      if (existing != null) {
        return const ApiResult(ok: false, message: 'Account already exists for this phone and role.');
      }
      await _users.insertOne(<String, dynamic>{
        'name': user['name'] ?? '',
        'phone': normalizedPhone,
        'role': user['role'] ?? '',
        'password': user['password'] ?? '123',
        'createdAt': DateTime.now().toIso8601String(),
      });
      return const ApiResult(ok: true, message: 'Account created successfully.');
    } catch (_) {
      return const ApiResult(ok: false, message: 'Could not connect to MongoDB. Check network and URI.');
    }
  }

  static Future<Map<String, String>?> login({required String phone, required String role, String? password}) async {
    final String normalizedPhone = _normalizePhone(phone);
    if (!_isValidPhone(normalizedPhone)) return null;
    try {
      await _ensureConnected();
      // Query by phone+role only for pre-filled list login (no password required)
      final Map<String, dynamic>? user = await _users.findOne({'phone': normalizedPhone, 'role': role});
      if (user == null) return null;
      return {'name': (user['name'] ?? '').toString(), 'role': (user['role'] ?? '').toString(), 'phone': (user['phone'] ?? '').toString()};
    } catch (e) {
      connectionError.value = e.toString();
      return null;
    }
  }

  static Future<bool> createEvent({required String type, required String role, required String userName, required Map<String, dynamic> payload}) async {
    try {
      await _ensureConnected();
      final mongo.ObjectId id = mongo.ObjectId();
      await _events.insertOne(<String, dynamic>{
        '_id': id,
        'id': id.toHexString(),
        'type': type,
        'role': role,
        'userName': userName,
        'payload': payload,
        'timestamp': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchEvents({String? type}) async {
    try {
      await _ensureConnected();
      final mongo.SelectorBuilder selector = mongo.where;
      if (type != null && type.trim().isNotEmpty) selector.eq('type', type.trim());
      selector.sortBy('timestamp', descending: true);
      final List<Map<String, dynamic>> data = await _events.find(selector).toList();
      return data.map(_cleanDoc).toList();
    } catch (_) {
      return const [];
    }
  }
}

class RealtimeService {
  RealtimeService._();
  static final RealtimeService instance = RealtimeService._();
  static const Duration _pollInterval = Duration(seconds: 2);
  Timer? _poller;
  final Set<String> _seenEventIds = <String>{};
  bool _initialSeedDone = false;
  final StreamController<Map<String, dynamic>> _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;

  void ensureConnected() {
    _poller ??= Timer.periodic(_pollInterval, (_) => _poll());
    _poll();
  }

  Future<void> pollNow() async {
    await _poll();
  }

  Future<void> _poll() async {
    final List<Map<String, dynamic>> latest = await ApiService.fetchEvents();
    if (!_initialSeedDone) {
      if (latest.isEmpty) {
        _initialSeedDone = true;
        return;
      }
      for (final Map<String, dynamic> e in latest.take(100)) {
        final String id = (e['id'] ?? '').toString();
        if (id.isNotEmpty) _seenEventIds.add(id);
      }
      _initialSeedDone = true;
      return;
    }
    if (latest.isEmpty) return;
    for (final Map<String, dynamic> e in latest.reversed) {
      final String id = (e['id'] ?? '').toString();
      if (id.isEmpty || _seenEventIds.contains(id)) continue;
      _seenEventIds.add(id);
      if (_seenEventIds.length > 500) {
        _seenEventIds.remove(_seenEventIds.first);
      }
      _events.add(e);
    }
  }

  Future<void> reconnect() async {
    _poller?.cancel();
    _poller = null;
    _seenEventIds.clear();
    _initialSeedDone = false;
    await ApiService.reconnect();
    ensureConnected();
  }

  void stop() {
    _poller?.cancel();
    _poller = null;
  }
}

class SmartAgriPlatform extends StatefulWidget {
  const SmartAgriPlatform({super.key});

  @override
  State<SmartAgriPlatform> createState() => _SmartAgriPlatformState();
}

class _SmartAgriPlatformState extends State<SmartAgriPlatform> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      RealtimeService.instance.ensureConnected();
      RealtimeService.instance.pollNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, primarySwatch: Colors.green, fontFamily: 'Poppins', scaffoldBackgroundColor: Colors.black),
      home: const AuthChoicePage(),
    );
  }
}

// --- SHARED UI COMPONENTS ---

class GlassCard extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final EdgeInsets padding;
  const GlassCard({super.key, required this.child, this.blur = 15, this.opacity = 0.15, this.padding = const EdgeInsets.all(20)});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(color: Colors.white.withOpacity(opacity), borderRadius: BorderRadius.circular(25), border: Border.all(color: Colors.white.withOpacity(0.2))),
          child: child,
        ),
      ),
    );
  }
}

Widget buildBackground(String imageUrl) {
  return Stack(
    children: [
      Positioned.fill(child: Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Container(color: Colors.black))),
      Positioned.fill(child: Container(color: Colors.black.withOpacity(0.5))),
    ],
  );
}

Widget _buildDashboardForRole(String userRole, String userName) {
  switch (userRole) {
    case 'farmer':
      return FarmerDashboard(userName: userName, userRole: userRole);
    case 'transporter':
      return TransporterDashboard(userName: userName, userRole: userRole);
    default:
      return RetailerDashboard(userName: userName, userRole: userRole);
  }
}

void _openSection(
  BuildContext context, {
  required AppSection currentSection,
  required AppSection targetSection,
  required String userName,
  required String userRole,
}) {
  if (currentSection == targetSection) return;
  final Widget destination = targetSection == AppSection.dashboard
      ? _buildDashboardForRole(userRole, userName)
      : UniversalChatPage(userName: userName, userRole: userRole);
  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => destination));
}

Widget _header(String name, VoidCallback refresh) {
  return Padding(
    padding: const EdgeInsets.all(20),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Welcome Back,', style: TextStyle(color: Colors.white70, fontSize: 16)),
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        ]),
        Row(children: [
          IconButton(onPressed: refresh, icon: const Icon(Icons.refresh, color: Colors.greenAccent)),
          const CircleAvatar(
            radius: 25,
            backgroundColor: Color(0xFF2E7D32),
            child: Icon(Icons.person, color: Colors.white),
          ),
        ]),
      ],
    ),
  );
}

Widget _shipmentCard(String title, String route, String status, double progress) {
  bool isDelivered = status == 'DELIVERED' || status == 'ALLOCATED';
  return Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.1))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: isDelivered ? Colors.green.withOpacity(0.2) : Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(10)), child: Text(status, style: TextStyle(color: isDelivered ? Colors.greenAccent : Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold))),
        Text('${(progress * 100).toInt()}%', style: const TextStyle(color: Colors.white70)),
      ]),
      const SizedBox(height: 12),
      Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      Text(route, style: const TextStyle(color: Colors.white60, fontSize: 14)),
      const SizedBox(height: 15),
      LinearProgressIndicator(value: progress, backgroundColor: Colors.white10, color: Colors.greenAccent, minHeight: 6),
    ]),
  );
}

Widget _bottomNav(
  BuildContext context, {
  required AppSection currentSection,
  required String userName,
  required String userRole,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 15),
    decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), borderRadius: const BorderRadius.vertical(top: Radius.circular(25))),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _NavIcon(
          icon: Icons.dashboard,
          label: 'Dashboard',
          isActive: currentSection == AppSection.dashboard,
          onTap: () => _openSection(
            context,
            currentSection: currentSection,
            targetSection: AppSection.dashboard,
            userName: userName,
            userRole: userRole,
          ),
        ),
        const _NavIcon(icon: Icons.inventory_2, label: 'Inventory'),
        const _NavIcon(icon: Icons.receipt_long, label: 'Orders'),
        _NavIcon(
          icon: Icons.forum,
          label: 'Chat',
          isActive: currentSection == AppSection.chat,
          onTap: () => _openSection(
            context,
            currentSection: currentSection,
            targetSection: AppSection.chat,
            userName: userName,
            userRole: userRole,
          ),
        ),
      ],
    ),
  );
}

class GroupChatPanel extends StatefulWidget {
  final String currentUserName;
  final String currentUserRole;
  final bool showFullHistory;
  final bool isFullScreen;
  final String title;
  final String subtitle;
  const GroupChatPanel({
    super.key,
    required this.currentUserName,
    required this.currentUserRole,
    this.showFullHistory = false,
    this.isFullScreen = false,
    this.title = 'Universal Group Chat',
    this.subtitle = 'All farmers, retailers, and transporters can chat here.',
  });

  @override
  State<GroupChatPanel> createState() => _GroupChatPanelState();
}

class _GroupChatPanelState extends State<GroupChatPanel> {
  final TextEditingController _messageController = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = false;
  bool _sending = false;
  bool _refreshQueued = false;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    RealtimeService.instance.ensureConnected();
    _sub = RealtimeService.instance.events.listen((event) {
      if ((event['type'] ?? '').toString() == 'group_chat_message') {
        _refresh();
      }
    });
    _refresh();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  String _formatTimestamp(String raw) {
    final DateTime? time = DateTime.tryParse(raw)?.toLocal();
    if (time == null) return '';
    final String hour = time.hour.toString().padLeft(2, '0');
    final String minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Future<void> _refresh() async {
    if (_loading) {
      _refreshQueued = true;
      return;
    }
    setState(() => _loading = true);
    final List<Map<String, dynamic>> messages = await ApiService.fetchEvents(type: 'group_chat_message');
    if (!mounted) return;
    final bool shouldRefreshAgain = _refreshQueued;
    final List<Map<String, dynamic>> orderedMessages = widget.showFullHistory
        ? messages
        : messages.take(40).toList();
    setState(() {
      _messages = orderedMessages;
      _loading = false;
      _refreshQueued = false;
    });
    if (shouldRefreshAgain) {
      await _refresh();
    }
  }

  Future<void> _sendMessage() async {
    final String text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final bool ok = await ApiService.createEvent(
      type: 'group_chat_message',
      role: widget.currentUserRole,
      userName: widget.currentUserName,
      payload: {
        'message': text,
        'senderName': widget.currentUserName,
        'senderRole': widget.currentUserRole,
      },
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send message. Check database connection.')),
      );
      return;
    }
    _messageController.clear();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final Widget messageList = _loading
        ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
        : _messages.isEmpty
            ? Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'No chat messages yet. Start the conversation.',
                  style: TextStyle(color: Colors.white70),
                ),
              )
            : ListView.separated(
                reverse: true,
                shrinkWrap: !widget.isFullScreen,
                itemCount: _messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final Map<String, dynamic> chat = _messages[index];
                  final Map<String, dynamic> payload = Map<String, dynamic>.from(chat['payload'] as Map);
                  final String senderName = (payload['senderName'] ?? chat['userName'] ?? 'Unknown').toString();
                  final String senderRole = (payload['senderRole'] ?? chat['role'] ?? 'user').toString();
                  final String message = (payload['message'] ?? '').toString();
                  final bool isMine = senderName == widget.currentUserName && senderRole == widget.currentUserRole;
                  return Align(
                    alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      width: widget.isFullScreen ? 320 : 260,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isMine ? Colors.green.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isMine ? Colors.greenAccent : Colors.white24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '$senderName • ${senderRole.toUpperCase()}',
                                  style: TextStyle(
                                    color: isMine ? Colors.greenAccent : Colors.orangeAccent,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Text(
                                _formatTimestamp((chat['timestamp'] ?? '').toString()),
                                style: const TextStyle(color: Colors.white54, fontSize: 11),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(message, style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  );
                },
              );

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.forum, color: Colors.greenAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.subtitle,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 14),
          if (widget.isFullScreen)
            Expanded(child: messageList)
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: messageList,
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: const InputDecoration(
                    labelText: 'Type a message',
                    hintText: 'Message all users...',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: _sending ? null : _sendMessage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(56, 52),
                ),
                child: _sending
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class UniversalChatPage extends StatelessWidget {
  final String userName;
  final String userRole;
  const UniversalChatPage({super.key, required this.userName, required this.userRole});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          buildBackground('https://images.unsplash.com/photo-1516321318423-f06f85e504b3?q=80&w=2070'),
          SafeArea(
            child: Column(
              children: [
                _header(userName, () => RealtimeService.instance.pollNow()),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Universal Chat',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GroupChatPanel(
                      currentUserName: userName,
                      currentUserRole: userRole,
                      showFullHistory: true,
                      isFullScreen: true,
                      title: 'Universal Group Chat',
                      subtitle: 'Full chat history for all users is shown here.',
                    ),
                  ),
                ),
                _bottomNav(
                  context,
                  currentSection: AppSection.chat,
                  userName: userName,
                  userRole: userRole,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;
  const _NavIcon({required this.icon, required this.label, this.isActive = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    final Color color = isActive ? Colors.greenAccent : Colors.white54;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontSize: 10)),
        ]),
      ),
    );
  }
}

// --- AUTH PAGES ---

class AuthChoicePage extends StatefulWidget {
  const AuthChoicePage({super.key});

  @override
  State<AuthChoicePage> createState() => _AuthChoicePageState();
}

class _AuthChoicePageState extends State<AuthChoicePage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          buildBackground('https://images.unsplash.com/photo-1500382017468-9049fed747ef?q=80&w=2070'),
          Center(
            child: GlassCard(
              blur: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.agriculture, size: 80, color: Color(0xFF4CAF50)),
                  const SizedBox(height: 10),
                  const Text('Smart Agri Logistics', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<String>(
                    valueListenable: MongoConfig.activeMongoDb,
                    builder: (context, dbName, _) => Text('Direct MongoDB mode | DB: $dbName', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  ),
                  const SizedBox(height: 4),
                  ValueListenableBuilder<String>(
                    valueListenable: ApiService.connectionStatus,
                    builder: (context, status, _) => Text(
                      'Status: $status',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: status == 'Connected' ? Colors.greenAccent : Colors.orangeAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<String?>(
                    valueListenable: ApiService.connectionError,
                    builder: (context, err, _) {
                      if (err == null || err.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          err,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 10, color: Colors.redAccent),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 30),
                  _btn(context, 'Login', () => _nav(context, AuthMode.login), true),
                  const SizedBox(height: 15),
                  _btn(context, 'Sign Up', () => _nav(context, AuthMode.signup), false),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  void _nav(BuildContext context, AuthMode mode) => Navigator.push(context, MaterialPageRoute(builder: (context) => RoleSelectionPage(authMode: mode)));
  Widget _btn(BuildContext context, String label, VoidCallback on, bool prim) {
    return SizedBox(width: 280, height: 55, child: prim 
      ? Container(decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF8BC34A), Color(0xFF4CAF50)]), borderRadius: BorderRadius.circular(30)), child: ElevatedButton(onPressed: on, style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))), child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))))
      : OutlinedButton(onPressed: on, style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white70), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))), child: Text(label, style: const TextStyle(fontSize: 18, color: Colors.white))));
  }
}

class RoleSelectionPage extends StatelessWidget {
  final AuthMode authMode;
  const RoleSelectionPage({super.key, required this.authMode});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          buildBackground('https://images.unsplash.com/photo-1464226184884-fa280b87c399?q=80&w=2070'),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back, color: Colors.white)),
                  const SizedBox(height: 20),
                  Text(authMode == AuthMode.login ? 'Welcome Back!' : 'Create Account', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                  const Text('Select your role to continue', style: TextStyle(color: Colors.white70, fontSize: 16)),
                  const SizedBox(height: 40),
                  _roleCard(context, 'Farmer', Icons.agriculture, 'farmer'),
                  const SizedBox(height: 15),
                  _roleCard(context, 'Transporter', Icons.local_shipping, 'transporter'),
                  const SizedBox(height: 15),
                  _roleCard(context, 'Retailer', Icons.storefront, 'retailer'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  Widget _roleCard(BuildContext context, String title, IconData icon, String role) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => LoginPage(authMode: authMode, selectedRole: role))),
      child: GlassCard(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20), child: Row(children: [Icon(icon, size: 40, color: Colors.greenAccent), const SizedBox(width: 20), Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const Spacer(), const Icon(Icons.chevron_right, color: Colors.white54)])),
    );
  }
}

class LoginPage extends StatefulWidget {
  final AuthMode authMode;
  final String selectedRole;
  const LoginPage({super.key, required this.authMode, required this.selectedRole});
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  List<Map<String, String>> _users = [];
  bool _loading = false;
  bool _loadQueued = false;
  Timer? _autoRefreshTimer;
  @override
  void initState() {
    super.initState();
    if (widget.authMode == AuthMode.login) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
      _autoRefreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (mounted) _load();
      });
    }
  }
  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }
  Future<void> _load() async {
    if (_loading) {
      _loadQueued = true;
      return;
    }
    final bool showLoader = _users.isEmpty;
    if (showLoader) {
      setState(() => _loading = true);
    }
    final List<Map<String, String>> users = await ApiService.fetchUsersByRole(widget.selectedRole);
    if (!mounted) return;
    final bool shouldReload = _loadQueued;
    setState(() {
      _users = users;
      _loading = false;
      _loadQueued = false;
    });
    if (shouldReload) {
      await _load();
    }
  }
  void _login(Map<String, String> u) async {
    setState(() => _loading = true);
    final res = await ApiService.login(phone: u['phone']!, role: u['role']!);
    if (!mounted) return;
    setState(() => _loading = false);
    if (res != null) {
      Widget dash = _buildDashboardForRole(res['role']!, res['name']!);
      Navigator.push(context, MaterialPageRoute(builder: (context) => dash));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ApiService.connectionStatus.value != 'Connected'
                ? 'Not connected to database. Check network and try again.'
                : 'Login failed. User not found in database.',
          ),
          backgroundColor: Colors.redAccent,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () async {
              await ApiService.reconnect();
              if (mounted) _load();
            },
          ),
        ),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.selectedRole.toUpperCase()), backgroundColor: Colors.transparent, elevation: 0),
      body: Stack(
        children: [
          buildBackground('https://images.unsplash.com/photo-1592982537447-7440770cbfc9?q=80&w=2070'),
          Padding(
            padding: const EdgeInsets.all(24),
            child: widget.authMode == AuthMode.login 
              ? (_loading
                  ? const Center(child: CircularProgressIndicator())
                  : _users.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.cloud_off, size: 60, color: Colors.white54),
                              const SizedBox(height: 12),
                              const Text('No users found.', style: TextStyle(color: Colors.white70)),
                              const SizedBox(height: 4),
                              ValueListenableBuilder<String>(
                                valueListenable: ApiService.connectionStatus,
                                builder: (ctx, status, _) => Text(
                                  'DB Status: $status',
                                  style: TextStyle(
                                    color: status == 'Connected' ? Colors.greenAccent : Colors.orangeAccent,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  await ApiService.reconnect();
                                  _load();
                                },
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry Connection'),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _users.length,
                          itemBuilder: (c, i) => Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: const CircleAvatar(child: Icon(Icons.person)),
                              title: Text(_users[i]['name']!),
                              subtitle: Text(_users[i]['phone']!),
                              trailing: const Icon(Icons.login),
                              onTap: () => _login(_users[i]),
                            ),
                          ),
                        ))
              : GlassCard(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full Name')),
                      const SizedBox(height: 15),
                      TextField(
                        controller: _phone,
                        keyboardType: TextInputType.number,
                        maxLength: 10,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Phone Number',
                          hintText: 'Enter 10-digit mobile number',
                        ),
                      ),
                      const SizedBox(height: 30),
                      ElevatedButton(
                        onPressed: () async {
                          final String name = _name.text.trim();
                          final String phone = _phone.text.trim();
                          if (name.isEmpty || phone.isEmpty) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Name and phone are required.')),
                            );
                            return;
                          }
                          if (phone.length != 10 || int.tryParse(phone) == null) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Phone must be exactly 10 digits.')),
                            );
                            return;
                          }

                          final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
                          final ApiResult result = await ApiService.signup({
                            'name': name,
                            'phone': phone,
                            'role': widget.selectedRole,
                            'password': '123',
                          });

                          if (!mounted) return;
                          if (result.ok) {
                            messenger.showSnackBar(
                              SnackBar(content: Text(result.message)),
                            );
                            _login({'phone': phone, 'role': widget.selectedRole, 'name': name});
                            return;
                          }

                          messenger.showSnackBar(
                            SnackBar(content: Text(result.message)),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(double.infinity, 55),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                        child: const Text('Create Account'),
                      ),
                    ],
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

// --- FARMER DASHBOARD ---

class FarmerDashboard extends StatefulWidget {
  final String userName;
  final String userRole;
  const FarmerDashboard({super.key, required this.userName, required this.userRole});
  @override
  State<FarmerDashboard> createState() => _FarmerDashboardState();
}

class _FarmerDashboardState extends State<FarmerDashboard> {
  final TextEditingController _item = TextEditingController(text: 'Tomato');
  final TextEditingController _from = TextEditingController(text: 'Nashik');
  final TextEditingController _to = TextEditingController(text: 'Mumbai');
  final TextEditingController _weight = TextEditingController(text: '100');
  final TextEditingController _dist = TextEditingController(text: '160');
  String _vehicle = 'mini';
  bool _share = true;
  double _price = 0;
  bool _loading = false;
  StreamSubscription? _sub;

  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _decisions = [];
  List<Map<String, dynamic>> _demands = [];
  List<Map<String, dynamic>> _spaces = [];
  List<Map<String, dynamic>> _allocations = [];
  List<Map<String, dynamic>> _fDecision = [];
  final Set<String> _pendingRetailerDemandIds = <String>{};
  bool _refreshQueued = false;

  @override
  void initState() {
    super.initState();
    _calc();
    RealtimeService.instance.ensureConnected();
    _sub = RealtimeService.instance.events.listen((_) => _refresh());
    _refresh();
  }
  @override
  void dispose() {
    _sub?.cancel();
    _item.dispose();
    _from.dispose();
    _to.dispose();
    _weight.dispose();
    _dist.dispose();
    super.dispose();
  }

  void _calc() {
    double w = double.tryParse(_weight.text) ?? 0;
    setState(() { _price = _estimateTransportPrice(w); });
  }

  double _estimateTransportPrice(double weightKg) {
    double d = double.tryParse(_dist.text) ?? 0;
    double r = _vehicle == 'refrigerated' ? 5.0 : (_vehicle == 'large' ? 4.0 : 2.0);
    double estimated = (d * weightKg * r / 100);
    if (estimated < 500) estimated = 500;
    return estimated;
  }

  String _generateRequestCode() => 'REQ-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

  void _prefillFromRetailerDemand(Map<String, dynamic> payload) {
    _item.text = (payload['goods'] ?? _item.text).toString();
    _to.text = (payload['city'] ?? _to.text).toString();
    _weight.text = (payload['quantityKg'] ?? _weight.text).toString();
    _calc();
  }

  void _showMessage(String message, {Color backgroundColor = Colors.black87}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: backgroundColor),
    );
  }

  Future<RetailerDemandAction?> _showRetailerForwardPrompt(Map<String, dynamic> payload) {
    final String goods = (payload['goods'] ?? 'Goods').toString();
    final String city = (payload['city'] ?? _to.text).toString();
    final String qty = (payload['quantityKg'] ?? '0').toString();
    return showDialog<RetailerDemandAction>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Forward to transporter?'),
        content: Text(
          'You accepted $goods ($qty kg) for $city. Do you also want to send a transport request to transporters now?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, RetailerDemandAction.acceptOnly),
            child: const Text('Accept Only'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, RetailerDemandAction.acceptAndForward),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black,
            ),
            child: const Text('Accept & Send'),
          ),
        ],
      ),
    );
  }

  Future<bool> _forwardRetailerDemandToTransporter(Map<String, dynamic> demand) async {
    final String demandId = (demand['id'] ?? '').toString();
    if (demandId.isEmpty) return false;

    final bool alreadyForwarded = _history.any((event) {
      if (event['type'] != 'transport_request') return false;
      final Map<String, dynamic> payload = Map<String, dynamic>.from(event['payload'] as Map);
      return (payload['retailerDemandEventId'] ?? '').toString() == demandId;
    });
    if (alreadyForwarded) return true;

    final Map<String, dynamic> payload = Map<String, dynamic>.from(demand['payload'] as Map);
    _prefillFromRetailerDemand(payload);

    final double weightKg = double.tryParse((payload['quantityKg'] ?? '0').toString()) ?? 0;
    final String destination = (payload['city'] ?? _to.text).toString();
    final String origin = _from.text.trim().isEmpty ? 'Farmer Location' : _from.text.trim();
    final String requestCode = _generateRequestCode();

    return ApiService.createEvent(
      type: 'transport_request',
      role: 'farmer',
      userName: widget.userName,
      payload: {
        'requestCode': requestCode,
        'item': (payload['goods'] ?? _item.text).toString(),
        'from': origin,
        'to': destination,
        'weightKg': weightKg,
        'vehicleType': _vehicle,
        'allowSharing': _share,
        'proposedPrice': _estimateTransportPrice(weightKg),
        'sourceType': 'retailer_demand',
        'retailerDemandEventId': demandId,
        'retailerName': (demand['userName'] ?? '').toString(),
        'retailerCity': destination,
        'retailerOfferPrice': payload['offerPrice'],
      },
    );
  }

  Future<void> _handleRetailerDemandAcceptance(Map<String, dynamic> demand) async {
    final String demandId = (demand['id'] ?? '').toString();
    if (demandId.isEmpty || _pendingRetailerDemandIds.contains(demandId)) return;

    final Map<String, dynamic> payload = Map<String, dynamic>.from(demand['payload'] as Map);
    final RetailerDemandAction? action = await _showRetailerForwardPrompt(payload);
    if (action == null) return;

    setState(() => _pendingRetailerDemandIds.add(demandId));
    final bool accepted = await ApiService.createEvent(
      type: 'retailer_demand_decision',
      role: 'farmer',
      userName: widget.userName,
      payload: {
        'retailerDemandEventId': demandId,
        'retailerName': demand['userName'],
        'goods': payload['goods'],
        'decision': 'accepted',
      },
    );

    bool forwarded = false;
    if (accepted && action == RetailerDemandAction.acceptAndForward) {
      forwarded = await _forwardRetailerDemandToTransporter(demand);
    }

    if (!mounted) return;
    setState(() => _pendingRetailerDemandIds.remove(demandId));

    if (!accepted) {
      _showMessage('Retailer request could not be accepted. Try again.', backgroundColor: Colors.redAccent);
      return;
    }

    if (action == RetailerDemandAction.acceptAndForward) {
      _showMessage(
        forwarded
            ? 'Retailer request accepted and sent to transporters.'
            : 'Retailer request accepted, but sending to transporters failed.',
        backgroundColor: forwarded ? Colors.green : Colors.orangeAccent,
      );
    } else {
      _showMessage('Retailer request accepted. You can send it to transporters later.', backgroundColor: Colors.green);
    }

    await _refresh();
  }

  Future<void> _handleRetailerDemandReject(Map<String, dynamic> demand) async {
    final String demandId = (demand['id'] ?? '').toString();
    if (demandId.isEmpty || _pendingRetailerDemandIds.contains(demandId)) return;

    final Map<String, dynamic> payload = Map<String, dynamic>.from(demand['payload'] as Map);
    setState(() => _pendingRetailerDemandIds.add(demandId));
    final bool rejected = await ApiService.createEvent(
      type: 'retailer_demand_decision',
      role: 'farmer',
      userName: widget.userName,
      payload: {
        'retailerDemandEventId': demandId,
        'retailerName': demand['userName'],
        'goods': payload['goods'],
        'decision': 'rejected',
      },
    );

    if (!mounted) return;
    setState(() => _pendingRetailerDemandIds.remove(demandId));
    _showMessage(
      rejected ? 'Retailer request rejected.' : 'Retailer request could not be rejected. Try again.',
      backgroundColor: rejected ? Colors.redAccent : Colors.orangeAccent,
    );
    if (rejected) await _refresh();
  }

  Future<void> _sendAcceptedDemandToTransporter(Map<String, dynamic> demand) async {
    final String demandId = (demand['id'] ?? '').toString();
    if (demandId.isEmpty || _pendingRetailerDemandIds.contains(demandId)) return;

    setState(() => _pendingRetailerDemandIds.add(demandId));
    final bool forwarded = await _forwardRetailerDemandToTransporter(demand);
    if (!mounted) return;
    setState(() => _pendingRetailerDemandIds.remove(demandId));
    _showMessage(
      forwarded ? 'Transport request sent to transporters.' : 'Could not send transport request to transporters.',
      backgroundColor: forwarded ? Colors.green : Colors.orangeAccent,
    );
    if (forwarded) await _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) {
      _refreshQueued = true;
      return;
    }
    setState(() => _loading = true);
    final reqs = await ApiService.fetchEvents(type: 'transport_request');
    final joins = await ApiService.fetchEvents(type: 'join_truck_request');
    final decs = await ApiService.fetchEvents(type: 'transporter_decision');
    final dems = await ApiService.fetchEvents(type: 'retailer_demand');
    final spcs = await ApiService.fetchEvents(type: 'truck_space');
    final allocs = await ApiService.fetchEvents(type: 'truck_allocation');
    final fdd = await ApiService.fetchEvents(type: 'retailer_demand_decision');
    if (!mounted) return;
    final bool shouldRefreshAgain = _refreshQueued;
    setState(() {
      _history = reqs.where((e) => e['userName'] == widget.userName).toList();
      _history.addAll(joins.where((e) => e['userName'] == widget.userName));
      _history.sort((a,b) => (b['timestamp']??'').compareTo(a['timestamp']??''));
      _decisions = decs; _demands = dems; _spaces = spcs; _allocations = allocs;
      _fDecision = fdd.where((e) => e['userName'] == widget.userName).toList();
      _loading = false;
      _refreshQueued = false;
    });
    if (shouldRefreshAgain) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, String> decMap = {};
    for (var d in _decisions) {
      var p = d['payload'] as Map;
      if (p['requestCode'] != null && !decMap.containsKey(p['requestCode'])) decMap[p['requestCode']] = p['decision'];
    }
    final Set<String> allocsSet = _allocations.map((a) => (a['payload'] as Map)['requestCode']?.toString() ?? '').toSet();
    final Map<String, dynamic> fDecMap = { for (var e in _fDecision) (e['payload'] as Map)['retailerDemandEventId'] : e['payload'] };
    final Map<String, Map<String, dynamic>> forwardedDemandMap = <String, Map<String, dynamic>>{};
    for (final event in _history) {
      if (event['type'] != 'transport_request') continue;
      final Map<String, dynamic> payload = Map<String, dynamic>.from(event['payload'] as Map);
      final String retailerDemandEventId = (payload['retailerDemandEventId'] ?? '').toString();
      if (retailerDemandEventId.isEmpty || forwardedDemandMap.containsKey(retailerDemandEventId)) continue;
      forwardedDemandMap[retailerDemandEventId] = payload;
    }

    return Scaffold(
      body: Stack(
        children: [
          buildBackground('https://images.unsplash.com/photo-1500382017468-9049fed747ef?q=80&w=1932'),
          SafeArea(
            child: Column(
              children: [
                _header(widget.userName, _refresh),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      GlassCard(child: Column(children: [
                        const Text('Post New Transport Request', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 10),
                        TextField(controller: _item, decoration: const InputDecoration(labelText: 'Item')),
                        Row(children: [Expanded(child: TextField(controller: _from, decoration: const InputDecoration(labelText: 'From'), onChanged: (_)=>_calc())), const SizedBox(width: 10), Expanded(child: TextField(controller: _to, decoration: const InputDecoration(labelText: 'To'), onChanged: (_)=>_calc()))]),
                        Row(children: [Expanded(child: TextField(controller: _dist, readOnly: true, decoration: const InputDecoration(labelText: 'Dist (km)'))), const SizedBox(width: 10), Expanded(child: TextField(controller: _weight, decoration: const InputDecoration(labelText: 'Weight (kg)'), onChanged: (_)=>_calc()))]),
                        DropdownButtonFormField<String>(initialValue: _vehicle, items: const [DropdownMenuItem(value: 'mini', child: Text('Mini')), DropdownMenuItem(value: 'pickup', child: Text('Pickup')), DropdownMenuItem(value: 'medium', child: Text('Medium')), DropdownMenuItem(value: 'large', child: Text('Large')), DropdownMenuItem(value: 'refrigerated', child: Text('Refrigerated'))], onChanged: (v){ if(v!=null){setState((){_vehicle=v;_calc();});} }, decoration: const InputDecoration(labelText: 'Vehicle')),
                        SwitchListTile(value: _share, title: const Text('Allow Sharing', style: TextStyle(fontSize: 14)), contentPadding: EdgeInsets.zero, onChanged: (v)=>setState(()=>_share=v)),
                        Text('Estimated: Rs ${_price.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                        const SizedBox(height: 10),
                        ElevatedButton(onPressed: () async {
                          final code = _generateRequestCode();
                          if (await ApiService.createEvent(type: 'transport_request', role: 'farmer', userName: widget.userName, payload: {'requestCode': code, 'item': _item.text, 'from': _from.text, 'to': _to.text, 'weightKg': double.parse(_weight.text), 'vehicleType': _vehicle, 'allowSharing': _share, 'proposedPrice': _price})) _refresh();
                        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 45), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: const Text('SUBMIT REQUEST')),
                      ])),
                      const SizedBox(height: 25),
                      const Text('Active Shipments', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 15),
                      ..._history.take(5).map((e) {
                        var p = e['payload'] as Map;
                        var code = p['requestCode'] ?? e['type'];
                        var stat = allocsSet.contains(code) ? 'ALLOCATED' : (decMap[code] ?? 'PENDING');
                        return _shipmentCard(code, '${p['from']} → ${p['to']}', stat, stat == 'ALLOCATED' ? 1.0 : 0.4);
                      }),
                      const SizedBox(height: 20),
                      const Text('Retailer Demands', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ..._demands.take(4).map((d) {
                        final Map<String, dynamic> p = Map<String, dynamic>.from(d['payload'] as Map);
                        final String id = (d['id'] ?? '').toString();
                        final bool locked = fDecMap.containsKey(id);
                        final bool pending = _pendingRetailerDemandIds.contains(id);
                        final Map<String, dynamic>? decisionPayload = locked ? Map<String, dynamic>.from(fDecMap[id] as Map) : null;
                        final String decision = (decisionPayload?['decision'] ?? '').toString();
                        final bool accepted = decision == 'accepted';
                        final Map<String, dynamic>? forwardedPayload = forwardedDemandMap[id];
                        return Container(margin: const EdgeInsets.only(top: 10), child: GlassCard(opacity: 0.08, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${p['goods']} - ${p['quantityKg']} kg', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('${p['city']} | Offer: Rs ${p['offerPrice']} | By: ${d['userName']}'),
                          if (locked)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Decision: ${decision.toUpperCase()}',
                                style: TextStyle(
                                  color: accepted ? Colors.greenAccent : Colors.redAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (forwardedPayload != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Sent to transporters | Request: ${forwardedPayload['requestCode']}',
                                style: const TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                          if (pending)
                            const Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5),
                              ),
                            ),
                          if (!locked && !pending) Row(children: [
                            TextButton(onPressed: () => _handleRetailerDemandAcceptance(d), child: const Text('Accept', style: TextStyle(color: Colors.greenAccent))),
                            TextButton(onPressed: () => _handleRetailerDemandReject(d), child: const Text('Reject', style: TextStyle(color: Colors.redAccent))),
                          ]),
                          if (locked && accepted && forwardedPayload == null && !pending) Row(children: [
                            TextButton(
                              onPressed: () => _sendAcceptedDemandToTransporter(d),
                              child: const Text('Send to Transporter', style: TextStyle(color: Colors.blueAccent)),
                            ),
                          ])
                        ])));
                      }),
                      const SizedBox(height: 20),
                      const Text('Shared Trucks Available', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ..._spaces.take(4).map((s) {
                        var p = s['payload'] as Map;
                        return Card(margin: const EdgeInsets.only(top: 10), child: ListTile(dense: true, title: Text('${p['truckId']} | ${p['from']} -> ${p['to']}'), subtitle: Text('Avail: ${p['remainingKg']} kg | Rs/kg: ${p['pricePerKg']}'), trailing: TextButton(onPressed: () async {
                          if (await ApiService.createEvent(type: 'join_truck_request', role: 'farmer', userName: widget.userName, payload: {'truckSpaceEventId': s['id'], 'truckId': p['truckId'], 'transporterName': s['userName'], 'from': p['from'], 'to': p['to'], 'item': _item.text, 'weightKg': double.parse(_weight.text), 'expectedSplitPrice': double.parse(_weight.text) * (p['pricePerKg']??0)})) _refresh();
                        }, child: const Text('Join'))));
                      }),
                    ],
                  ),
                ),
                _bottomNav(
                  context,
                  currentSection: AppSection.dashboard,
                  userName: widget.userName,
                  userRole: widget.userRole,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- TRANSPORTER DASHBOARD ---

class TransporterDashboard extends StatefulWidget {
  final String userName;
  final String userRole;
  const TransporterDashboard({super.key, required this.userName, required this.userRole});
  @override
  State<TransporterDashboard> createState() => _TransporterDashboardState();
}

class _TransporterDashboardState extends State<TransporterDashboard> {
  final TextEditingController _truckId = TextEditingController(text: 'MH-12-3909');
  final TextEditingController _from = TextEditingController(text: 'Nashik');
  final TextEditingController _to = TextEditingController(text: 'Pune');
  final TextEditingController _cap = TextEditingController(text: '2000');
  final TextEditingController _rem = TextEditingController(text: '600');
  final TextEditingController _price = TextEditingController(text: '9000');
  List<Map<String, dynamic>> _reqs = [];
  List<Map<String, dynamic>> _myDecs = [];
  bool _loading = false;
  bool _refreshQueued = false;
  StreamSubscription? _sub;

  @override
  void initState() { super.initState(); RealtimeService.instance.ensureConnected(); _sub = RealtimeService.instance.events.listen((_) => _refresh()); _refresh(); }
  @override
  void dispose() {
    _sub?.cancel();
    _truckId.dispose();
    _from.dispose();
    _to.dispose();
    _cap.dispose();
    _rem.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) {
      _refreshQueued = true;
      return;
    }
    setState(() => _loading = true);
    final rs = await ApiService.fetchEvents(type: 'transport_request');
    final ds = await ApiService.fetchEvents(type: 'transporter_decision');
    if (!mounted) return;
    final bool shouldRefreshAgain = _refreshQueued;
    setState(() {
      _reqs = rs;
      _myDecs = ds.where((d) => d['userName'] == widget.userName).toList();
      _loading = false;
      _refreshQueued = false;
    });
    if (shouldRefreshAgain) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, String> decMap = { for (var d in _myDecs) (d['payload'] as Map)['requestCode'] : (d['payload'] as Map)['decision'] };
    return Scaffold(
      body: Stack(
        children: [
          buildBackground('https://images.unsplash.com/photo-1519003722824-192d992a6058?q=80&w=2070'),
          SafeArea(
            child: Column(
              children: [
                _header(widget.userName, _refresh),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      GlassCard(child: Column(children: [
                        const Text('Manage Truck Space', style: TextStyle(fontWeight: FontWeight.bold)),
                        TextField(controller: _truckId, decoration: const InputDecoration(labelText: 'Truck ID')),
                        Row(children: [Expanded(child: TextField(controller: _from, decoration: const InputDecoration(labelText: 'From'))), const SizedBox(width: 10), Expanded(child: TextField(controller: _to, decoration: const InputDecoration(labelText: 'To')))]),
                        Row(children: [Expanded(child: TextField(controller: _cap, decoration: const InputDecoration(labelText: 'Cap kg'))), const SizedBox(width: 10), Expanded(child: TextField(controller: _rem, decoration: const InputDecoration(labelText: 'Rem kg')))]),
                        TextField(controller: _price, decoration: const InputDecoration(labelText: 'Base Trip Price (Rs)')),
                        const SizedBox(height: 10),
                        ElevatedButton(onPressed: () async {
                          if (await ApiService.createEvent(type: 'truck_space', role: 'transporter', userName: widget.userName, payload: {'truckId': _truckId.text, 'from': _from.text, 'to': _to.text, 'capacityKg': double.parse(_cap.text), 'remainingKg': double.parse(_rem.text), 'baseTripPrice': double.parse(_price.text), 'pricePerKg': double.parse(_price.text) / double.parse(_cap.text)})) _refresh();
                        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 45), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: const Text('Broadcast Space Available')),
                      ])),
                      const SizedBox(height: 20),
                      const Text('Incoming Transport Requests', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ..._reqs.take(5).map((r) {
                        final Map<String, dynamic> p = Map<String, dynamic>.from(r['payload'] as Map);
                        final String code = (p['requestCode'] ?? '').toString();
                        final String? dec = decMap[code];
                        final bool retailerOrigin = (p['sourceType'] ?? '').toString() == 'retailer_demand';
                        return Container(margin: const EdgeInsets.only(top: 10), child: GlassCard(opacity: 0.08, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (retailerOrigin)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orangeAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text('Retailer order forwarded by farmer', style: TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                          Text('${p['item']} | ${p['weightKg']} kg', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('${p['from']} -> ${p['to']} | Rs ${p['proposedPrice']}'),
                          if (retailerOrigin)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Retailer: ${p['retailerName']} | Demand city: ${p['retailerCity']}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ),
                          if (dec != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Decision: ${dec.toUpperCase()}', style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 12))),
                          if (dec == null) Row(children: [
                            TextButton(onPressed: () async { if(await ApiService.createEvent(type:'transporter_decision', role:'transporter', userName:widget.userName, payload:{'requestCode':code, 'decision':'accepted'})) _refresh(); }, child: const Text('Accept', style: TextStyle(color: Colors.greenAccent))),
                            TextButton(onPressed: () async { if(await ApiService.createEvent(type:'transporter_decision', role:'transporter', userName:widget.userName, payload:{'requestCode':code, 'decision':'rejected'})) _refresh(); }, child: const Text('Reject', style: TextStyle(color: Colors.redAccent))),
                            TextButton(onPressed: () async { if(await ApiService.createEvent(type:'truck_allocation', role:'transporter', userName:widget.userName, payload:{'truckId':_truckId.text, 'requestCode':code, 'item':p['item'], 'weightKg':p['weightKg'], 'proposedPrice':p['proposedPrice']})) _refresh(); }, child: const Text('Allocate', style: TextStyle(color: Colors.blueAccent))),
                          ])
                        ])));
                      }),
                    ],
                  ),
                ),
                _bottomNav(
                  context,
                  currentSection: AppSection.dashboard,
                  userName: widget.userName,
                  userRole: widget.userRole,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- RETAILER DASHBOARD ---

class RetailerDashboard extends StatefulWidget {
  final String userName;
  final String userRole;
  const RetailerDashboard({super.key, required this.userName, required this.userRole});
  @override
  State<RetailerDashboard> createState() => _RetailerDashboardState();
}

class _RetailerDashboardState extends State<RetailerDashboard> {
  final TextEditingController _qty = TextEditingController();
  final TextEditingController _offer = TextEditingController();
  String _item = 'Banana';
  String _city = 'Pune';
  List<Map<String, dynamic>> _myDems = [];
  List<Map<String, dynamic>> _fDecs = [];
  bool _loading = false;
  bool _refreshQueued = false;
  StreamSubscription? _sub;

  @override
  void initState() { super.initState(); RealtimeService.instance.ensureConnected(); _sub = RealtimeService.instance.events.listen((_) => _refresh()); _refresh(); }
  @override
  void dispose() {
    _sub?.cancel();
    _qty.dispose();
    _offer.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) {
      _refreshQueued = true;
      return;
    }
    setState(() => _loading = true);
    final ds = await ApiService.fetchEvents(type: 'retailer_demand');
    final fs = await ApiService.fetchEvents(type: 'retailer_demand_decision');
    if (!mounted) return;
    final bool shouldRefreshAgain = _refreshQueued;
    setState(() {
      _myDems = ds.where((e) => e['userName'] == widget.userName).toList();
      _fDecs = fs;
      _loading = false;
      _refreshQueued = false;
    });
    if (shouldRefreshAgain) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          buildBackground('https://images.unsplash.com/photo-1488459716781-31db52582fe9?q=80&w=2070'),
          SafeArea(
            child: Column(
              children: [
                _header(widget.userName, _refresh),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      GlassCard(child: Column(children: [
                        const Text('Retailer Demand Panel', style: TextStyle(fontWeight: FontWeight.bold)),
                        DropdownButtonFormField<String>(initialValue: _item, items: const [DropdownMenuItem(value: 'Banana', child: Text('Banana')), DropdownMenuItem(value: 'Mango', child: Text('Mango')), DropdownMenuItem(value: 'Tomato', child: Text('Tomato'))], onChanged: (v)=>setState(()=>_item=v!), decoration: const InputDecoration(labelText: 'Item')),
                        TextField(controller: _qty, decoration: const InputDecoration(labelText: 'Qty (kg)')),
                        DropdownButtonFormField<String>(initialValue: _city, items: const [DropdownMenuItem(value: 'Pune', child: Text('Pune')), DropdownMenuItem(value: 'Mumbai', child: Text('Mumbai')), DropdownMenuItem(value: 'Nashik', child: Text('Nashik'))], onChanged: (v)=>setState(()=>_city=v!), decoration: const InputDecoration(labelText: 'City')),
                        TextField(controller: _offer, decoration: const InputDecoration(labelText: 'Offer Price (Rs)')),
                        const SizedBox(height: 10),
                        ElevatedButton(onPressed: () async {
                          if (await ApiService.createEvent(type: 'retailer_demand', role: 'retailer', userName: widget.userName, payload: {'goods': _item, 'quantityKg': int.parse(_qty.text), 'city': _city, 'offerPrice': double.parse(_offer.text)})) _refresh();
                        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black, minimumSize: const Size(double.infinity, 45), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: const Text('SEND DEMAND TO MAIN SERVER')),
                      ])),
                      const SizedBox(height: 20),
                      const Text('My Demand History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ..._myDems.map((d) {
                        var p = d['payload'] as Map;
                        var responses = _fDecs.where((f) => (f['payload'] as Map)['retailerDemandEventId'] == d['id']).toList();
                        return Card(margin: const EdgeInsets.only(top: 10), child: ExpansionTile(title: Text('${p['goods']} - ${p['quantityKg']} kg'), subtitle: Text('Rs ${p['offerPrice']} | Responses: ${responses.length}'), children: responses.map((r) => ListTile(dense: true, title: Text(r['userName']!), subtitle: Text('Status: ${(r['payload'] as Map)['decision'].toUpperCase()}'))).toList()));
                      }),
                    ],
                  ),
                ),
                _bottomNav(
                  context,
                  currentSection: AppSection.dashboard,
                  userName: widget.userName,
                  userRole: widget.userRole,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
