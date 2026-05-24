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
        if (data.event == AuthChangeEvent.signedIn ||
            data.event == AuthChangeEvent.userUpdated) {
          final user = data.session?.user;
          if (user != null && user.emailConfirmedAt != null) {
            add(const EmailConfirmationReceived());
          }
        }
        // When user signs out, reset to unauthenticated
        if (data.event == AuthChangeEvent.signedOut) {
          add(const AuthCheckRequested());
        }
      },
    );
  }

  Future<void> _onAuthCheck(
      AuthCheckRequested event, Emitter<AuthState> emit) async {
    if (state.status == AuthStatus.unknown) {
      emit(state.copyWith(
          status: AuthStatus.initializing, error: null));
    }

    try {
      // Offline / no-auth mode
      if (!AppConfig.requiresAuth) {
        emit(state.copyWith(
            status: AuthStatus.authenticated, isAdmin: false));
        return;
      }

      await _authService.initialize();

      if (_authService.isAuthenticated) {
        final user = _authService.currentUser;
        if (user != null && !user.isApproved) {
          emit(state.copyWith(
            status: AuthStatus.unauthenticated,
            error: 'Your account is pending approval.',
          ));
          await _authService.signOut();
          return;
        }

        // Try to check admin status, but don't fail if offline
        bool isAdmin = false;
        try {
          isAdmin = await _adminService.isAdmin();
        } catch (_) {
          // Offline - use cached value or default to false
          isAdmin = false;
        }

        emit(state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          isAdmin: isAdmin,
        ));
      } else {
        // Not authenticated — show login screen
        emit(const AuthState(status: AuthStatus.unauthenticated));
      }
    } catch (e) {
      // If initialization fails completely, show login
      emit(const AuthState(status: AuthStatus.unauthenticated));
    }
  }

  Future<void> _onSignIn(
      SignInRequested event, Emitter<AuthState> emit) async {
    emit(state.copyWith(
        status: AuthStatus.authenticating, error: null));

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

        emit(state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          isAdmin: isAdmin,
        ));
      } else {
        emit(state.copyWith(
          status: AuthStatus.unauthenticated,
          error: 'Invalid email or password',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.unauthenticated,
        error: 'Sign in failed. Please check your credentials and internet connection.',
      ));
    }
  }

  Future<void> _onSignUp(
      SignUpRequested event, Emitter<AuthState> emit) async {
    emit(state.copyWith(
        status: AuthStatus.authenticating, error: null));

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
          emit(state.copyWith(
              status: AuthStatus.authenticated));
        }
      } else {
        emit(state.copyWith(
          status: AuthStatus.unauthenticated,
          error: result.error ?? 'Registration failed',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.unauthenticated,
        error: 'Registration failed. Please check your internet connection.',
      ));
    }
  }

  Future<void> _onSignOut(
      SignOutRequested event, Emitter<AuthState> emit) async {
    try {
      await _authService.signOut();
      emit(const AuthState(status: AuthStatus.unauthenticated));
    } catch (e) {
      emit(state.copyWith(error: 'Sign out failed'));
    }
  }

  void _onEmailConfirmed(
      EmailConfirmationReceived event,
      Emitter<AuthState> emit) {
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