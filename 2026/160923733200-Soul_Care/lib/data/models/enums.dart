/// Shared enums — no magic strings.
enum SleepQuality { poor, fair, okay, good, excellent }

extension SleepQualityX on SleepQuality {
  int get score {
    switch (this) {
      case SleepQuality.poor:
        return 1;
      case SleepQuality.fair:
        return 2;
      case SleepQuality.okay:
        return 3;
      case SleepQuality.good:
        return 4;
      case SleepQuality.excellent:
        return 5;
    }
  }

  String get label {
    switch (this) {
      case SleepQuality.poor:
        return 'Poor';
      case SleepQuality.fair:
        return 'Fair';
      case SleepQuality.okay:
        return 'Okay';
      case SleepQuality.good:
        return 'Good';
      case SleepQuality.excellent:
        return 'Excellent';
    }
  }

  static SleepQuality fromScore(int s) {
    switch (s) {
      case 1:
        return SleepQuality.poor;
      case 2:
        return SleepQuality.fair;
      case 3:
        return SleepQuality.okay;
      case 4:
        return SleepQuality.good;
      default:
        return SleepQuality.excellent;
    }
  }
}

enum ExerciseIntensity { none, low, moderate, high }

extension ExerciseIntensityX on ExerciseIntensity {
  String get label {
    switch (this) {
      case ExerciseIntensity.none:
        return 'None';
      case ExerciseIntensity.low:
        return 'Low';
      case ExerciseIntensity.moderate:
        return 'Moderate';
      case ExerciseIntensity.high:
        return 'High';
    }
  }

  static ExerciseIntensity fromName(String? name) {
    switch (name?.toLowerCase()) {
      case 'low':
        return ExerciseIntensity.low;
      case 'moderate':
        return ExerciseIntensity.moderate;
      case 'high':
        return ExerciseIntensity.high;
      default:
        return ExerciseIntensity.none;
    }
  }
}

enum MealQuality { poor, fair, okay, good, excellent }

extension MealQualityX on MealQuality {
  int get score {
    switch (this) {
      case MealQuality.poor:
        return 1;
      case MealQuality.fair:
        return 2;
      case MealQuality.okay:
        return 3;
      case MealQuality.good:
        return 4;
      case MealQuality.excellent:
        return 5;
    }
  }

  String get label {
    switch (this) {
      case MealQuality.poor:
        return 'Poor';
      case MealQuality.fair:
        return 'Fair';
      case MealQuality.okay:
        return 'Okay';
      case MealQuality.good:
        return 'Good';
      case MealQuality.excellent:
        return 'Excellent';
    }
  }

  static MealQuality fromScore(int s) {
    switch (s) {
      case 1:
        return MealQuality.poor;
      case 2:
        return MealQuality.fair;
      case 3:
        return MealQuality.okay;
      case 4:
        return MealQuality.good;
      default:
        return MealQuality.excellent;
    }
  }
}

enum Mood { veryLow, low, okay, good, great }

extension MoodX on Mood {
  int get score {
    switch (this) {
      case Mood.veryLow:
        return 1;
      case Mood.low:
        return 2;
      case Mood.okay:
        return 3;
      case Mood.good:
        return 4;
      case Mood.great:
        return 5;
    }
  }

  String get label {
    switch (this) {
      case Mood.veryLow:
        return 'Very low';
      case Mood.low:
        return 'Low';
      case Mood.okay:
        return 'Okay';
      case Mood.good:
        return 'Good';
      case Mood.great:
        return 'Great';
    }
  }

  static Mood fromScore(int s) {
    switch (s) {
      case 1:
        return Mood.veryLow;
      case 2:
        return Mood.low;
      case 3:
        return Mood.okay;
      case 4:
        return Mood.good;
      default:
        return Mood.great;
    }
  }
}

enum ExperimentStatus {
  recommended,
  draft,
  active,
  paused,
  completed,
  abandoned,
  archived,
}

extension ExperimentStatusX on ExperimentStatus {
  String get label {
    switch (this) {
      case ExperimentStatus.recommended:
        return 'Recommended';
      case ExperimentStatus.draft:
        return 'Draft';
      case ExperimentStatus.active:
        return 'Active';
      case ExperimentStatus.paused:
        return 'Paused';
      case ExperimentStatus.completed:
        return 'Completed';
      case ExperimentStatus.abandoned:
        return 'Abandoned';
      case ExperimentStatus.archived:
        return 'Archived';
    }
  }

  static ExperimentStatus fromName(String? name) {
    switch (name) {
      case 'recommended':
        return ExperimentStatus.recommended;
      case 'draft':
        return ExperimentStatus.draft;
      case 'active':
        return ExperimentStatus.active;
      case 'paused':
        return ExperimentStatus.paused;
      case 'completed':
        return ExperimentStatus.completed;
      case 'abandoned':
        return ExperimentStatus.abandoned;
      case 'archived':
        return ExperimentStatus.archived;
      default:
        return ExperimentStatus.draft;
    }
  }
}

enum DocumentCategory {
  labResult,
  imaging,
  prescription,
  consultation,
  discharge,
  vaccination,
  medicalLetter,
  other,
}

extension DocumentCategoryX on DocumentCategory {
  String get label {
    switch (this) {
      case DocumentCategory.labResult:
        return 'Lab Result';
      case DocumentCategory.imaging:
        return 'Imaging';
      case DocumentCategory.prescription:
        return 'Prescription';
      case DocumentCategory.consultation:
        return 'Consultation';
      case DocumentCategory.discharge:
        return 'Discharge';
      case DocumentCategory.vaccination:
        return 'Vaccination';
      case DocumentCategory.medicalLetter:
        return 'Medical Letter';
      case DocumentCategory.other:
        return 'Other';
    }
  }

  static DocumentCategory fromName(String? name) {
    switch (name) {
      case 'labResult':
      case 'labReport': // legacy name from Prompt 1
        return DocumentCategory.labResult;
      case 'imaging':
        return DocumentCategory.imaging;
      case 'prescription':
        return DocumentCategory.prescription;
      case 'consultation':
        return DocumentCategory.consultation;
      case 'discharge':
        return DocumentCategory.discharge;
      case 'vaccination':
        return DocumentCategory.vaccination;
      case 'medicalLetter':
        return DocumentCategory.medicalLetter;
      case 'note': // legacy: free notes map to Other
      case 'other':
        return DocumentCategory.other;
      default:
        return DocumentCategory.other;
    }
  }
}

enum DocumentProcessingStatus { idle, processing, completed, failed, unavailable }

extension DocumentProcessingStatusX on DocumentProcessingStatus {
  String get label {
    switch (this) {
      case DocumentProcessingStatus.idle:
        return 'Not processed';
      case DocumentProcessingStatus.processing:
        return 'Processing…';
      case DocumentProcessingStatus.completed:
        return 'Processed';
      case DocumentProcessingStatus.failed:
        return 'Processing failed';
      case DocumentProcessingStatus.unavailable:
        return 'Processing unavailable';
    }
  }

  /// Legacy values from Prompt 1 map onto the new states.
  static DocumentProcessingStatus fromName(String? name) {
    switch (name) {
      case 'idle':
        return DocumentProcessingStatus.idle;
      case 'processing':
        return DocumentProcessingStatus.processing;
      case 'completed':
      case 'processed': // legacy
        return DocumentProcessingStatus.completed;
      case 'failed':
        return DocumentProcessingStatus.failed;
      case 'unavailable':
        return DocumentProcessingStatus.unavailable;
      case 'pending': // legacy
      default:
        return DocumentProcessingStatus.idle;
    }
  }
}
