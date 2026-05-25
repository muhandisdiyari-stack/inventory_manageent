/// User role enum with permission hierarchy.
enum UserRole {
  owner,
  admin,
  manager,
  staff,
  viewer;

  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => UserRole.viewer,
    );
  }

  /// Whether this role can manage members of the company.
  bool get canManageCompany => this == owner;

  /// Whether this role can manage (invite/remove) members.
  bool get canManageMembers => this == owner || this == admin;

  /// Whether this role can manage inventory (create/edit/delete items).
  bool get canManageInventory =>
      this == owner || this == admin || this == manager;

  /// Whether this role can delete items.
  bool get canDeleteItems =>
      this == owner || this == admin || this == manager;

  /// Whether this role can export reports.
  bool get canExportReports =>
      this == owner || this == admin || this == manager;

  /// Whether this role can bulk import.
  bool get canBulkImport =>
      this == owner || this == admin || this == manager;

  /// Whether this role can change inventory settings.
  bool get canChangeSettings =>
      this == owner || this == admin;

  /// Whether this role can view inventory items.
  bool get canViewInventory => true; // All roles can view
}

/// Inventory-level permission flags for invited members.
class InventoryPermissions {
  final bool canView;
  final bool canAddItems;
  final bool canRemoveItems;
  final bool canUpdateItems;
  final bool canDownloadReports;
  final bool canViewActivity;
  final bool canChangeSettings;
  final bool canDeleteItems;

  const InventoryPermissions({
    this.canView = true,
    this.canAddItems = false,
    this.canRemoveItems = false,
    this.canUpdateItems = false,
    this.canDownloadReports = false,
    this.canViewActivity = false,
    this.canChangeSettings = false,
    this.canDeleteItems = false,
  });

  /// Default viewer permissions (view only).
  static const viewer = InventoryPermissions(
    canView: true,
    canViewActivity: true,
  );

  /// Default staff permissions (add + update items).
  static const staff = InventoryPermissions(
    canView: true,
    canAddItems: true,
    canUpdateItems: true,
    canViewActivity: true,
  );

  /// Default manager permissions (full item management).
  static const manager = InventoryPermissions(
    canView: true,
    canAddItems: true,
    canRemoveItems: true,
    canUpdateItems: true,
    canDownloadReports: true,
    canViewActivity: true,
    canChangeSettings: true,
  );

  /// Owner permissions (everything).
  static const owner = InventoryPermissions(
    canView: true,
    canAddItems: true,
    canRemoveItems: true,
    canUpdateItems: true,
    canDownloadReports: true,
    canViewActivity: true,
    canChangeSettings: true,
    canDeleteItems: true,
  );

  static InventoryPermissions fromRole(String role) {
    switch (role.toLowerCase()) {
      case 'owner':
        return InventoryPermissions.owner;
      case 'admin':
        return InventoryPermissions.owner;
      case 'manager':
        return InventoryPermissions.manager;
      case 'staff':
        return InventoryPermissions.staff;
      default:
        return InventoryPermissions.viewer;
    }
  }

