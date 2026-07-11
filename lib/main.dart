import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'branding/branding.dart';
import 'branding/branding_service.dart';
import 'config/app_config.dart';
import 'services/api_service.dart';
import 'services/background_service.dart';
import 'services/update_service.dart';

// =============================================================================
// DESIGN TOKENS
// =============================================================================
abstract final class AppColors {
  // Primary gradient — deep navy (fixed dark identity, not brand-configurable)
  static const Color primary = Color(0xFF0D1B2A);
  static const Color primaryLight = Color(0xFF1B2D45);

  // Accent — the action color. RUNTIME-mutable via [applyBranding]; do not use
  // in `const` expressions.
  static Color accent = const Color(0xFF00C9A7);
  static Color accentDark = const Color(0xFF00A388);

  /// Apply a resolved [Branding] to the runtime-mutable accent tokens.
  static void applyBranding(Branding b) {
    accent = b.accent;
    accentDark = b.accentDark;
  }

  // Status
  static const Color success = Color(0xFF00E676);
  static const Color successDark = Color(0xFF00C853);
  static const Color danger = Color(0xFFFF5252);
  static const Color dangerDark = Color(0xFFD32F2F);
  static const Color warning = Color(0xFFFFAB40);

  // Surfaces
  static const Color surface = Color(0xFF112240);
  static const Color surfaceLight = Color(0xFF1A3358);
  static const Color cardDark = Color(0xFF0A192F);

  // Text
  static const Color textPrimary = Color(0xFFE6F1FF);
  static const Color textSecondary = Color(0xFF8892B0);
  static const Color textMuted = Color(0xFF5A6A8A);
}

// =============================================================================
// MAIN
// =============================================================================
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load cached (or compile-time fallback) branding BEFORE the first frame so the
  // app opens instantly and offline, already themed (plan §5.1 N2). Never throws.
  final brand = (await BrandingService.loadCached()).effective;
  AppColors.applyBranding(brand);

  await initializeService();
  runApp(DriverApp(initialBranding: brand));
}

class DriverApp extends StatefulWidget {
  final Branding initialBranding;
  const DriverApp({super.key, required this.initialBranding});

  @override
  State<DriverApp> createState() => _DriverAppState();
}

class _DriverAppState extends State<DriverApp> {
  late Branding _branding = widget.initialBranding;

