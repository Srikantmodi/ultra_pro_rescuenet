import 'dart:convert';
import 'package:equatable/equatable.dart';

/// Represents the payload data for an SOS emergency packet.
///
/// This entity captures all the information a survivor needs to transmit
/// in an emergency situation, designed to work with the UI mockup:
/// - Location (auto-captured GPS)
/// - Emergency Type (Medical, Fire, Flood, Earthquake, etc.)
/// - Severity Level (Critical, High, Medium, Low)
/// - Medical Conditions
/// - Required Supplies
/// - Personal Info
class SosPayload extends Equatable {
  /// Unique identifier for this SOS
  final String sosId;

  /// ID of the device/user sending the SOS
  final String senderId;

  /// Display name of the sender
  final String senderName;

  /// GPS latitude of the emergency location
  final double latitude;

  /// GPS longitude of the emergency location
  final double longitude;

  /// GPS accuracy in meters
  final double locationAccuracy;

  /// Type of emergency
  final EmergencyType emergencyType;

  /// Triage/Severity level (Red=Critical, Yellow=High, Green=Medium/Low)
  final TriageLevel triageLevel;

  /// Number of people affected
  final int numberOfPeople;

  /// List of medical conditions affecting victims
  final List<MedicalCondition> medicalConditions;

  /// List of required supplies
  final List<SupplyType> requiredSupplies;

  /// Additional details/notes from the sender
  final String additionalNotes;

  /// Unix timestamp when SOS was created
  final int timestamp;

  /// Whether this SOS is still active
  final bool isActive;

  /// Contact phone number (optional)
  final String? contactPhone;

  const SosPayload({
    required this.sosId,
    required this.senderId,
    required this.senderName,
    required this.latitude,
    required this.longitude,
    required this.locationAccuracy,
    required this.emergencyType,
    required this.triageLevel,
    required this.numberOfPeople,
    required this.medicalConditions,
    required this.requiredSupplies,
    required this.additionalNotes,
    required this.timestamp,
    this.isActive = true,
    this.contactPhone,
  });

  /// Creates a new SOS payload with current timestamp.
  factory SosPayload.create({
    required String sosId,
    required String senderId,
    required String senderName,
    required double latitude,
    required double longitude,
    double locationAccuracy = 0,
    EmergencyType emergencyType = EmergencyType.other,
    TriageLevel triageLevel = TriageLevel.high,
    int numberOfPeople = 1,
    List<MedicalCondition>? medicalConditions,
    List<SupplyType>? requiredSupplies,
    String additionalNotes = '',
    String? contactPhone,
  }) {
    return SosPayload(
      sosId: sosId,
      senderId: senderId,
      senderName: senderName,
      latitude: latitude,
      longitude: longitude,
      locationAccuracy: locationAccuracy,
      emergencyType: emergencyType,
      triageLevel: triageLevel,
      numberOfPeople: numberOfPeople,
      medicalConditions: medicalConditions ?? [],
      requiredSupplies: requiredSupplies ?? [],
      additionalNotes: additionalNotes,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isActive: true,
      contactPhone: contactPhone,
    );
  }

  /// Returns the triage level as a string code for network transmission.
  String get triageCode {
    switch (triageLevel) {
      case TriageLevel.critical:
      case TriageLevel.red:
        return 'red';
      case TriageLevel.high:
      case TriageLevel.yellow:
        return 'yellow';
      case TriageLevel.medium:
      case TriageLevel.low:
      case TriageLevel.green:
        return 'green';
      default:
        return 'none';
    }
  }

  /// Returns human-readable emergency type.
  String get emergencyTypeDisplay => emergencyType.displayName;

  /// Creates a simplified version of the payload (e.g. for list views).
  Map<String, dynamic> simple() {
    return {
      'id': sosId,
      'type': emergencyTypeDisplay,
      'triage': triageLevel.displayName,
      'distance': 'Unknown', // Calculated elsewhere
    };
  }

  /// Returns the age of this SOS in seconds.
  int get ageSeconds {
    return (DateTime.now().millisecondsSinceEpoch - timestamp) ~/ 1000;
  }

  /// Returns human-readable age string.
  String get ageString {
    final seconds = ageSeconds;
    if (seconds < 60) return '${seconds}s ago';
    if (seconds < 3600) return '${seconds ~/ 60}m ago';
    return '${seconds ~/ 3600}h ago';
  }

