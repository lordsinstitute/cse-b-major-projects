import '../../core/errors/app_exceptions.dart';
import '../local/local_database.dart';
import '../models/reminders.dart';

/// Medication reminders: user-controlled CRUD. Scheduling itself lives in
/// NotificationService; this layer only persists user intent.
class MedReminderRepository {
  Future<Result<List<MedicationReminder>>> getAll() async {
    try {
      final out = <MedicationReminder>[];
      for (final key in LocalDatabase.medRemindersBox.keys) {
        final raw = LocalDatabase.medRemindersBox.get(key);
        if (raw == null) continue;
        out.add(MedicationReminder.fromJson(
            Map<String, dynamic>.from(raw as Map)));
      }
      out.sort((a, b) => a.medicationName
          .toLowerCase()
          .compareTo(b.medicationName.toLowerCase()));
      return Success(out);
    } catch (e) {
      return Failure(PersistenceException('Could not load reminders.',
          originalError: e));
    }
  }

  Future<Result<MedicationReminder>> save(MedicationReminder r) async {
    try {
      if (r.medicationName.trim().isEmpty) {
        return const Failure(
            ValidationException('Medication name is required.'));
      }
      if (r.times.isEmpty) {
        return const Failure(
            ValidationException('Add at least one reminder time.'));
      }
      await LocalDatabase.medRemindersBox.put(r.id, r.toJson());
      return Success(r);
    } catch (e) {
      return Failure(PersistenceException('Could not save the reminder.',
          originalError: e));
    }
  }

  Future<Result<void>> delete(String id) async {
    try {
      await LocalDatabase.medRemindersBox.delete(id);
      return const Success(null);
    } catch (e) {
      return Failure(PersistenceException('Could not delete the reminder.',
          originalError: e));
    }
  }
}

/// Appointments: user-controlled CRUD.
class AppointmentRepository {
  Future<Result<List<Appointment>>> getAll() async {
    try {
      final out = <Appointment>[];
      for (final key in LocalDatabase.appointmentsBox.keys) {
        final raw = LocalDatabase.appointmentsBox.get(key);
        if (raw == null) continue;
        out.add(Appointment.fromJson(
            Map<String, dynamic>.from(raw as Map)));
      }
      out.sort((a, b) => a.dateTime.compareTo(b.dateTime));
      return Success(out);
    } catch (e) {
      return Failure(PersistenceException('Could not load appointments.',
          originalError: e));
    }
  }

  Future<Result<Appointment>> save(Appointment a) async {
    try {
      if (a.title.trim().isEmpty) {
        return const Failure(
            ValidationException('Appointment title is required.'));
      }
      await LocalDatabase.appointmentsBox.put(a.id, a.toJson());
      return Success(a);
    } catch (e) {
      return Failure(PersistenceException(
          'Could not save the appointment.',
          originalError: e));
    }
  }

  Future<Result<void>> delete(String id) async {
    try {
      await LocalDatabase.appointmentsBox.delete(id);
      return const Success(null);
    } catch (e) {
      return Failure(PersistenceException(
          'Could not delete the appointment.',
          originalError: e));
    }
  }
}

/// Dose logs: taken/skipped records keyed by reminder+date+time.
class DoseLogRepository {
  Future<Result<List<DoseLog>>> getAll() async {
    try {
      final out = <DoseLog>[];
      for (final key in LocalDatabase.doseLogBox.keys) {
        final raw = LocalDatabase.doseLogBox.get(key);
        if (raw == null) continue;
        out.add(DoseLog.fromJson(Map<String, dynamic>.from(raw as Map)));
      }
      return Success(out);
    } catch (e) {
      return Failure(PersistenceException('Could not load dose history.',
          originalError: e));
    }
  }

  Future<Result<DoseLog>> save(DoseLog log) async {
    try {
      await LocalDatabase.doseLogBox.put(log.key, log.toJson());
      return Success(log);
    } catch (e) {
      return Failure(PersistenceException('Could not save the response.',
          originalError: e));
    }
  }
}
