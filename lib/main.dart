import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartAgriPlatform());
}

enum AuthMode { login, signup }

const String _configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');

class BackendConfig {
  static final ValueNotifier<String> activeBaseUrl = ValueNotifier<String>(_initialBaseUrl());

  static String _initialBaseUrl() {
    if (_configuredApiBaseUrl.isNotEmpty) {
      return _normalize(_configuredApiBaseUrl);
    }
    return kIsWeb ? 'http://127.0.0.1:5000' : 'http://10.0.2.2:5000';
  }

  static String get baseUrl => activeBaseUrl.value;

  static String _normalize(String url) {
    String normalized = url.trim();
    if (normalized.isEmpty) {
      return normalized;
    }

    // Allow plain IP/domain entry like 192.168.0.104 or mypc.local
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }

    final Uri? parsed = Uri.tryParse(normalized);
    if (parsed != null && parsed.host.isNotEmpty && parsed.hasPort == false) {
      normalized = '${parsed.scheme}://${parsed.host}:5000';
    }

    return normalized.replaceAll(RegExp(r'/+$'), '');
  }

}

class ApiService {
  static Uri _uri(String path, {Map<String, String>? query}) {
    return Uri.parse('${BackendConfig.baseUrl}$path').replace(queryParameters: query);
  }

