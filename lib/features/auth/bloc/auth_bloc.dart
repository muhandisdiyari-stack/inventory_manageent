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

    _setupAuthListener();
  }

  void _setupAuthListener() {
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen(
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
          add(const AuthCheckRequested());
        }
      },
    );
  }

  Future<void> _onAuthCheck(
      AuthCheckRequested event, Emitter<AuthState> emit) async {
    debugPrint('🔍 AuthBloc._onAuthCheck: status=${state.status}');

    if (_initialAuthCheckDone &&
        state.status == AuthStatus.authenticated) {
      debugPrint('🔍 AuthBloc: Already authenticated, skipping check');
      return;
    }

    if (state.status == AuthStatus.unknown) {
      emit(state.copyWith(status: AuthStatus.initializing, error: null));
    }

    try {
      if (!AppConfig.requiresAuth) {
        emit(state.copyWith(
            status: AuthStatus.authenticated, isAdmin: false));
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
        debugPrint('🔍 AuthBloc: Not authenticated via cache, checking Supabase...');
        bool foundSession = false;

        if (AppConfig.useSupabase) {
          try {
            final session =
                Supabase.instance.client.auth.currentSession;
            if (session != null) {
              debugPrint('🔍 AuthBloc: Found Supabase session, refreshing...');
              await Supabase.instance.client.auth.refreshSession();
              final authUser =
                  Supabase.instance.client.auth.currentUser;
              if (authUser != null) {
                _authService.currentUser = User(
                  id: authUser.id,
                  email: authUser.email ?? '',
                  displayName:
                      authUser.userMetadata?['display_name'],
                  role: UserRole.dataOperator,
                  isApproved: false,
                );
                _authService.isAuthenticatedValue = true;
                foundSession = true;
              }
            }
          } catch (e) {
            debugPrint('🔍 AuthBloc: Supabase session check failed: $e');
          }
        }

        if (foundSession) {
          _initialAuthCheckDone = true;
          emit(state.copyWith(
            status: AuthStatus.authenticated,
            user: _authService.currentUser,
            isAdmin: false,
          ));
        } else {
          debugPrint('🔍 AuthBloc: No valid session found, showing login');
          _initialAuthCheckDone = true;
          emit(const AuthState(status: AuthStatus.unauthenticated));
        }
      }
    } catch (e) {
      debugPrint('❌ AuthBloc._onAuthCheck error: $e');
      _initialAuthCheckDone = true;
      emit(const AuthState(status: AuthStatus.unauthenticated));
    }
  }

  Future<void> _onSignIn(
      SignInRequested event, Emitter<AuthState> emit) async {
    debugPrint('🔍 AuthBloc._onSignIn: ${event.email}');
    emit(state.copyWith(status: AuthStatus.authenticating, error: null));

    try {
      final success =
          await _authService.signIn(event.email, event.password);

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
          error: 'Invalid email or password',
        ));
      }
    } catch (e) {
      debugPrint('❌ AuthBloc._onSignIn error: $e');
      emit(state.copyWith(
        status: AuthStatus.unauthenticated,
        error:
            'Sign in failed. Please check your credentials and internet connection.',
      ));
    }
  }

  Future<void> _onSignUp(
      SignUpRequested event, Emitter<AuthState> emit) async {
    debugPrint('🔍 AuthBloc._onSignUp: ${event.email}');
    emit(state.copyWith(status: AuthStatus.authenticating, error: null));

    try {
      final result = await _authService.register(
        event.email,
        event.password,
        event.displayName,
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
    } catch (e) {
      debugPrint('❌ AuthBloc._onSignUp error: $e');
      emit(state.copyWith(
        status: AuthStatus.unauthenticated,
        error:
            'Registration failed. Please check your internet connection.',
      ));
    }
  }

  Future<void> _onSignOut(
      SignOutRequested event, Emitter<AuthState> emit) async {
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

  void _onEmailConfirmed(
      EmailConfirmationReceived event, Emitter<AuthState> emit) {
    debugPrint('🔍 AuthBloc._onEmailConfirmed');
    emit(state.copyWith(status: AuthStatus.emailConfirmed));
  }

  Future<void> _onAdminCheck(
      AdminCheckRequested event, Emitter<AuthState> emit) async {
    try {
      final isAdmin = await _adminService.isAdmin();
      emit(state.copyWith(isAdmin: isAdmin));
    } catch (_) {}
  }

  Future<void> _onDeepLink(
      DeepLinkReceived event, Emitter<AuthState> emit) async {
    final uriString = event.uri.toString();
    if (!uriString.contains('auth/callback') &&
        !uriString.contains('access_token') &&
        !uriString.contains('refresh_token')) {
      return;
    }

    try {
      await Supabase.instance.client.auth
          .getSessionFromUrl(event.uri);
      _initialAuthCheckDone = false;
      add(const AuthCheckRequested());
    } catch (e) {
      debugPrint('Deep link handling error: $e');
      if (state.status == AuthStatus.emailUnconfirmed) {
        emit(state.copyWith(
          status: AuthStatus.unauthenticated,
          error:
              'Email confirmation failed. Please try again or contact support.',
        ));
      }
    }
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel();
    return super.close();
  }
}