  /// Converts to JSON map for transmission.
  Map<String, dynamic> toJson() {
    return {
      'sosId': sosId,
      'senderId': senderId,
      'senderName': senderName,
      'latitude': latitude,
      'longitude': longitude,
      'locationAccuracy': locationAccuracy,
      'emergencyType': emergencyType.index,
      'triageLevel': triageLevel.index,
      'numberOfPeople': numberOfPeople,
      'medicalConditions': medicalConditions.map((e) => e.index).toList(),
      'requiredSupplies': requiredSupplies.map((e) => e.index).toList(),
      'additionalNotes': additionalNotes,
      'timestamp': timestamp,
      'isActive': isActive,
      'contactPhone': contactPhone,
    };
  }

  /// Converts to JSON string for packet payload.
  String toJsonString() => jsonEncode(toJson());

  /// Creates from JSON map.
  factory SosPayload.fromJson(Map<String, dynamic> json) {
    return SosPayload(
      sosId: json['sosId'] as String,
      senderId: json['senderId'] as String,
      senderName: json['senderName'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      locationAccuracy: (json['locationAccuracy'] as num?)?.toDouble() ?? 0,
      emergencyType: EmergencyType.values[json['emergencyType'] as int],
      triageLevel: TriageLevel.values[json['triageLevel'] as int],
      numberOfPeople: json['numberOfPeople'] as int? ?? 1,
      medicalConditions: (json['medicalConditions'] as List<dynamic>?)
              ?.map((e) => MedicalCondition.values[e as int])
              .toList() ??
          [],
      requiredSupplies: (json['requiredSupplies'] as List<dynamic>?)
              ?.map((e) => SupplyType.values[e as int])
              .toList() ??
          [],
      additionalNotes: json['additionalNotes'] as String? ?? '',
      timestamp: json['timestamp'] as int,
      isActive: json['isActive'] as bool? ?? true,
      contactPhone: json['contactPhone'] as String?,
    );
  }

  /// Creates from JSON string.
  factory SosPayload.fromJsonString(String jsonString) {
    return SosPayload.fromJson(jsonDecode(jsonString) as Map<String, dynamic>);
  }

  /// Creates a copy with updated fields.
  SosPayload copyWith({
    String? sosId,
    String? senderId,
    String? senderName,
    double? latitude,
    double? longitude,
    double? locationAccuracy,
    EmergencyType? emergencyType,
    TriageLevel? triageLevel,
    int? numberOfPeople,
    List<MedicalCondition>? medicalConditions,
    List<SupplyType>? requiredSupplies,
    String? additionalNotes,
    int? timestamp,
    bool? isActive,
    String? contactPhone,
  }) {
    return SosPayload(
      sosId: sosId ?? this.sosId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationAccuracy: locationAccuracy ?? this.locationAccuracy,
      emergencyType: emergencyType ?? this.emergencyType,
      triageLevel: triageLevel ?? this.triageLevel,
      numberOfPeople: numberOfPeople ?? this.numberOfPeople,
      medicalConditions: medicalConditions ?? this.medicalConditions,
      requiredSupplies: requiredSupplies ?? this.requiredSupplies,
      additionalNotes: additionalNotes ?? this.additionalNotes,
      timestamp: timestamp ?? this.timestamp,
      isActive: isActive ?? this.isActive,
      contactPhone: contactPhone ?? this.contactPhone,
    );
  }

  /// Marks this SOS as resolved.
  SosPayload resolve() => copyWith(isActive: false);

  @override
  List<Object?> get props => [
        sosId,
        senderId,
        senderName,
        latitude,
        longitude,
        locationAccuracy,
        emergencyType,
        triageLevel,
        numberOfPeople,
        medicalConditions,
        requiredSupplies,
        additionalNotes,
        timestamp,
        isActive,
        contactPhone,
      ];

  @override
  String toString() {
    return 'SosPayload('
        'id: $sosId, '
        'from: $senderName, '
        'type: ${emergencyType.name}, '
        'triage: ${triageLevel.name}, '
        'people: $numberOfPeople, '
        'loc: ($latitude, $longitude)'
        ')';
  }
}

/// Types of emergencies supported by the system.
/// Matches the UI mockup icons.
enum EmergencyType {
  medical,
  fire,
  flood,
  earthquake,
  trapped,
  injury,
  other,
  // Added for compatibility
  general,
  rescue,
  naturalDisaster,
  security,
}

/// Extension to get display names for emergency types.
extension EmergencyTypeExtension on EmergencyType {
  String get displayName {
    switch (this) {
      case EmergencyType.medical:
        return 'Medical Emergency';
      case EmergencyType.fire:
        return 'Fire';
      case EmergencyType.flood:
        return 'Flood';
      case EmergencyType.earthquake:
        return 'Earthquake';
      case EmergencyType.trapped:
        return 'Trapped/Stuck';
      case EmergencyType.injury:
        return 'Injury';
      case EmergencyType.other:
        return 'Other Emergency';
      case EmergencyType.general:
        return 'General Emergency';
      case EmergencyType.rescue:
        return 'Rescue Request';
      case EmergencyType.naturalDisaster:
        return 'Natural Disaster';
      case EmergencyType.security:
        return 'Security Alert';
    }
  }
}

/// Triage/Severity levels using START triage color coding.
enum TriageLevel {
  /// Green - Walking wounded, minor injuries
  low,