  @override
  void initState() {
    super.initState();
    // Background refresh of the platform brand after the first frame. A failure
    // is silently ignored (plan E7) — branding is cosmetic.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final fetched = (await BrandingService.fetchAndCache()).effective;
      if (!mounted) return;
      AppColors.applyBranding(fetched);
      setState(() => _branding = fetched);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: _branding.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.primary,
        colorScheme: ColorScheme.dark(
          primary: AppColors.accent,
          secondary: AppColors.accentDark,
          surface: AppColors.surface,
          onPrimary: AppColors.primary,
          onSurface: AppColors.textPrimary,
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// =============================================================================
// SPLASH SCREEN — Premium animated entry
// =============================================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _scaleAnim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.elasticOut),
    );
    _animController.forward();
    _checkLogin();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _checkLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('api_token');
    final driverName = prefs.getString('driver_name');

    await Future.delayed(const Duration(milliseconds: 1800));

    if (!mounted) return;

    if (token != null && token.isNotEmpty) {
      Navigator.pushReplacement(
        context,
        _fadeRoute(
          DashboardScreen(
            token: token,
            driverName: driverName ?? 'Driver',
            vehicleNumber: prefs.getString('vehicle_number') ?? '',
            schoolName: prefs.getString('school_name') ?? '',
          ),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        _fadeRoute(const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, AppColors.cardDark, AppColors.primaryLight],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(
              scale: _scaleAnim,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Glowing icon
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [AppColors.accent, AppColors.accentDark],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withOpacity(0.4),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.local_shipping_rounded,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    AppConfig.appName,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'School Vehicle GPS Tracking',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.accent.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// LOGIN SCREEN — Premium glass-morphism style
// =============================================================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _schoolEmailController = TextEditingController();
  final _vehicleNumberController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isDemoMode = false;
  String _errorMessage = '';

  late AnimationController _animController;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
    _checkDemoMode();
  }

  Future<void> _checkDemoMode() async {
    final isDemo = await ApiService.checkDemoMode();
    if (mounted) setState(() => _isDemoMode = isDemo);
  }

  @override
  void dispose() {
    _animController.dispose();
    _schoolEmailController.dispose();
    _vehicleNumberController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final result = await ApiService.login(
        _schoolEmailController.text.trim(),
        _vehicleNumberController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;

      if (result['status'] == 'success') {
        final data = result['data'];
        Navigator.pushReplacement(
          context,
          _fadeRoute(
            DashboardScreen(
              token: data['api_token'],
              driverName: data['driver_name'] ?? 'Driver',
              vehicleNumber: data['vehicle_number'] ?? '',
              schoolName: data['school_name'] ?? '',
            ),
          ),
        );
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Login failed. Please try again.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error. Please check your internet.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _demoLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final result = await ApiService.demoLogin();
      if (!mounted) return;

      if (result['status'] == 'success') {
        final data = result['data'];
        Navigator.pushReplacement(
          context,
          _fadeRoute(
            DashboardScreen(
              token: data['api_token'],
              driverName: data['driver_name'] ?? 'Driver',
              vehicleNumber: data['vehicle_number'] ?? '',
              schoolName: data['school_name'] ?? '',
            ),
          ),
        );
      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Demo login is unavailable right now.';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error. Please check your internet.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
      prefixIcon: Icon(icon, color: AppColors.accent, size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppColors.surface.withOpacity(0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.textMuted.withOpacity(0.2)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.textMuted.withOpacity(0.15)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.cardDark, AppColors.primary],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [AppColors.accent, AppColors.accentDark],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accent.withOpacity(0.3),
                                blurRadius: 24,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.local_shipping_rounded,
                            size: 36,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Driver Login',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Sign in to start tracking',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 36),

                        // Error message
                        if (_errorMessage.isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage,
                                    style: const TextStyle(color: AppColors.danger, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // School email
                        TextFormField(
                          controller: _schoolEmailController,
                          decoration: _inputDecoration(
                            label: 'School Email / Domain',
                            icon: Icons.school_rounded,
                          ),
                          keyboardType: TextInputType.emailAddress,
                          style: const TextStyle(color: AppColors.textPrimary),
                          validator: (v) =>
                              v == null || v.isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: 16),

                        // Vehicle number
                        TextFormField(
                          controller: _vehicleNumberController,
                          decoration: _inputDecoration(
                            label: 'Vehicle Number',
                            icon: Icons.directions_bus_rounded,
                          ),
                          textCapitalization: TextCapitalization.characters,
                          style: const TextStyle(color: AppColors.textPrimary),
                          validator: (v) =>
                              v == null || v.isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: 16),

                        // Password
                        TextFormField(
                          controller: _passwordController,
                          decoration: _inputDecoration(
                            label: 'Password',
                            icon: Icons.lock_outline_rounded,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: AppColors.textMuted,
                                size: 20,
                              ),
                              onPressed: () =>
                                  setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          obscureText: _obscurePassword,
                          style: const TextStyle(color: AppColors.textPrimary),
                          onFieldSubmitted: (_) => _login(),
                          validator: (v) =>
                              v == null || v.isEmpty ? 'Required' : null,
                        ),
                        const SizedBox(height: 32),

                        // Login button
                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [AppColors.accent, AppColors.accentDark],
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.accent.withOpacity(0.35),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'SIGN IN',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                            ),
                          ),
                        ),

                        // Demo quick-access (only when server is in demo mode)
                        if (_isDemoMode) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: OutlinedButton.icon(
                              onPressed: _isLoading ? null : _demoLogin,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.accent,
                                side: BorderSide(
                                    color: AppColors.accent.withOpacity(0.6)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: const Icon(Icons.bolt_rounded, size: 20),
                              label: const Text(
                                'DEMO LOGIN',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 40),

                        // Footer
                        Text(
                          AppConfig.poweredBy,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted.withOpacity(0.5),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// DASHBOARD SCREEN — Premium transport control center
// =============================================================================
class DashboardScreen extends StatefulWidget {
  final String token;
  final String driverName;
  final String vehicleNumber;
  final String schoolName;

  const DashboardScreen({
    super.key,
    required this.token,
    required this.driverName,
    required this.vehicleNumber,
    required this.schoolName,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  bool _isTripActive = false;
  bool _isToggling = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Once-per-run "update available" check (silent on any failure).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateService.maybePrompt(context);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _startPulse() {
    _pulseController.repeat(reverse: true);
  }

  void _stopPulse() {
    _pulseController.stop();
    _pulseController.reset();
  }

  Future<void> _toggleTrip() async {
    setState(() => _isToggling = true);

    try {
      if (!_isTripActive) {
        // ── Step 1: Check if GPS/Location Services are enabled ──
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.location_disabled, color: Colors.white, size: 18),
                  SizedBox(width: 10),
                  Expanded(child: Text('Location services are OFF. Please enable GPS.')),
                ],
              ),
              backgroundColor: AppColors.warning,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              action: SnackBarAction(
                label: 'OPEN SETTINGS',
                textColor: Colors.white,
                onPressed: () => Geolocator.openLocationSettings(),
              ),
            ),
          );
          setState(() => _isToggling = false);
          return;
        }

        // ── Step 2: Foreground location permission ──
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.location_off, color: Colors.white, size: 18),
                  SizedBox(width: 10),
                  Expanded(child: Text('Location permission is required to track.')),
                ],
              ),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              action: permission == LocationPermission.deniedForever
                  ? SnackBarAction(
                      label: 'SETTINGS',
                      textColor: Colors.white,
                      onPressed: () => Geolocator.openAppSettings(),
                    )
                  : null,
            ),
          );
          setState(() => _isToggling = false);
          return;
        }

        // ── Step 3: Background location permission (Android 10+) ──
        // Without this, the foreground service CANNOT access GPS when app is swiped away.
        // On Android 10+, this must be requested SEPARATELY after foreground is granted.
        if (permission == LocationPermission.whileInUse) {
          // Show explanation dialog first, then request
          if (!mounted) return;
          final shouldRequest = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(Icons.gps_fixed, color: AppColors.accent, size: 24),
                  const SizedBox(width: 10),
                  const Text('Background Location',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 18)),
                ],
              ),
              content: const Text(
                'For tracking to work when the app is closed, please select '
                '"Allow all the time" on the next screen.\n\n'
                'This ensures parents can see the bus location even when '
                'the app is in the background.',
                style: TextStyle(color: AppColors.textSecondary, height: 1.5),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Skip', style: TextStyle(color: AppColors.textMuted)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Continue', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );

          if (shouldRequest == true) {
            permission = await Geolocator.requestPermission();
          }
          // Even if they skip or only grant whileInUse, we proceed — the foreground
          // service will still work while the app is visible. It may stop when swiped.
        }
      }

