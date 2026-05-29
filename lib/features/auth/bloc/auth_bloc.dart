import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../../../core/services/auth_service.dart';
import '../../../core/services/admin_service.dart';
import '../../../core/models/user.dart';
import '../../../core/config/app_config.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthService _authService;
  final AdminService _adminService;
  StreamSubscription? _authSubscription;
  bool _initialAuthCheckDone = false;

  AuthBloc({
    required AuthService authService,
    required AdminService adminService,
  })  : _authService = authService,
        _adminService = adminService,
        super(const AuthState()) {
    on<AuthCheckRequested>(_onAuthCheck);
    on<SignInRequested>(_onSignIn);
    on<SignUpRequested>(_onSignUp);
    on<SignOutRequested>(_onSignOut);
    on<EmailConfirmationReceived>(_onEmailConfirmed);
    on<AdminCheckRequested>(_onAdminCheck);
    on<DeepLinkReceived>(_onDeepLink);
    on<ClearAuthError>(_onClearError);

    _setupAuthListener();
  }

  void _setupAuthListener() {
    try {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
        (data) {
          debugPrint('🔍 AuthBloc: Auth state change: ${data.event}');
          if (data.event == AuthChangeEvent.signedIn ||
              data.event == AuthChangeEvent.userUpdated) {
            final user = data.session?.user;
            if (user != null && user.emailConfirmedAt != null) {
              add(const EmailConfirmationReceived());
            }
          }
          if (data.event == AuthChangeEvent.signedOut) {
            _initialAuthCheckDone = false;
            add(const AuthCheckRequested());
          }
        },
      );
    } catch (e) {
      debugPrint('⚠️ Auth listener setup failed: $e');
    }
  }

  Future<void> _onAuthCheck(
      AuthCheckRequested event, Emitter<AuthState> emit) async {
    debugPrint('🔍 AuthBloc._onAuthCheck: status=${state.status}');

    if (_initialAuthCheckDone && state.status == AuthStatus.authenticated) {
      debugPrint('🔍 AuthBloc: Already authenticated, skipping check');
      return;
    }

    if (state.status == AuthStatus.unknown) {
      emit(state.copyWith(status: AuthStatus.initializing, error: null));
    }

    try {
      if (!AppConfig.requiresAuth) {
        emit(state.copyWith(status: AuthStatus.authenticated, isAdmin: false));
        _initialAuthCheckDone = true;
        return;
      }

      await _authService.initialize();

      if (_authService.isAuthenticated && _authService.currentUser != null) {
        final user = _authService.currentUser!;

        if (!user.isApproved) {
          emit(state.copyWith(
            status: AuthStatus.unauthenticated,
            error: 'Your account is pending approval.',
          ));
          await _authService.signOut();
          return;
        }

        bool isAdmin = false;
        try {
          isAdmin = await _adminService.isAdmin();
        } catch (_) {
          isAdmin = false;
        }

        _initialAuthCheckDone = true;
        emit(state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          isAdmin: isAdmin,
        ));
        debugPrint('✅ AuthBloc: Authenticated as ${user.email}');
      } else {
        _initialAuthCheckDone = true;
        emit(const AuthState(status: AuthStatus.unauthenticated));
      }
    } catch (e) {
      debugPrint('❌ AuthBloc._onAuthCheck error: $e');
      emit(state.copyWith(
        status: AuthStatus.error,
        error: 'Connection failed. Please check your internet and try again.',
      ));
    }
  }

  Future<void> _onSignIn(
      SignInRequested event, Emitter<AuthState> emit) async {
    debugPrint('🔍 AuthBloc._onSignIn: ${event.email}');
    emit(state.copyWith(status: AuthStatus.authenticating, error: null));

    try {
      final success = await _authService.signIn(event.email, event.password);

      if (success && _authService.currentUser != null) {
        final user = _authService.currentUser!;

        if (!user.isApproved) {
          emit(state.copyWith(
            status: AuthStatus.unauthenticated,
            error: 'Your account is pending approval.',
          ));
          await _authService.signOut();
          return;
        }

        // ✅ NEW: Auto-join any pending invitations
        try {
          final result = await Supabase.instance.client
              .rpc('auto_join_pending_invitations');
          debugPrint('🔍 Auto-join result: $result');
        } catch (e) {
          debugPrint('⚠️ Auto-join failed: $e');
        }

        bool isAdmin = false;
        try {
          isAdmin = await _adminService.isAdmin();
        } catch (_) {
          isAdmin = false;
        }

        _initialAuthCheckDone = true;
        emit(state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          isAdmin: isAdmin,
        ));
        debugPrint('✅ AuthBloc: Sign in successful');
      } else {
        emit(state.copyWith(
          status: AuthStatus.unauthenticated,
          error: 'Invalid email or password. Please check your credentials.',
        ));
      }
    } on AuthException catch (e) {
      debugPrint('❌ AuthBloc AuthException: ${e.message}');
      emit(state.copyWith(status: AuthStatus.unauthenticated, error: e.message));
    } catch (e) {
      debugPrint('❌ AuthBloc._onSignIn error: $e');
      emit(state.copyWith(
        status: AuthStatus.unauthenticated,
        error: 'Sign in failed. Please check your internet connection.',
      ));
    }
  }

  Future<void> _onSignUp(
      SignUpRequested event, Emitter<AuthState> emit) async {
    debugPrint('🔍 AuthBloc._onSignUp: ${event.email}');
    emit(state.copyWith(status: AuthStatus.authenticating, error: null));

    try {
      final result = await _authService.register(
        event.email, event.password, event.displayName,
      );

      if (result.success) {
        if (result.requiresEmailConfirmation) {
          emit(state.copyWith(
            status: AuthStatus.emailUnconfirmed,
            pendingEmail: result.email ?? event.email,
          ));
        } else {
          emit(state.copyWith(status: AuthStatus.authenticated));
        }
      } else {
        emit(state.copyWith(
          status: AuthStatus.unauthenticated,
          error: result.error ?? 'Registration failed',
        ));
      }
    } on AuthException catch (e) {
      emit(state.copyWith(status: AuthStatus.unauthenticated, error: e.message));
    } catch (e) {
      emit(state.copyWith(status: AuthStatus.unauthenticated, error: 'Registration failed. Please try again.'));
    }
  }

  Future<void> _onSignOut(SignOutRequested event, Emitter<AuthState> emit) async {
    debugPrint('🔍 AuthBloc._onSignOut');
    try {
      await _authService.signOut();
      _initialAuthCheckDone = false;
      emit(const AuthState(status: AuthStatus.unauthenticated));
    } catch (e) {
      debugPrint('❌ AuthBloc._onSignOut error: $e');
      emit(state.copyWith(error: 'Sign out failed'));
    }
  }

  void _onEmailConfirmed(EmailConfirmationReceived event, Emitter<AuthState> emit) {
    debugPrint('🔍 AuthBloc._onEmailConfirmed');
    _initialAuthCheckDone = false;
    emit(state.copyWith(status: AuthStatus.emailConfirmed));
  }

  Future<void> _onAdminCheck(AdminCheckRequested event, Emitter<AuthState> emit) async {
    try {
      final isAdmin = await _adminService.isAdmin();
      emit(state.copyWith(isAdmin: isAdmin));
    } catch (_) {}
  }

  Future<void> _onDeepLink(DeepLinkReceived event, Emitter<AuthState> emit) async {
    final uriString = event.uri.toString();
    if (!uriString.contains('auth/callback') &&
        !uriString.contains('access_token') &&
        !uriString.contains('refresh_token')) {
      return;
    }

    try {
      await Supabase.instance.client.auth.getSessionFromUrl(event.uri);
      _initialAuthCheckDone = false;
      add(const AuthCheckRequested());
    } catch (e) {
      debugPrint('Deep link handling error: $e');
    }
  }

  void _onClearError(ClearAuthError event, Emitter<AuthState> emit) {
    emit(state.copyWith(error: null));
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }
}