  /// Green - Can wait, non-life-threatening
  medium,

  /// Yellow - Delayed, serious but stable
  high,

  /// Red - Immediate, life-threatening
  critical,
  
  // Added for compatibility with UI
  none,
  green,
  yellow,
  red,
}

extension TriageLevelExtension on TriageLevel {
  String get displayName {
    switch (this) {
      case TriageLevel.low:
      case TriageLevel.green:
        return 'Minor (Green)';
      case TriageLevel.medium:
        return 'Stable (no color)'; 
      case TriageLevel.high:
      case TriageLevel.yellow:
        return 'Serious (Yellow)';
      case TriageLevel.critical:
      case TriageLevel.red:
        return 'Critical (Red)';
      case TriageLevel.none:
        return 'None';
    }
  }
}

/// Medical conditions that may affect victims.
/// Matches the UI mockup chips.
enum MedicalCondition {
  bleeding,
  fracture,
  burns,
  difficultyBreathing,
  chestPain,
  unconscious,
  diabetic,
  heartCondition,
  allergies,
  pregnant,
  elderly,
  childInfant,
}

/// Types of supplies that may be needed.
/// Matches the UI mockup chips.
enum SupplyType {
  firstAidKit,
  water,
  food,
  medication,
  blankets,
  flashlight,
  radio,
  stretcher,
  oxygen,
  defibrillator,
  ropeHarness,
  fireExtinguisher,
}

/// Extension to get display names for medical conditions.
extension MedicalConditionExtension on MedicalCondition {
  String get displayName {
    switch (this) {
      case MedicalCondition.bleeding:
        return 'Bleeding';
      case MedicalCondition.fracture:
        return 'Fracture';
      case MedicalCondition.burns:
        return 'Burns';
      case MedicalCondition.difficultyBreathing:
        return 'Difficulty Breathing';
      case MedicalCondition.chestPain:
        return 'Chest Pain';
      case MedicalCondition.unconscious:
        return 'Unconscious';
      case MedicalCondition.diabetic:
        return 'Diabetic';
      case MedicalCondition.heartCondition:
        return 'Heart Condition';
      case MedicalCondition.allergies:
        return 'Allergies';
      case MedicalCondition.pregnant:
        return 'Pregnant';
      case MedicalCondition.elderly:
        return 'Elderly';
      case MedicalCondition.childInfant:
        return 'Child/Infant';
    }
  }
}

/// Extension to get display names for supply types.
extension SupplyTypeExtension on SupplyType {
  String get displayName {
    switch (this) {
      case SupplyType.firstAidKit:
        return 'First Aid Kit';
      case SupplyType.water:
        return 'Water';
      case SupplyType.food:
        return 'Food';
      case SupplyType.medication:
        return 'Medication';
      case SupplyType.blankets:
        return 'Blankets';
      case SupplyType.flashlight:
        return 'Flashlight';
      case SupplyType.radio:
        return 'Radio';
      case SupplyType.stretcher:
        return 'Stretcher';
      case SupplyType.oxygen:
        return 'Oxygen';
      case SupplyType.defibrillator:
        return 'Defibrillator';
      case SupplyType.ropeHarness:
        return 'Rope/Harness';
      case SupplyType.fireExtinguisher:
        return 'Fire Extinguisher';
    }
  }
}