  static Future<List<Map<String, String>>> fetchUsersByRole(String role) async {
    try {
      final Uri uri = _uri('/users', query: <String, String>{'role': role});
      final http.Response response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return const [];
      }
      final dynamic data = jsonDecode(response.body);
      if (data is! List) {
        return const [];
      }
      return data
          .whereType<Map<String, dynamic>>()
          .map((item) => {
                'name': (item['name'] ?? '').toString(),
                'role': (item['role'] ?? '').toString(),
                'phone': (item['phone'] ?? '').toString(),
              })
          .where((u) => u['name']!.isNotEmpty && u['role']!.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> signup(Map<String, String> user) async {
    try {
      final Uri uri = _uri('/signup');
      final http.Response response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(user),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, String>?> login({
    required String phone,
    required String role,
    required String password,
  }) async {
    try {
      final Uri uri = _uri('/login');
      final http.Response response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone, 'role': role, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return null;
      }

      final dynamic body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        return null;
      }
      final dynamic user = body['user'];
      if (user is! Map<String, dynamic>) {
        return null;
      }

      return {
        'name': (user['name'] ?? '').toString(),
        'role': (user['role'] ?? '').toString(),
        'phone': (user['phone'] ?? '').toString(),
      };
    } catch (_) {
      return null;
    }
  }

  static Future<bool> createEvent({
    required String type,
    required String role,
    required String userName,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final Uri uri = _uri('/events');
      final http.Response response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'type': type,
              'role': role,
              'userName': userName,
              'payload': payload,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchEvents({String? type}) async {
    try {
      final Uri uri = _uri('/events', query: type == null ? null : <String, String>{'type': type});
      final http.Response response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return const [];
      }
      final dynamic data = jsonDecode(response.body);
      if (data is! List) {
        return const [];
      }
      return data.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }
}

class RealtimeService {
  RealtimeService._();

  static final RealtimeService instance = RealtimeService._();

  io.Socket? _socket;
  bool _connecting = false;
  final StreamController<Map<String, dynamic>> _events = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get events => _events.stream;

  void ensureConnected() {
    if (_socket?.connected == true || _connecting) {
      return;
    }

    _connecting = true;
    final io.Socket socket = io.io(
      BackendConfig.baseUrl,
      io.OptionBuilder()
          .setTransports(<String>['websocket'])
          .enableReconnection()
          .setReconnectionAttempts(999)
          .setReconnectionDelay(1000)
          .disableAutoConnect()
          .build(),
    );

    socket.onConnect((_) {
      _connecting = false;
    });

    socket.onConnectError((_) {
      _connecting = false;
    });

    socket.onError((_) {
      _connecting = false;
    });

    socket.on('db_event', (dynamic data) {
      if (data is Map) {
        _events.add(Map<String, dynamic>.from(data));
      }
    });

    socket.connect();
    _socket = socket;
  }

  void dispose() {
    _socket?.dispose();
    _socket = null;
  }
}

class SmartAgriPlatform extends StatelessWidget {
  const SmartAgriPlatform({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.green, fontFamily: 'Poppins'),
      home: const AuthChoicePage(),
    );
  }
}

class AuthChoicePage extends StatelessWidget {
  const AuthChoicePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2E7D32),
      body: Center(
        child: Container(
          width: 350,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.agriculture, size: 70, color: Color(0xFF2E7D32)),
              const SizedBox(height: 12),
              const Text('Smart Agri Logistics', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ValueListenableBuilder<String>(
                valueListenable: BackendConfig.activeBaseUrl,
                builder: (context, url, _) => Text(
                  'REST + WebSocket server: $url',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const RoleSelectionPage(authMode: AuthMode.login)),
                  );
                },
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                child: const Text('Login'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const RoleSelectionPage(authMode: AuthMode.signup)),
                  );
                },
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                child: const Text('Sign Up'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RoleSelectionPage extends StatelessWidget {
  final AuthMode authMode;

  const RoleSelectionPage({super.key, required this.authMode});

  void _openRole(BuildContext context, String role) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LoginPage(authMode: authMode, selectedRole: role),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isLogin = authMode == AuthMode.login;
    return Scaffold(
      backgroundColor: const Color(0xFF2E7D32),
      appBar: AppBar(title: Text(isLogin ? 'Login - Select Role' : 'Sign Up - Select Role')),
      body: Center(
        child: Container(
          width: 360,
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Select Role', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(isLogin ? 'Choose role to login' : 'Choose role to create account'),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openRole(context, 'farmer'),
                  icon: const Icon(Icons.agriculture),
                  label: const Text('Farmer'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openRole(context, 'transporter'),
                  icon: const Icon(Icons.local_shipping),
                  label: const Text('Transporter'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openRole(context, 'retailer'),
                  icon: const Icon(Icons.storefront),
                  label: const Text('Retailer'),
                ),
              ),
            ],
          ),
        ),
      ),
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
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  List<Map<String, String>> _roleUsers = [];
  bool _loadingUsers = false;

  @override
  void initState() {
    super.initState();
    if (widget.authMode == AuthMode.login) {
      _loadRoleUsersFromServer();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  String _roleLabel(String role) {
    if (role == 'farmer') return 'Farmer';
    if (role == 'transporter') return 'Transporter';
    return 'Retailer';
  }

  Future<void> _loadRoleUsersFromServer() async {
    setState(() => _loadingUsers = true);
    final List<Map<String, String>> serverUsers = await ApiService.fetchUsersByRole(widget.selectedRole);
    if (mounted) {
      setState(() {
        _roleUsers = serverUsers;
        _loadingUsers = false;
      });
    }
  }

  Future<void> _createAccountForSelectedRole() async {
    final String name = _nameController.text.trim();
    final String phone = _phoneController.text.trim();
    final bool isPhoneValid = RegExp(r'^\d{10}$').hasMatch(phone);

    if (name.isEmpty || !isPhoneValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid name and 10-digit phone number.')),
      );
      return;
    }

    final String role = widget.selectedRole;
    final Map<String, String> created = {
      'name': '$name (${_roleLabel(role)})',
      'role': role,
      'phone': phone,
      'password': '123',
    };

    final bool synced = await ApiService.signup(created);
    final String message = synced
        ? 'Account created and saved in MongoDB.'
        : 'Sign up failed. Check backend and MongoDB connection.';

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    if (synced) {
      performLogin(created);
    }
  }

  Future<void> _loginWithServer(Map<String, String> user) async {
    final String phone = user['phone'] ?? '';
    final String role = user['role'] ?? '';

    final Map<String, String>? loggedIn = await ApiService.login(
      phone: phone,
      role: role,
      password: '123',
    );

    if (!mounted) {
      return;
    }

    if (loggedIn == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed. Check backend/MongoDB and API URL: ${BackendConfig.baseUrl}')),
      );
      return;
    }

    performLogin(loggedIn);
  }

  void performLogin(Map<String, String> user) {
    Widget nextScreen;
    if (user['role'] == 'farmer') {
      nextScreen = FarmerDashboard(userName: user['name']!);
    } else if (user['role'] == 'transporter') {
      nextScreen = TransporterDashboard(userName: user['name']!);
    } else {
      nextScreen = RetailerDashboard(userName: user['name']!);
    }
    Navigator.push(context, MaterialPageRoute(builder: (context) => nextScreen));
  }

  @override
  Widget build(BuildContext context) {
    final bool isLogin = widget.authMode == AuthMode.login;
    final String roleTitle = _roleLabel(widget.selectedRole);

    return Scaffold(
      backgroundColor: const Color(0xFF2E7D32),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const Icon(Icons.agriculture, size: 80, color: Colors.white),
              const Text('Smart Agri Logistics', style: TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 30),
              Container(
                width: 350,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
                child: Column(
                  children: [
                    Text(
                      isLogin ? 'Login as $roleTitle' : 'Sign Up as $roleTitle',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 20),
                    if (isLogin) ...[
                      if (_loadingUsers) const CircularProgressIndicator(),
                      if (!_loadingUsers && _roleUsers.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Text('No users found for this role. Please sign up.'),
                        ),
                      ..._roleUsers.map((user) => Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey[100],
                                foregroundColor: Colors.black87,
                                minimumSize: const Size(double.infinity, 55),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15),
                                  side: const BorderSide(color: Colors.green),
                                ),
                              ),
                              onPressed: () => _loginWithServer(user),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(user['name']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        Text(user['phone']!, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.green),
                                ],
                              ),
                            ),
                          )),
                    ] else ...[
                      TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Full Name',
                          prefixIcon: const Icon(Icons.person),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: 'Phone Number (10 digits)',
                          prefixIcon: const Icon(Icons.phone),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _createAccountForSelectedRole,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 55),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                        child: const Text('Create Account'),
                      ),
                    ],
                    const SizedBox(height: 15),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Go Back', style: TextStyle(color: Colors.green)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: TextField(
                  onChanged: (val) {
                    BackendConfig.activeBaseUrl.value = BackendConfig._normalize(val);
                  },
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Change Server IP (Optional)',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white70)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FarmerDashboard extends StatefulWidget {
  final String userName;

  const FarmerDashboard({super.key, required this.userName});

  @override
  State<FarmerDashboard> createState() => _FarmerDashboardState();
}

class _FarmerDashboardState extends State<FarmerDashboard> {
  final TextEditingController _itemController = TextEditingController(text: 'Tomato');
  final TextEditingController _fromController = TextEditingController(text: 'Nashik');
  final TextEditingController _toController = TextEditingController(text: 'Mumbai');
  final TextEditingController _weightController = TextEditingController(text: '100');
  final TextEditingController _distanceController = TextEditingController(text: '160');
  final TextEditingController _notesController = TextEditingController();

