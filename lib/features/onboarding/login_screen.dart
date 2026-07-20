import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/premium_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _useBiometrics = false;
  bool _isLoggingIn = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleEmailLogin() {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoggingIn = true;
      });
      // Simulate network request
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() {
            _isLoggingIn = false;
          });
          context.go('/');
        }
      });
    }
  }

  void _handleOAuthLogin(String method) {
    setState(() {
      _isLoggingIn = true;
    });
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        setState(() {
          _isLoggingIn = false;
        });
        context.go('/');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              
              // App Logo / Icon Header
              Center(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.layers_outlined,
                        color: AppColors.goldDark,
                        size: 48,
                      ),
                    ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
                    const SizedBox(height: 16),
                    Text(
                      'Welcome to CoinVault AI',
                      style: AppTypography.sectionHeader.copyWith(fontSize: 24),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Discover. Identify. Collect. Invest.',
                      style: AppTypography.bodyMuted,
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 48),

              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Email Input
                    Text('Email Address', style: AppTypography.caption),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _emailController,
                      style: AppTypography.bodyMedium,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: 'name@domain.com',
                        hintStyle: AppTypography.bodyMuted,
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.borderLight, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty || !value.contains('@')) {
                          return 'Please enter a valid email address';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 20),

                    // Password Input
                    Text('Password', style: AppTypography.caption),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: AppTypography.bodyMedium,
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        hintStyle: AppTypography.bodyMuted,
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.borderLight, width: 1),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.gold, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: AppColors.textSecondary,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    // Biometrics toggle mockup
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(Icons.face_retouching_natural, color: AppColors.goldDark, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Enable Face ID / Biometrics',
                                  style: AppTypography.bodyMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Switch.adaptive(
                          value: _useBiometrics,
                          activeColor: AppColors.gold,
                          onChanged: (val) {
                            setState(() {
                              _useBiometrics = val;
                            });
                          },
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Submit email login button
                    SizedBox(
                      width: double.infinity,
                      child: GoldButton(
                        text: 'Sign In with Email',
                        isLoading: _isLoggingIn,
                        onPressed: _handleEmailLogin,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // OR divider line
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('or continue with', style: AppTypography.caption),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),

              const SizedBox(height: 24),

              // OAuth Social Buttons (Google & Apple)
              Row(
                children: [
                  Expanded(
                    child: GoldButton(
                      text: 'Google',
                      isSecondary: true,
                      icon: Icons.g_mobiledata,
                      onPressed: () => _handleOAuthLogin('Google'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GoldButton(
                      text: 'Apple',
                      isSecondary: true,
                      icon: Icons.apple,
                      onPressed: () => _handleOAuthLogin('Apple'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Guest Bypass Button
              Center(
                child: TextButton(
                  onPressed: () {
                    // Instantly route to dashboard bypass
                    context.go('/');
                  },
                  child: Text(
                    'Bypass and Enter as Guest',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.goldDark,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