  static InventoryPermissions fromJson(Map<String, dynamic>? json) {
    if (json == null) return InventoryPermissions.viewer;
    return InventoryPermissions(
      canView: json['canView'] as bool? ?? json['view'] as bool? ?? true,
      canAddItems: json['canAddItems'] as bool? ?? json['add'] as bool? ?? false,
      canRemoveItems: json['canRemoveItems'] as bool? ?? json['delete'] as bool? ?? false,
      canUpdateItems: json['canUpdateItems'] as bool? ?? json['update'] as bool? ?? false,
      canDownloadReports: json['canDownloadReports'] as bool? ?? json['reports'] as bool? ?? false,
      canViewActivity: json['canViewActivity'] as bool? ?? json['activity'] as bool? ?? false,
      canChangeSettings: json['canChangeSettings'] as bool? ?? json['settings'] as bool? ?? false,
      canDeleteItems: json['canDeleteItems'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'canView': canView,
    'canAddItems': canAddItems,
    'canRemoveItems': canRemoveItems,
    'canUpdateItems': canUpdateItems,
    'canDownloadReports': canDownloadReports,
    'canViewActivity': canViewActivity,
    'canChangeSettings': canChangeSettings,
    'canDeleteItems': canDeleteItems,
  };

  /// Supabase-compatible JSON (uses shorter keys matching DB schema).
  Map<String, dynamic> toSupabaseJson() => {
    'view': canView,
    'add': canAddItems,
    'delete': canRemoveItems,
    'update': canUpdateItems,
    'reports': canDownloadReports,
    'activity': canViewActivity,
    'settings': canChangeSettings,
  };

  InventoryPermissions copyWith({
    bool? canView,
    bool? canAddItems,
    bool? canRemoveItems,
    bool? canUpdateItems,
    bool? canDownloadReports,
    bool? canViewActivity,
    bool? canChangeSettings,
    bool? canDeleteItems,
  }) {
    return InventoryPermissions(
      canView: canView ?? this.canView,
      canAddItems: canAddItems ?? this.canAddItems,
      canRemoveItems: canRemoveItems ?? this.canRemoveItems,
      canUpdateItems: canUpdateItems ?? this.canUpdateItems,
      canDownloadReports: canDownloadReports ?? this.canDownloadReports,
      canViewActivity: canViewActivity ?? this.canViewActivity,
      canChangeSettings: canChangeSettings ?? this.canChangeSettings,
      canDeleteItems: canDeleteItems ?? this.canDeleteItems,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryPermissions &&
          canView == other.canView &&
          canAddItems == other.canAddItems &&
          canRemoveItems == other.canRemoveItems &&
          canUpdateItems == other.canUpdateItems &&
          canDownloadReports == other.canDownloadReports &&
          canViewActivity == other.canViewActivity &&
          canChangeSettings == other.canChangeSettings &&
          canDeleteItems == other.canDeleteItems;

  @override
  int get hashCode => Object.hash(
    canView, canAddItems, canRemoveItems, canUpdateItems,
    canDownloadReports, canViewActivity, canChangeSettings, canDeleteItems,
  );
}

/// User model representing an authenticated user.
class User {
  final String id;
  final String email;
  final String? displayName;
  final UserRole role;
  final String? companyId;
  final bool isApproved;
  final DateTime? createdAt;
  final Map<String, bool> permissions;
  final InventoryPermissions? inventoryPermissions;

  User({
    required this.id,
    required this.email,
    this.displayName,
    this.role = UserRole.staff,
    this.companyId,
    this.isApproved = false,
    this.createdAt,
    Map<String, bool>? permissions,
    this.inventoryPermissions,
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

  /// Returns the effective inventory permissions, falling back to role-based defaults.
  InventoryPermissions get effectiveInventoryPermissions {
    if (inventoryPermissions != null) return inventoryPermissions!;
    return InventoryPermissions.fromRole(role.name);
  }

  /// Whether this user can perform a specific inventory action.
  bool canPerformInventoryAction(InventoryAction action) {
    final perms = effectiveInventoryPermissions;
    switch (action) {
      case InventoryAction.view:
        return perms.canView;
      case InventoryAction.addItem:
        return perms.canAddItems;
      case InventoryAction.removeItem:
        return perms.canRemoveItems;
      case InventoryAction.updateItem:
        return perms.canUpdateItems;
      case InventoryAction.deleteItem:
        return perms.canDeleteItems;
      case InventoryAction.downloadReport:
        return perms.canDownloadReports;
      case InventoryAction.viewActivity:
        return perms.canViewActivity;
      case InventoryAction.changeSettings:
        return perms.canChangeSettings;
    }
  }

  String get displayNameOrEmail => displayName ?? email;
  String get displayNameInitial =>
      displayNameOrEmail.isNotEmpty ? displayNameOrEmail[0].toUpperCase() : '?';

  User copyWith({
    String? id,
    String? email,
    String? displayName,
    UserRole? role,
    String? companyId,
    bool? isApproved,
    DateTime? createdAt,
    Map<String, bool>? permissions,
    InventoryPermissions? inventoryPermissions,
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
      inventoryPermissions: inventoryPermissions ?? this.inventoryPermissions,
    );
  }

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
      inventoryPermissions: json['inventory_permissions'] != null
          ? InventoryPermissions.fromJson(
              json['inventory_permissions'] as Map<String, dynamic>?)
          : null,
    );
  }

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
      'inventoryPermissions': inventoryPermissions?.toJson(),
    };
  }

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
      inventoryPermissions: json['inventoryPermissions'] != null
          ? InventoryPermissions.fromJson(
              json['inventoryPermissions'] as Map<String, dynamic>?)
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is User &&
          id == other.id &&
          email == other.email &&
          role == other.role &&
          companyId == other.companyId &&
          isApproved == other.isApproved;

  @override
  int get hashCode => Object.hash(id, email, role, companyId, isApproved);
}

/// Actions a user can perform within an inventory.
enum InventoryAction {
  view,
  addItem,
  removeItem,
  updateItem,
  deleteItem,
  downloadReport,
  viewActivity,
  changeSettings,
}