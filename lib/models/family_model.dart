import 'package:flutter/foundation.dart';

enum FamilyStatusTone { safe, waiting, active }

enum FamilyCheckInType {
  autoLogin('Auto when logging in'),
  manualDaily('Manual daily check-in'),
  exerciseTarget('Exercise target check-in');

  // 创建打卡类型。
  const FamilyCheckInType(this.familyLabel);

  final String familyLabel;
}

class FamilyMember {
  // 创建家庭成员数据。
  const FamilyMember({
    required this.familyName,
    required this.familyRole,
    required this.familyInitial,
    required this.familyStatusText,
    required this.familyStatusTone,
    this.familyIsAdmin = false,
  });

  final String familyName;
  final String familyRole;
  final String familyInitial;
  final String familyStatusText;
  final FamilyStatusTone familyStatusTone;
  final bool familyIsAdmin;
}

class FamilyCheckInTask {
  // 创建家庭打卡任务数据。
  const FamilyCheckInTask({
    required this.familyTitle,
    required this.familyMemberNames,
    required this.familyType,
    required this.familyRepeat,
    required this.familyCreatedAt,
  });

  final String familyTitle;
  final List<String> familyMemberNames;
  final FamilyCheckInType familyType;
  final String familyRepeat;
  final DateTime familyCreatedAt;

  // 生成成员展示文字。
  String get familyMemberSummary => familyMemberNames.join(', ');
}

class FamilyActivity {
  // 创建家庭活动数据。
  const FamilyActivity({
    required this.familyTitle,
    required this.familyDate,
    required this.familyDuration,
    required this.familyLocation,
    required this.familyParticipants,
    required this.familyGoal,
    required this.familyDescription,
    required this.familyRequirements,
    required this.familyTags,
    this.familyIsRecent = false,
  });

  final String familyTitle;
  final String familyDate;
  final String familyDuration;
  final String familyLocation;
  final List<String> familyParticipants;
  final String familyGoal;
  final String familyDescription;
  final String familyRequirements;
  final List<String> familyTags;
  final bool familyIsRecent;

  // 生成参与者展示文字。
  String get familyParticipantSummary => familyParticipants.join(', ');
}

class FamilyHealthRecord {
  // 创建家庭健康记录数据。
  const FamilyHealthRecord({
    required this.familyTitle,
    required this.familyNote,
    required this.familyPhotoTitle,
    required this.familyCreatedAt,
  });

  final String familyTitle;
  final String familyNote;
  final String familyPhotoTitle;
  final DateTime? familyCreatedAt;
}

class FamilyDataStore {
  static const String familyGroupName = 'Tan Family Group';
  static const String familyGroupSubtitle = '3 members · 2 admins';
  static const String familyDetails =
      'Home group for safety check-ins and family activities.';
  static const String familyAdmins = 'Linda Tan (Mom), Michael Tan (Dad)';

  static final ValueNotifier<List<FamilyMember>> familyMembersNotifier =
      ValueNotifier<List<FamilyMember>>(const [
    FamilyMember(
      familyName: 'Linda Tan',
      familyRole: 'Mom',
      familyInitial: 'L',
      familyStatusText: 'Checked in · 8:30 AM',
      familyStatusTone: FamilyStatusTone.safe,
      familyIsAdmin: true,
    ),
    FamilyMember(
      familyName: 'Michael Tan',
      familyRole: 'Dad',
      familyInitial: 'M',
      familyStatusText: 'No check-in today',
      familyStatusTone: FamilyStatusTone.waiting,
      familyIsAdmin: true,
    ),
    FamilyMember(
      familyName: 'Henry Tan',
      familyRole: 'Grandfather',
      familyInitial: 'H',
      familyStatusText: 'Walk record added',
      familyStatusTone: FamilyStatusTone.active,
    ),
  ]);

  static final ValueNotifier<List<FamilyCheckInTask>>
      familyCheckInTasksNotifier =
      ValueNotifier<List<FamilyCheckInTask>>(const []);

  static final ValueNotifier<List<FamilyActivity>> familyActivitiesNotifier =
      ValueNotifier<List<FamilyActivity>>(const [
    FamilyActivity(
      familyTitle: 'Family Dinner',
      familyDate: 'Sat, May 25',
      familyDuration: '2 hours',
      familyLocation: 'Home',
      familyParticipants: ['Mom', 'Dad', 'Grandfather'],
      familyGoal: 'Spend time together',
      familyDescription:
          'Prepare dinner together and share recent family updates.',
      familyRequirements: 'Bring photos and simple food ideas.',
      familyTags: ['Care', 'Home'],
      familyIsRecent: true,
    ),
    FamilyActivity(
      familyTitle: 'Park Walk',
      familyDate: 'May 18',
      familyDuration: '60 min',
      familyLocation: 'Riverside Park',
      familyParticipants: ['Mom', 'Dad', 'Grandfather'],
      familyGoal: 'Gentle outdoor exercise',
      familyDescription: 'A slow walk with rest points and water breaks.',
      familyRequirements: 'Comfortable shoes and water.',
      familyTags: ['Health', 'Walk'],
    ),
    FamilyActivity(
      familyTitle: 'Photo Day',
      familyDate: 'May 12',
      familyDuration: '12 photos',
      familyLocation: 'Family Album',
      familyParticipants: ['Family album'],
      familyGoal: 'Keep memory photos',
      familyDescription: 'Organize family photos and write short captions.',
      familyRequirements: 'Select favorite memory photos.',
      familyTags: ['Memory', 'Photos'],
    ),
    FamilyActivity(
      familyTitle: 'Health Check',
      familyDate: 'May 8',
      familyDuration: 'Record updated',
      familyLocation: 'Home',
      familyParticipants: ['Grandfather'],
      familyGoal: 'Update health record',
      familyDescription: 'Record simple health notes for family admins.',
      familyRequirements: 'Add notes after the check-in.',
      familyTags: ['Health', 'Care'],
    ),
  ]);

  static final ValueNotifier<List<FamilyHealthRecord>>
      familyHealthRecordsNotifier =
      ValueNotifier<List<FamilyHealthRecord>>(const [
    FamilyHealthRecord(
      familyTitle: 'Health Record Log',
      familyNote: 'Admins can add health notes or memory photos.',
      familyPhotoTitle: 'No photo attached',
      familyCreatedAt: null,
    ),
  ]);

  // 读取家庭成员列表。
  static List<FamilyMember> familyMembers() {
    return familyMembersNotifier.value;
  }

  // 新增家庭打卡任务。
  static void familyAddCheckInTask(FamilyCheckInTask familyTask) {
    familyCheckInTasksNotifier.value = [
      familyTask,
      ...familyCheckInTasksNotifier.value,
    ];
  }

  // 新增家庭活动。
  static void familyAddActivity(FamilyActivity familyActivity) {
    familyActivitiesNotifier.value = [
      familyActivity,
      ...familyActivitiesNotifier.value,
    ];
  }

  // 新增健康备注或照片说明。
  static void familyAddHealthRecord(FamilyHealthRecord familyRecord) {
    familyHealthRecordsNotifier.value = [
      familyRecord,
      ...familyHealthRecordsNotifier.value,
    ];
  }
}