      final result = await ApiService.toggleTrip(
        widget.token,
        _isTripActive ? 'stop' : 'start',
      );

      if (!mounted) return;

      if (result['status'] == 'success') {
        final service = FlutterBackgroundService();

        if (!_isTripActive) {
          await service.startService();
          _startPulse();
        } else {
          service.invoke('stopService');
          _stopPulse();
        }

        setState(() => _isTripActive = !_isTripActive);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  _isTripActive ? Icons.gps_fixed : Icons.gps_off,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  _isTripActive
                      ? 'Trip Started — Tracking ON'
                      : 'Trip Stopped — Tracking OFF',
                ),
              ],
            ),
            backgroundColor: _isTripActive ? AppColors.successDark : AppColors.warning,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Failed to toggle trip'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isToggling = false);
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Logout', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final service = FlutterBackgroundService();
      service.invoke('stopService');

      if (_isTripActive) {
        await ApiService.toggleTrip(widget.token, 'stop');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('api_token');
      await prefs.remove('driver_name');
      await prefs.remove('vehicle_number');
      await prefs.remove('school_name');

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        _fadeRoute(const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _isTripActive ? AppColors.success : AppColors.textMuted;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.cardDark, AppColors.primary],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom AppBar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hello, ${widget.driverName.split(' ').first} 👋',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.schoolName,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Status indicator dot
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                        boxShadow: _isTripActive
                            ? [BoxShadow(color: statusColor.withOpacity(0.5), blurRadius: 8)]
                            : null,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout_rounded, color: AppColors.textMuted),
                      tooltip: 'Logout',
                      onPressed: _logout,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Vehicle info card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.surfaceLight.withOpacity(0.7),
                        AppColors.surface.withOpacity(0.5),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.textMuted.withOpacity(0.1)),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      // Avatar
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              AppColors.accent.withOpacity(0.2),
                              AppColors.accentDark.withOpacity(0.1),
                            ],
                          ),
                          border: Border.all(color: AppColors.accent.withOpacity(0.3)),
                        ),
                        child: Icon(
                          Icons.person_rounded,
                          color: AppColors.accent,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.driverName,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.accent.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.accent.withOpacity(0.2)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.directions_bus_rounded,
                                          color: AppColors.accent, size: 14),
                                      const SizedBox(width: 6),
                                      Text(
                                        widget.vehicleNumber.isNotEmpty
                                            ? widget.vehicleNumber
                                            : 'N/A',
                                        style: TextStyle(
                                          color: AppColors.accent,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Trip control — center of screen
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // GPS status ring
                      AnimatedBuilder(
                        animation: _pulseAnim,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _isTripActive ? _pulseAnim.value : 1.0,
                            child: Container(
                              width: 130,
                              height: 130,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isTripActive
                                    ? AppColors.success.withOpacity(0.05)
                                    : AppColors.textMuted.withOpacity(0.05),
                                border: Border.all(
                                  color: _isTripActive
                                      ? AppColors.success.withOpacity(0.3)
                                      : AppColors.textMuted.withOpacity(0.15),
                                  width: 2,
                                ),
                                boxShadow: _isTripActive
                                    ? [
                                        BoxShadow(
                                          color: AppColors.success.withOpacity(0.15),
                                          blurRadius: 40,
                                          spreadRadius: 10,
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Icon(
                                _isTripActive ? Icons.gps_fixed_rounded : Icons.gps_off_rounded,
                                size: 56,
                                color: _isTripActive ? AppColors.success : AppColors.textMuted,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      // Status text
                      Text(
                        _isTripActive ? 'TRACKING ACTIVE' : 'TRACKING INACTIVE',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _isTripActive ? AppColors.success : AppColors.textMuted,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isTripActive
                            ? 'GPS location is being shared with parents'
                            : 'Tap the button below to start your trip',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 40),

                      // Big action button
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: SizedBox(
                          width: double.infinity,
                          height: 58,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: _isTripActive
                                    ? [AppColors.danger, AppColors.dangerDark]
                                    : [AppColors.success, AppColors.successDark],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: (_isTripActive ? AppColors.danger : AppColors.success)
                                      .withOpacity(0.35),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              onPressed: _isToggling ? null : _toggleTrip,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: _isToggling
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(
                                      _isTripActive
                                          ? Icons.stop_circle_rounded
                                          : Icons.play_circle_fill_rounded,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                              label: _isToggling
                                  ? const SizedBox.shrink()
                                  : Text(
                                      _isTripActive ? 'STOP TRIP' : 'START TRIP',
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom footer
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  AppConfig.appVersionLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted.withOpacity(0.4),
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

// =============================================================================
// SHARED UTILS
// =============================================================================
PageRouteBuilder<T> _fadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
    transitionDuration: const Duration(milliseconds: 400),
  );
}