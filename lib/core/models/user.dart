library;

enum UserRole {
  owner, admin, dataOperator, viewer;

  static UserRole fromString(String value) {
    switch (value.toLowerCase().replaceAll(' ', '_')) {
      case 'owner': return UserRole.owner;
      case 'admin': return UserRole.admin;
      case 'data_operator': case 'staff': case 'editor': return UserRole.dataOperator;
      default: return UserRole.viewer;
    }
  }

  String get displayName {
    switch (this) {
      case UserRole.owner: return 'Owner';
      case UserRole.admin: return 'Admin';
      case UserRole.dataOperator: return 'Data Operator';
      case UserRole.viewer: return 'Viewer';
    }
  }
}

class InventoryPermissions {
  final bool canCreate;
  final bool canUpdate;
  final bool canDelete;
  final bool canExport;
  final bool canViewActivity;
  final bool canManageSettings;
  final bool canInviteMembers;
  final bool canRemoveMembers;
  final bool canManageLabels;
  final bool canChat;
  final String role;

  const InventoryPermissions({
    this.canCreate = false,
    this.canUpdate = false,
    this.canDelete = false,
    this.canExport = true,
    this.canViewActivity = true,
    this.canManageSettings = false,
    this.canInviteMembers = false,
    this.canRemoveMembers = false,
    this.canManageLabels = false,
    this.canChat = true,
    this.role = 'viewer',
  });

  bool get isViewerOnly =>
      !canCreate && !canUpdate && !canDelete && !canManageSettings;

  factory InventoryPermissions.fromSupabase(Map<String, dynamic> json) {
    return InventoryPermissions(
      canCreate: json['can_create'] as bool? ?? false,
      canUpdate: json['can_update'] as bool? ?? false,
      canDelete: json['can_delete'] as bool? ?? false,
      canExport: json['can_export'] as bool? ?? true,
      canViewActivity: json['can_view_activity'] as bool? ?? true,
      canManageSettings: json['can_manage_settings'] as bool? ?? false,
      canInviteMembers: json['can_invite_members'] as bool? ?? false,
      canRemoveMembers: json['can_remove_members'] as bool? ?? false,
      canManageLabels: json['can_manage_labels'] as bool? ?? false,
      canChat: json['can_chat'] as bool? ?? true,
      role: json['role'] as String? ?? 'viewer',
    );
  }

  factory InventoryPermissions.fromRole(String role) {
    switch (role) {
      case 'owner':
        return const InventoryPermissions(
          canCreate: true, canUpdate: true, canDelete: true,
          canExport: true, canViewActivity: true, canManageSettings: true,
          canInviteMembers: true, canRemoveMembers: true,
          canManageLabels: true, canChat: true,
          role: 'owner',
        );
      case 'admin':
        return const InventoryPermissions(
          canCreate: true, canUpdate: true, canDelete: true,
          canExport: true, canViewActivity: true, canManageSettings: true,
          canInviteMembers: true, canRemoveMembers: true,
          canManageLabels: true, canChat: true,
          role: 'admin',
        );
      case 'data_operator':
        return const InventoryPermissions(
          canCreate: true, canUpdate: true, canDelete: false,
          canExport: true, canViewActivity: true, canManageSettings: false,
          canInviteMembers: false, canRemoveMembers: false,
          canManageLabels: false, canChat: true,
          role: 'data_operator',
        );
      default:
        return const InventoryPermissions(
          canCreate: false, canUpdate: false, canDelete: false,
          canExport: true, canViewActivity: true, canManageSettings: false,
          canInviteMembers: false, canRemoveMembers: false,
          canManageLabels: false, canChat: true,
          role: 'viewer',
        );
    }
  }

  Map<String, dynamic> toJson() => {
    'can_create': canCreate,
    'can_update': canUpdate,
    'can_delete': canDelete,
    'can_export': canExport,
    'can_view_activity': canViewActivity,
    'can_manage_settings': canManageSettings,
    'can_invite_members': canInviteMembers,
    'can_remove_members': canRemoveMembers,
    'can_manage_labels': canManageLabels,
    'can_chat': canChat,
    'role': role,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventoryPermissions &&
          canCreate == other.canCreate &&
          canUpdate == other.canUpdate &&
          canDelete == other.canDelete &&
          canExport == other.canExport &&
          canViewActivity == other.canViewActivity &&
          canManageSettings == other.canManageSettings &&
          canInviteMembers == other.canInviteMembers &&
          canRemoveMembers == other.canRemoveMembers &&
          canManageLabels == other.canManageLabels &&
          canChat == other.canChat;

  @override
  int get hashCode => Object.hash(
        canCreate, canUpdate, canDelete, canExport,
        canViewActivity, canManageSettings,
        canInviteMembers, canRemoveMembers,
        canManageLabels, canChat,
      );
}

class User {
  final String id;
  final String email;
  final String? fullName;
  final String? displayName;
  final UserRole role;
  final String? companyId;
  final bool isApproved;
  final DateTime? createdAt;
  final InventoryPermissions? inventoryPermissions;

  const User({
    required this.id,
    required this.email,
    this.fullName,
    this.displayName,
    this.role = UserRole.viewer,
    this.companyId,
    this.isApproved = false,
    this.createdAt,
    this.inventoryPermissions,
  });

  String get displayNameOrEmail => fullName ?? displayName ?? email;
  String get displayNameInitial =>
      displayNameOrEmail.isNotEmpty ? displayNameOrEmail[0].toUpperCase() : '?';

  User copyWith({
    String? id,
    String? email,
    String? fullName,
    String? displayName,
    UserRole? role,
    String? companyId,
    bool? isApproved,
    DateTime? createdAt,
    InventoryPermissions? inventoryPermissions,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      companyId: companyId ?? this.companyId,
      isApproved: isApproved ?? this.isApproved,
      createdAt: createdAt ?? this.createdAt,
      inventoryPermissions: inventoryPermissions ?? this.inventoryPermissions,
    );
  }

  Map<String, dynamic> toCloudJson() => {
    'id': id,
    'email': email,
    'full_name': fullName,
    'display_name': displayName,
    'role': role.name,
    'company_id': companyId,
    'is_approved': isApproved,
    'created_at': createdAt?.toIso8601String(),
  };

  factory User.fromCloudJson(Map<String, dynamic> json) {
    InventoryPermissions? perms;
    if (json['permissions'] is Map) {
      perms = InventoryPermissions.fromSupabase(
          Map<String, dynamic>.from(json['permissions']));
    }
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String?,
      displayName: json['display_name'] as String?,
      role: UserRole.fromString(json['role'] as String? ?? 'viewer'),
      companyId: json['company_id'] as String?,
      isApproved: json['is_approved'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      inventoryPermissions: perms,
    );
  }

  Map<String, dynamic> toLocalJson() => {
    'id': id,
    'email': email,
    'fullName': fullName,
    'displayName': displayName,
    'role': role.name,
    'companyId': companyId,
    'isApproved': isApproved,
    'createdAt': createdAt?.toIso8601String(),
    'inventoryPermissions': inventoryPermissions?.toJson(),
  };

  factory User.fromLocalJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['fullName'] as String?,
      displayName: json['displayName'] as String?,
      role: UserRole.fromString(json['role'] as String? ?? 'viewer'),
      companyId: json['companyId'] as String?,
      isApproved: json['isApproved'] as bool? ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      inventoryPermissions: json['inventoryPermissions'] != null
          ? InventoryPermissions.fromSupabase(
              Map<String, dynamic>.from(json['inventoryPermissions']))
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is User && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'User(id: $id, email: $email, fullName: $fullName)';
}