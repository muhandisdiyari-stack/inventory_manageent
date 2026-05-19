enum UserRole {
  owner,
  admin,
  manager,
  staff,
  viewer;

  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (e) => e.name == value,
      orElse: () => UserRole.viewer,
    );
  }
}

class User {
  final String id;
  final String email;
  final String? displayName;
  final UserRole role;
  final String? companyId;
  final bool isApproved;
  final DateTime? createdAt;
  final Map<String, bool> permissions;

  User({
    required this.id,
    required this.email,
    this.displayName,
    this.role = UserRole.staff,
    this.companyId,
    this.isApproved = false,
    this.createdAt,
    Map<String, bool>? permissions,
  }) : permissions = permissions ?? _getDefaultPermissions(role);

  static Map<String, bool> _getDefaultPermissions(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return {
          'manage_company': true,
          'manage_users': true,
          'manage_inventory': true,
          'view_inventory': true,
          'export_reports': true,
          'bulk_import': true,
          'delete_items': true,
        };
      case UserRole.admin:
        return {
          'manage_company': false,
          'manage_users': true,
          'manage_inventory': true,
          'view_inventory': true,
          'export_reports': true,
          'bulk_import': true,
          'delete_items': true,
        };
      case UserRole.manager:
        return {
          'manage_company': false,
          'manage_users': false,
          'manage_inventory': true,
          'view_inventory': true,
          'export_reports': true,
          'bulk_import': true,
          'delete_items': false,
        };
      case UserRole.staff:
        return {
          'manage_company': false,
          'manage_users': false,
          'manage_inventory': false,
          'view_inventory': true,
          'export_reports': false,
          'bulk_import': false,
          'delete_items': false,
        };
      case UserRole.viewer:
        return {
          'manage_company': false,
          'manage_users': false,
          'manage_inventory': false,
          'view_inventory': true,
          'export_reports': false,
          'bulk_import': false,
          'delete_items': false,
        };
    }
  }

  bool hasPermission(String permission) => permissions[permission] ?? false;

  bool get canManageCompany => hasPermission('manage_company');
  bool get canManageUsers => hasPermission('manage_users');
  bool get canManageInventory => hasPermission('manage_inventory');
  bool get canViewInventory => hasPermission('view_inventory');
  bool get canExportReports => hasPermission('export_reports');
  bool get canBulkImport => hasPermission('bulk_import');
  bool get canDeleteItems => hasPermission('delete_items');

  /// Creates a copy with updated fields
  User copyWith({
    String? id,
    String? email,
    String? displayName,
    UserRole? role,
    String? companyId,
    bool? isApproved,
    DateTime? createdAt,
    Map<String, bool>? permissions,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      companyId: companyId ?? this.companyId,
      isApproved: isApproved ?? this.isApproved,
      createdAt: createdAt ?? this.createdAt,
      permissions: permissions ?? Map<String, bool>.from(this.permissions),
    );
  }

  /// Serialize for cloud storage (Supabase)
  Map<String, dynamic> toCloudJson() {
    return {
      'id': id,
      'email': email,
      'display_name': displayName,
      'role': role.name,
      'company_id': companyId,
      'is_approved': isApproved,
      'created_at': createdAt?.toIso8601String(),
      'permissions': permissions,
    };
  }

  /// Deserialize from cloud storage (Supabase)
  factory User.fromCloudJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String?,
      role: UserRole.fromString(json['role'] as String? ?? 'viewer'),
      companyId: json['company_id'] as String?,
      isApproved: json['is_approved'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      permissions: (json['permissions'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v as bool),
      ),
    );
  }

  /// Serialize for local storage (Hive)
  Map<String, dynamic> toLocalJson() {
    return {
      'id': id,
      'email': email,
      'displayName': displayName,
      'role': role.name,
      'companyId': companyId,
      'isApproved': isApproved,
      'createdAt': createdAt?.toIso8601String(),
      'permissions': permissions,
    };
  }

  /// Deserialize from local storage (Hive)
  factory User.fromLocalJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['displayName'] as String?,
      role: UserRole.fromString(json['role'] as String? ?? 'viewer'),
      companyId: json['companyId'] as String?,
      isApproved: json['isApproved'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      permissions: (json['permissions'] as Map<String, dynamic>?)?.map(
        (k, v) => MapEntry(k, v as bool),
      ),
    );
  }
}