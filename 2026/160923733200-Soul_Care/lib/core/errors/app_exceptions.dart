/// Base exception class for SoulCare
abstract class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  const AppException(this.message, {this.code, this.originalError});

  @override
  String toString() => 'AppException: $message${code != null ? ' (Code: $code)' : ''}';
}

/// Exception for persistence layer failures
class PersistenceException extends AppException {
  const PersistenceException(super.message,
      {String? code, super.originalError})
      : super(code: code ?? 'PERSISTENCE_ERROR');
}

/// Exception for validation failures
class ValidationException extends AppException {
  final Map<String, String>? fieldErrors;

  const ValidationException(
    super.message, {
    String? code,
    this.fieldErrors,
    super.originalError,
  }) : super(code: code ?? 'VALIDATION_ERROR');
}

/// Exception for not found errors
class NotFoundException extends AppException {
  const NotFoundException(super.message, {String? code, super.originalError})
      : super(code: code ?? 'NOT_FOUND');
}

/// Exception for repository errors
class RepositoryException extends AppException {
  const RepositoryException(super.message, {String? code, super.originalError})
      : super(code: code ?? 'REPOSITORY_ERROR');
}

/// Exception for file operations
class FileException extends AppException {
  const FileException(super.message, {String? code, super.originalError})
      : super(code: code ?? 'FILE_ERROR');
}

/// Result type for operations that can fail
sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;

  T? get value => isSuccess ? (this as Success<T>).value : null;
  AppException? get error => isFailure ? (this as Failure<T>).error : null;

  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(AppException error) onFailure,
  }) {
    if (isSuccess) {
      return onSuccess((this as Success<T>).value);
    } else {
      return onFailure((this as Failure<T>).error);
    }
  }
}

class Success<T> extends Result<T> {
  @override
  final T value;
  const Success(this.value);
}

class Failure<T> extends Result<T> {
  @override
  final AppException error;
  const Failure(this.error);
}

/// Extension for easier Result handling
extension ResultExtension<T> on Result<T> {
  T getOrThrow() {
    if (isSuccess) return value!;
    throw error!;
  }

  T getOrDefault(T defaultValue) {
    return value ?? defaultValue;
  }

  Result<R> map<R>(R Function(T value) transform) {
    return fold(
      onSuccess: (value) => Success(transform(value)),
      onFailure: (error) => Failure<R>(error),
    );
  }

  Result<R> flatMap<R>(Result<R> Function(T value) transform) {
    return fold(
      onSuccess: (value) => transform(value),
      onFailure: (error) => Failure<R>(error),
    );
  }
}