  String _vehicle = 'mini';
  bool _shareTruck = true;
  double _price = 0;
  bool _loading = false;
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;

  List<Map<String, dynamic>> _myRequestHistory = [];
  List<Map<String, dynamic>> _decisions = [];
  List<Map<String, dynamic>> _demands = [];
  List<Map<String, dynamic>> _spaces = [];
  List<Map<String, dynamic>> _allocations = [];
  List<Map<String, dynamic>> _farmerDemandDecisions = [];

  @override
  void initState() {
    super.initState();
    _recalculateDistance();
    RealtimeService.instance.ensureConnected();
    _wsSubscription = RealtimeService.instance.events.listen((_) {
      if (mounted) {
        _refreshData();
      }
    });
    _refreshData();
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _itemController.dispose();
    _fromController.dispose();
    _toController.dispose();
    _weightController.dispose();
    _distanceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _recalculateDistance() {
    final double dist = double.tryParse(_distanceController.text) ?? 0;
    final double weight = double.tryParse(_weightController.text) ?? 0;
    double rate = 2.0;
    if (_vehicle == 'refrigerated') rate = 5.0;
    if (_vehicle == 'large') rate = 4.0;
    setState(() {
      _price = dist * weight * rate / 100;
      if (_price < 500) _price = 500;
    });
  }

  Future<void> _refreshData() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final List<Map<String, dynamic>> requests = await ApiService.fetchEvents(type: 'transport_request');
      final List<Map<String, dynamic>> joins = await ApiService.fetchEvents(type: 'join_truck_request');
      final List<Map<String, dynamic>> decisions = await ApiService.fetchEvents(type: 'transporter_decision');
      final List<Map<String, dynamic>> demands = await ApiService.fetchEvents(type: 'retailer_demand');
      final List<Map<String, dynamic>> spaces = await ApiService.fetchEvents(type: 'truck_space');
      final List<Map<String, dynamic>> allocations = await ApiService.fetchEvents(type: 'truck_allocation');
      final List<Map<String, dynamic>> fdd = await ApiService.fetchEvents(type: 'retailer_demand_decision');

      if (mounted) {
        setState(() {
          _myRequestHistory = requests.where((e) => e['userName'] == widget.userName).toList();
          _myRequestHistory.addAll(joins.where((e) => e['userName'] == widget.userName));
          _myRequestHistory.sort((a, b) => (b['timestamp'] ?? '').compareTo(a['timestamp'] ?? ''));

          _decisions = decisions;
          _demands = demands;
          _spaces = spaces;
          _allocations = allocations;
          _farmerDemandDecisions = fdd.where((e) => e['userName'] == widget.userName).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _routeKey(String f, String t) => '${f.toLowerCase().trim()}_${t.toLowerCase().trim()}';

  Future<void> _submitTransportRequest() async {
    final String item = _itemController.text.trim();
    final String from = _fromController.text.trim();
    final String to = _toController.text.trim();
    final double weight = double.tryParse(_weightController.text.trim()) ?? 0;

    if (item.isEmpty || from.isEmpty || to.isEmpty || weight <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields.')));
      return;
    }

    final String code = 'REQ-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    final bool sent = await ApiService.createEvent(
      type: 'transport_request',
      role: 'farmer',
      userName: widget.userName,
      payload: {
        'requestCode': code,
        'item': item,
        'from': from,
        'to': to,
        'routeKey': _routeKey(from, to),
        'weightKg': weight,
        'vehicleType': _vehicle,
        'allowSharing': _shareTruck,
        'proposedPrice': _price,
        'notes': _notesController.text.trim(),
      },
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sent ? 'Request Sent: $code' : 'Sync Error.')));
    if (sent) _refreshData();
  }

  Future<void> _joinSharedTruck(Map<String, dynamic> spaceEvent) async {
    final Map<String, dynamic> p = (spaceEvent['payload'] as Map<String, dynamic>? ?? {});
    final double weight = double.tryParse(_weightController.text.trim()) ?? 0;

    if (weight <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter weight first.')));
      return;
    }

    final bool sent = await ApiService.createEvent(
      type: 'join_truck_request',
      role: 'farmer',
      userName: widget.userName,
      payload: {
        'truckSpaceEventId': spaceEvent['id'],
        'truckId': p['truckId'],
        'transporterName': spaceEvent['userName'],
        'from': p['from'],
        'to': p['to'],
        'item': _itemController.text.trim(),
        'weightKg': weight,
        'expectedSplitPrice': weight * (p['pricePerKg'] ?? 0),
      },
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sent ? 'Join request sent to transporter.' : 'Failed.')));
    if (sent) _refreshData();
  }

  Future<void> _respondToRetailerDemand(Map<String, dynamic> demandEvent, String decision, {double? counterPrice}) async {
    final Map<String, dynamic> p = (demandEvent['payload'] as Map<String, dynamic>? ?? {});
    final bool sent = await ApiService.createEvent(
      type: 'retailer_demand_decision',
      role: 'farmer',
      userName: widget.userName,
      payload: {
        'retailerDemandEventId': demandEvent['id'],
        'retailerName': demandEvent['userName'],
        'goods': p['goods'],
        'decision': decision,
        'counterPrice': counterPrice,
      },
    );
    if (sent) _refreshData();
  }

  Future<void> _retailerCounterDialog(Map<String, dynamic> demandEvent) async {
    final TextEditingController c = TextEditingController();
    final double? res = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Counter Offer to Retailer'),
        content: TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Your Price (Rs)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, double.tryParse(c.text)), child: const Text('Send')),
        ],
      ),
    );
    if (res != null) _respondToRetailerDemand(demandEvent, 'counter', counterPrice: res);
  }

  Future<void> _respondToCounterOffer(Map<String, dynamic> transporterCounterEvent, String decision) async {
    final Map<String, dynamic> p = (transporterCounterEvent['payload'] as Map<String, dynamic>? ?? {});
    final bool sent = await ApiService.createEvent(
      type: 'farmer_counter_response',
      role: 'farmer',
      userName: widget.userName,
      payload: {
        'requestCode': p['requestCode'],
        'transporterName': transporterCounterEvent['userName'],
        'decision': decision,
      },
    );
    if (sent) _refreshData();
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, String> decisionByCode = {};
    final List<Map<String, dynamic>> pendingCounterOffers = [];
    final Map<String, String> farmerCounterResponseByCode = {};

    for (final d in _decisions) {
      final p = (d['payload'] as Map<String, dynamic>? ?? {});
      final code = p['requestCode']?.toString() ?? '';
      final decision = p['decision']?.toString() ?? '';
      if (code.isNotEmpty && !decisionByCode.containsKey(code)) {
        decisionByCode[code] = decision;
        if (decision == 'counter') pendingCounterOffers.add(d);
      }
    }

    final Set<String> allocatedCodes = _allocations.map((a) => (a['payload'] as Map)['requestCode']?.toString() ?? '').toSet();

    final Map<String, Map<String, dynamic>> retailerDecisionByDemandId = {};
    for (final fdd in _farmerDemandDecisions) {
      final p = (fdd['payload'] as Map<String, dynamic>? ?? {});
      final id = p['retailerDemandEventId']?.toString() ?? '';
      if (id.isNotEmpty) retailerDecisionByDemandId[id] = p;
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.userName), backgroundColor: Colors.green, actions: [IconButton(onPressed: _refreshData, icon: const Icon(Icons.refresh))]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('New Transport Request', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 10),
                  TextField(controller: _itemController, decoration: const InputDecoration(labelText: 'Produce Item (e.g. Tomato)', border: OutlineInputBorder())),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _fromController,
                          decoration: const InputDecoration(labelText: 'From', border: OutlineInputBorder()),
                          onChanged: (_) {
                            _recalculateDistance();
                            setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _toController,
                          decoration: const InputDecoration(labelText: 'To', border: OutlineInputBorder()),
                          onChanged: (_) {
                            _recalculateDistance();
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _distanceController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Distance (km) - Auto',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _weightController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Weight (kg)', border: OutlineInputBorder()),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _vehicle,
                    decoration: const InputDecoration(labelText: 'Vehicle', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'mini', child: Text('Mini')),
                      DropdownMenuItem(value: 'pickup', child: Text('Pickup')),
                      DropdownMenuItem(value: 'medium', child: Text('Medium')),
                      DropdownMenuItem(value: 'large', child: Text('Large')),
                      DropdownMenuItem(value: 'refrigerated', child: Text('Refrigerated')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _vehicle = v);
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Farmer notes for truck driver (packaging, timing, fragile, etc.)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  SwitchListTile(
                    value: _shareTruck,
                    title: const Text('Allow shared truck with other farmers'),
                    contentPadding: EdgeInsets.zero,
                    onChanged: (v) => setState(() => _shareTruck = v),
                  ),
                  Text('Estimated Trip Price: Rs ${_price.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _submitTransportRequest,
                      child: const Text('Submit Request'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('My Request History (${_myRequestHistory.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
          ..._myRequestHistory.take(8).map((event) {
            final String type = (event['type'] ?? '').toString();
            final Map<String, dynamic> p = (event['payload'] as Map<String, dynamic>? ?? {});
            final String requestCode = (p['requestCode'] ?? '').toString();
            final String route = '${p['from'] ?? '-'} -> ${p['to'] ?? '-'}';
            final String item = (p['item'] ?? p['goods'] ?? '-').toString();
            final String weight = (p['weightKg'] ?? '-').toString();
            final String price = (p['proposedPrice'] ?? p['expectedSplitPrice'] ?? '-').toString();

            String status = 'Pending';
            if (type == 'join_truck_request') {
              status = 'Join Request Sent';
            }
            if (requestCode.isNotEmpty && decisionByCode.containsKey(requestCode)) {
              status = decisionByCode[requestCode]!;
            }
            if (requestCode.isNotEmpty && farmerCounterResponseByCode.containsKey(requestCode)) {
              status = 'Counter ${farmerCounterResponseByCode[requestCode]}';
            }
            if (requestCode.isNotEmpty && allocatedCodes.contains(requestCode)) {
              status = 'Allocated to Truck';
            }

            return Card(
              child: ListTile(
                dense: true,
                title: Text('${requestCode.isEmpty ? type : requestCode} | $item ($weight kg)'),
                subtitle: Text('$route | Price: Rs $price | Status: $status'),
              ),
            );
          }),
          const SizedBox(height: 8),
          Text('Counter Offers From Transporter (${pendingCounterOffers.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
          ...pendingCounterOffers.take(5).map((offer) {
            final Map<String, dynamic> p = (offer['payload'] as Map<String, dynamic>? ?? {});
            final String requestCode = (p['requestCode'] ?? '-').toString();
            final String route = '${p['from'] ?? '-'} -> ${p['to'] ?? '-'}';
            final String counterPrice = (p['counterPrice'] ?? '-').toString();
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Request: $requestCode', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Route: $route'),
                    Text('Counter Price: Rs $counterPrice | By ${offer['userName'] ?? '-'}'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _respondToCounterOffer(offer, 'accepted'),
                            child: const Text('Accept Counter'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _respondToCounterOffer(offer, 'rejected'),
                            child: const Text('Reject Counter'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          Text('Transporter Decisions (${_decisions.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
          ..._decisions.take(5).map((d) {
            final Map<String, dynamic> p = (d['payload'] as Map<String, dynamic>? ?? {});
            return ListTile(
              dense: true,
              title: Text('${p['decision'] ?? '-'} | ${p['requestCode'] ?? ''}'),
              subtitle: Text('By ${d['userName'] ?? 'transporter'} | Counter: ${p['counterPrice'] ?? '-'}'),
            );
          }),
          const SizedBox(height: 8),
          Text('Retailer Demands (${_demands.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (_loading) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
          ..._demands.take(5).map((d) {
            final Map<String, dynamic> p = (d['payload'] as Map<String, dynamic>? ?? {});
            final String demandId = (d['id'] ?? '').toString();
            final Map<String, dynamic>? myDecision = retailerDecisionByDemandId[demandId];
            final bool locked = myDecision != null;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${p['goods'] ?? 'Goods'} - ${p['quantityKg'] ?? '-'} kg', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('${p['city'] ?? '-'} | Offer Rs ${p['offerPrice'] ?? '-'} | by ${d['userName'] ?? 'retailer'}'),
                    if (locked)
                      Text(
                        'Your response: ${(myDecision['decision'] ?? '-').toString().toUpperCase()} ${myDecision['counterPrice'] != null ? '| Counter Rs ${myDecision['counterPrice']}' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: locked ? null : () => _respondToRetailerDemand(d, 'accepted'),
                          child: const Text('Accept'),
                        ),
                        OutlinedButton(
                          onPressed: locked ? null : () => _respondToRetailerDemand(d, 'rejected'),
                          child: const Text('Reject'),
                        ),
                        OutlinedButton(
                          onPressed: locked ? null : () => _retailerCounterDialog(d),
                          child: const Text('Counter'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          Text('Available Shared Trucks (${_spaces.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
          ..._spaces.take(6).map((s) {
            final Map<String, dynamic> p = (s['payload'] as Map<String, dynamic>? ?? {});
            return Card(
              child: ListTile(
                title: Text('${p['truckId'] ?? 'Truck'} | ${p['from'] ?? '-'} -> ${p['to'] ?? '-'}'),
                subtitle: Text('Remaining: ${p['remainingKg'] ?? '-'} kg | Rs/kg: ${(p['pricePerKg'] ?? '-').toString()}'),
                trailing: TextButton(
                  onPressed: () => _joinSharedTruck(s),
                  child: const Text('Join'),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class TransporterDashboard extends StatefulWidget {
  final String userName;
  const TransporterDashboard({super.key, required this.userName});

  @override
  State<TransporterDashboard> createState() => _TransporterDashboardState();
}

class _TransporterDashboardState extends State<TransporterDashboard> {
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;
  final TextEditingController _truckIdController = TextEditingController(text: 'MH-12-3909');
  final TextEditingController _fromController = TextEditingController(text: 'Nashik');
  final TextEditingController _toController = TextEditingController(text: 'Pune');
  final TextEditingController _capacityController = TextEditingController(text: '2000');
  final TextEditingController _remainingController = TextEditingController(text: '600');
  final TextEditingController _baseTripPriceController = TextEditingController(text: '9000');

  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _joinRequests = [];
  List<Map<String, dynamic>> _allocations = [];
  List<Map<String, dynamic>> _myDecisions = [];

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _truckIdController.dispose();
    _fromController.dispose();
    _toController.dispose();
    _capacityController.dispose();
    _remainingController.dispose();
    _baseTripPriceController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    RealtimeService.instance.ensureConnected();
    _wsSubscription = RealtimeService.instance.events.listen((_) {
      if (mounted) {
        _refreshRequests();
      }
    });
    _refreshRequests();
  }

  Future<void> _refreshRequests() async {
    final List<Map<String, dynamic>> requests = await ApiService.fetchEvents(type: 'transport_request');
    final List<Map<String, dynamic>> joins = await ApiService.fetchEvents(type: 'join_truck_request');
    final List<Map<String, dynamic>> allocations = await ApiService.fetchEvents(type: 'truck_allocation');
    final List<Map<String, dynamic>> decisions = await ApiService.fetchEvents(type: 'transporter_decision');
    if (!mounted) {
      return;
    }
    setState(() {
      _requests = requests;
      _joinRequests = joins;
      _allocations = allocations;
      _myDecisions = decisions.where((d) => (d['userName'] ?? '') == widget.userName).toList();
    });
  }

  Future<void> _broadcastSpace() async {
    final String from = _fromController.text.trim();
    final String to = _toController.text.trim();
    final String truckId = _truckIdController.text.trim();
    final double capacity = double.tryParse(_capacityController.text.trim()) ?? 0;
    final double remaining = double.tryParse(_remainingController.text.trim()) ?? 0;
    final double baseTripPrice = double.tryParse(_baseTripPriceController.text.trim()) ?? 0;

    if (from.isEmpty || to.isEmpty || truckId.isEmpty || capacity <= 0 || remaining < 0 || baseTripPrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill truck, route, capacity, remaining, and base trip price.')),
      );
      return;
    }

    final bool sent = await ApiService.createEvent(
      type: 'truck_space',
      role: 'transporter',
      userName: widget.userName,
      payload: {
        'truckId': truckId,
        'from': from,
        'to': to,
        'routeKey': _routeKey(from, to),
        'capacityKg': capacity,
        'remainingKg': remaining,
        'baseTripPrice': baseTripPrice,
        'pricePerKg': baseTripPrice / capacity,
      },
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sent ? 'Truck space shared.' : 'Backend unavailable.')));
    if (sent) {
      await _refreshRequests();
    }
  }

  Future<void> _respondToRequest(
    Map<String, dynamic> requestEvent,
    String decision, {
    double? counterPrice,
  }) async {
    final Map<String, dynamic> payload = (requestEvent['payload'] as Map<String, dynamic>? ?? {});
    final bool sent = await ApiService.createEvent(
      type: 'transporter_decision',
      role: 'transporter',
      userName: widget.userName,
      payload: {
        'requestEventId': requestEvent['id'],
        'requestCode': payload['requestCode'],
        'farmerName': requestEvent['userName'],
        'from': payload['from'],
        'to': payload['to'],
        'routeKey': payload['routeKey'],
        'decision': decision,
        'counterPrice': counterPrice,
      },
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sent ? 'Decision saved.' : 'Could not sync decision.')));
    if (sent) {
      await _refreshRequests();
    }
  }

  Future<void> _allocateToTruck(Map<String, dynamic> requestEvent) async {
    final String truckId = _truckIdController.text.trim();
    if (truckId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter truck ID before allocation.')),
      );
      return;
    }

    final Map<String, dynamic> p = (requestEvent['payload'] as Map<String, dynamic>? ?? {});
    final bool sent = await ApiService.createEvent(
      type: 'truck_allocation',
      role: 'transporter',
      userName: widget.userName,
      payload: {
        'truckId': truckId,
        'requestCode': p['requestCode'],
        'farmerName': requestEvent['userName'],
        'routeKey': p['routeKey'],
        'item': p['item'],
        'weightKg': p['weightKg'],
        'proposedPrice': p['proposedPrice'],
      },
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sent ? 'Added to shared truck.' : 'Allocation failed.')));
    if (sent) {
      await _refreshRequests();
    }
  }

  Future<void> _counterDialog(Map<String, dynamic> requestEvent) async {
    final TextEditingController counterController = TextEditingController();
    final double? counter = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Counter Offer'),
          content: TextField(
            controller: counterController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Counter price', border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, double.tryParse(counterController.text.trim())),
              child: const Text('Send'),
            ),
          ],
        );
      },
    );
    if (counter != null && counter > 0) {
      await _respondToRequest(requestEvent, 'counter', counterPrice: counter);
    }
  }

  Map<String, Map<String, dynamic>> _buildSplitSummary() {
    final Map<String, Map<String, dynamic>> grouped = {};
    for (final Map<String, dynamic> event in _allocations) {
      final Map<String, dynamic> p = (event['payload'] as Map<String, dynamic>? ?? {});
      final String truckId = (p['truckId'] ?? '').toString();
      if (truckId.isEmpty) {
        continue;
      }
      final double weight = (p['weightKg'] is num) ? (p['weightKg'] as num).toDouble() : 0;
      final double price = (p['proposedPrice'] is num) ? (p['proposedPrice'] as num).toDouble() : 0;
      grouped.putIfAbsent(
        truckId,
        () => {'farmers': 0, 'totalWeight': 0.0, 'totalPrice': 0.0},
      );
      grouped[truckId]!['farmers'] = (grouped[truckId]!['farmers'] as int) + 1;
      grouped[truckId]!['totalWeight'] = (grouped[truckId]!['totalWeight'] as double) + weight;
      grouped[truckId]!['totalPrice'] = (grouped[truckId]!['totalPrice'] as double) + price;
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, String> decisionByRequestCode = <String, String>{};
    for (final Map<String, dynamic> d in _myDecisions) {
      final Map<String, dynamic> p = (d['payload'] as Map<String, dynamic>? ?? {});
      final String code = (p['requestCode'] ?? '').toString();
      final String decision = (p['decision'] ?? '').toString();
      // API returns newest decisions first; keep first entry per requestCode.
      if (code.isNotEmpty && decision.isNotEmpty && !decisionByRequestCode.containsKey(code)) {
        decisionByRequestCode[code] = decision;
      }
    }

    final List<Map<String, dynamic>> acceptedRequests = _requests.where((r) {
      final Map<String, dynamic> p = (r['payload'] as Map<String, dynamic>? ?? {});
      return decisionByRequestCode[(p['requestCode'] ?? '').toString()] == 'accepted';
    }).toList();

    final List<Map<String, dynamic>> rejectedRequests = _requests.where((r) {
      final Map<String, dynamic> p = (r['payload'] as Map<String, dynamic>? ?? {});
      return decisionByRequestCode[(p['requestCode'] ?? '').toString()] == 'rejected';
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userName),
        backgroundColor: Colors.blue,
        actions: [IconButton(onPressed: _refreshRequests, icon: const Icon(Icons.refresh))],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(15)),
              child: Column(
                children: [
                  const Text('Transporter Shared Truck Panel', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _truckIdController,
                    decoration: const InputDecoration(labelText: 'Truck ID', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _fromController,
                          decoration: const InputDecoration(labelText: 'From', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _toController,
                          decoration: const InputDecoration(labelText: 'To', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _capacityController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Capacity kg', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _remainingController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Remaining kg', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _baseTripPriceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Base trip price (Rs)', border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Incoming Farmer Requests', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            SizedBox(
              height: 220,
              child: ListView.builder(
                itemCount: _requests.length,
                itemBuilder: (context, index) {
                  final Map<String, dynamic> req = _requests[index];
                  final Map<String, dynamic> payload = (req['payload'] as Map<String, dynamic>? ?? {});
                  final String requestCode = (payload['requestCode'] ?? '').toString();
                  final String decision = decisionByRequestCode[requestCode] ?? '';
                  final bool isAccepted = decision == 'accepted';
                  final bool isRejected = decision == 'rejected';
                  return Card(
                    color: isAccepted
                        ? Colors.green[100]
                        : isRejected
                            ? Colors.red[100]
                            : null,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${payload['item'] ?? 'Item'} | ${payload['weightKg'] ?? '-'} kg', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('${payload['from'] ?? '-'} -> ${payload['to'] ?? '-'}'),
                          Text('Price: Rs ${(payload['proposedPrice'] ?? '-').toString()} | Farmer: ${req['userName'] ?? '-'}'),
                          if (decision.isNotEmpty)
                            Text(
                              'Status: ${decision.toUpperCase()}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isAccepted
                                    ? Colors.green[800]
                                    : isRejected
                                        ? Colors.red[800]
                                        : Colors.blueGrey,
                              ),
                            ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: (isAccepted || isRejected) ? null : () => _respondToRequest(req, 'accepted'),
                                child: const Text('Accept'),
                              ),
                              OutlinedButton(
                                onPressed: (isAccepted || isRejected) ? null : () => _respondToRequest(req, 'rejected'),
                                child: const Text('Reject'),
                              ),
                              OutlinedButton(
                                onPressed: (isAccepted || isRejected) ? null : () => _counterDialog(req),
                                child: const Text('Counter'),
                              ),
                              ElevatedButton(
                                onPressed: isRejected ? null : () => _allocateToTruck(req),
                                child: const Text('Add to Shared Truck'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Accepted Requests (${acceptedRequests.length})', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            ),
            ...acceptedRequests.take(5).map((req) {
              final Map<String, dynamic> p = (req['payload'] as Map<String, dynamic>? ?? {});
              return Card(
                color: Colors.green[100],
                child: ListTile(
                  dense: true,
                  title: Text('${p['requestCode'] ?? '-'} | ${p['item'] ?? '-'} (${p['weightKg'] ?? '-'} kg)'),
                  subtitle: Text('${p['from'] ?? '-'} -> ${p['to'] ?? '-'}'),
                ),
              );
            }),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Rejected Requests (${rejectedRequests.length})', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
            ),
            ...rejectedRequests.take(5).map((req) {
              final Map<String, dynamic> p = (req['payload'] as Map<String, dynamic>? ?? {});
              return Card(
                color: Colors.red[100],
                child: ListTile(
                  dense: true,
                  title: Text('${p['requestCode'] ?? '-'} | ${p['item'] ?? '-'} (${p['weightKg'] ?? '-'} kg)'),
                  subtitle: Text('${p['from'] ?? '-'} -> ${p['to'] ?? '-'}'),
                ),
              );
            }),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Farmer Join Requests: ${_joinRequests.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ..._joinRequests.take(4).map((j) {
              final Map<String, dynamic> p = (j['payload'] as Map<String, dynamic>? ?? {});
              return ListTile(
                dense: true,
                title: Text('${p['item'] ?? '-'} | ${p['weightKg'] ?? '-'} kg'),
                subtitle: Text('Truck: ${p['truckId'] ?? '-'} | Farmer: ${j['userName'] ?? '-'}'),
              );
            }),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Shared Truck Split Summary', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            ..._buildSplitSummary().entries.map((entry) {
              final Map<String, dynamic> s = entry.value;
              final double totalWeight = (s['totalWeight'] as double);
              final double totalPrice = (s['totalPrice'] as double);
              final double perKg = totalWeight > 0 ? totalPrice / totalWeight : 0;
              return ListTile(
                dense: true,
                title: Text('${entry.key} | Farmers: ${s['farmers']}'),
                subtitle: Text('Total: ${totalWeight.toStringAsFixed(1)} kg | Rs/kg: ${perKg.toStringAsFixed(2)}'),
              );
            }),
            ElevatedButton(
              onPressed: _broadcastSpace,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: const Text('Broadcast Space Available', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

class RetailerDashboard extends StatefulWidget {
  final String userName;
  const RetailerDashboard({super.key, required this.userName});

  @override
  State<RetailerDashboard> createState() => _RetailerDashboardState();
}

class _RetailerDashboardState extends State<RetailerDashboard> {
  final TextEditingController _qtyController = TextEditingController();
  final TextEditingController _offerPriceController = TextEditingController(text: '0');
  final List<String> _goodsOptions = <String>['Banana', 'Grapes', 'Tomato', 'Onion', 'Mango', 'Potato'];
  final List<String> _cityOptions = <String>['Pune', 'Nashik', 'Mumbai', 'Kolhapur', 'Nagpur'];
  String _selectedGoods = 'Banana';
  String _selectedCity = 'Pune';
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;

  List<Map<String, dynamic>> _myDemands = [];
  List<Map<String, dynamic>> _farmerRequests = [];
  List<Map<String, dynamic>> _decisions = [];
  List<Map<String, dynamic>> _farmerDemandDecisions = [];

  @override
  void initState() {
    super.initState();
    RealtimeService.instance.ensureConnected();
    _wsSubscription = RealtimeService.instance.events.listen((_) {
      if (mounted) {
        _refreshMyDemands();
      }
    });
    _refreshMyDemands();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _offerPriceController.dispose();
    _wsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _refreshMyDemands() async {
    final List<Map<String, dynamic>> demandEvents = await ApiService.fetchEvents(type: 'retailer_demand');
    final List<Map<String, dynamic>> requestEvents = await ApiService.fetchEvents(type: 'transport_request');
    final List<Map<String, dynamic>> decisionEvents = await ApiService.fetchEvents(type: 'transporter_decision');
    final List<Map<String, dynamic>> farmerDemandDecisionEvents = await ApiService.fetchEvents(type: 'retailer_demand_decision');
    if (!mounted) {
      return;
    }

    final List<Map<String, dynamic>> myDemands = demandEvents.where((e) => e['userName'] == widget.userName).toList();
    final Set<String> myDemandIds = myDemands.map((d) => (d['id'] ?? '').toString()).toSet();

    setState(() {
      _myDemands = myDemands;
      _farmerRequests = requestEvents;
      _decisions = decisionEvents;
      _farmerDemandDecisions = farmerDemandDecisionEvents.where((e) {
        final Map<String, dynamic> p = (e['payload'] as Map<String, dynamic>? ?? {});
        final String demandId = (p['retailerDemandEventId'] ?? '').toString();
        final String retailerName = (p['retailerName'] ?? '').toString();
        return myDemandIds.contains(demandId) || retailerName == widget.userName;
      }).toList();
    });
  }

  Future<void> _sendDemand() async {
    final String goods = _selectedGoods;
    final int qty = int.tryParse(_qtyController.text.trim()) ?? 0;
    final String city = _selectedCity;
    final double offerPrice = double.tryParse(_offerPriceController.text.trim()) ?? 0;

    if (goods.isEmpty || qty <= 0 || city.isEmpty || offerPrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter goods, quantity, city, and offer price.')),
      );
      return;
    }

    final bool sent = await ApiService.createEvent(
      type: 'retailer_demand',
      role: 'retailer',
      userName: widget.userName,
      payload: {
        'goods': goods,
        'quantityKg': qty,
        'city': city,
        'offerPrice': offerPrice,
      },
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(sent ? 'Demand sent to main MongoDB feed.' : 'Could not reach backend.')),
    );

    if (sent) {
      _qtyController.clear();
      _offerPriceController.clear();
      await _refreshMyDemands();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.userName),
        backgroundColor: Colors.orange,
        actions: [IconButton(onPressed: _refreshMyDemands, icon: const Icon(Icons.refresh))],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedGoods,
              decoration: const InputDecoration(labelText: 'Select Item', border: OutlineInputBorder()),
              items: _goodsOptions
                  .map((g) => DropdownMenuItem<String>(value: g, child: Text(g)))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedGoods = value);
                }
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity Needed (kg)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _selectedCity,
              decoration: const InputDecoration(labelText: 'Delivery City', border: OutlineInputBorder()),
              items: _cityOptions
                  .map((c) => DropdownMenuItem<String>(value: c, child: Text(c)))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedCity = value);
                }
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _offerPriceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Offer Price (Rs)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, minimumSize: const Size(double.infinity, 50)),
              onPressed: _sendDemand,
              child: const Text('SEND DEMAND TO MAIN SERVER', style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('My Demand History (${_myDemands.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _myDemands.length,
                itemBuilder: (ctx, idx) {
                  final Map<String, dynamic> d = _myDemands[idx];
                  final Map<String, dynamic> p = (d['payload'] as Map<String, dynamic>? ?? {});
                  final String demandId = (d['id'] ?? '').toString();

                  final List<Map<String, dynamic>> responses = _farmerDemandDecisions.where((e) {
                    final Map<String, dynamic> rp = (e['payload'] as Map<String, dynamic>? ?? {});
                    return (rp['retailerDemandEventId'] ?? '').toString() == demandId;
                  }).toList();

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${p['goods'] ?? 'Goods'} - ${p['quantityKg'] ?? '-'} kg', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text('City: ${p['city'] ?? '-'} | Offer: Rs ${p['offerPrice'] ?? '-'}'),
                          const Divider(),
                          Text('Farmer Responses (${responses.length}):', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ...responses.map((r) {
                            final Map<String, dynamic> rp = (r['payload'] as Map<String, dynamic>? ?? {});
                            final String decision = (rp['decision'] ?? '-').toString().toUpperCase();
                            final String counter = rp['counterPrice'] != null ? '| Counter Rs ${rp['counterPrice']}' : '';
                            return Text('• ${r['userName'] ?? 'Farmer'}: $decision $counter', style: const TextStyle(fontSize: 12));
                          }),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _routeKey(String f, String t) => '${f.toLowerCase().trim()}_${t.toLowerCase().trim()}';
