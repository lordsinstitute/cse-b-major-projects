// DateTime extensions for SoulCare
import 'dart:math' as math;

extension DateTimeExtensions on DateTime {
  /// Returns a DateTime at the start of the day (00:00:00)
  DateTime get startOfDay => DateTime(year, month, day);

  /// Returns a DateTime at the end of the day (23:59:59.999)
  DateTime get endOfDay => DateTime(year, month, day, 23, 59, 59, 999);

  /// Returns a DateTime at the start of the week (Monday)
  DateTime get startOfWeek {
    final difference = weekday - DateTime.monday;
    return subtract(Duration(days: difference)).startOfDay;
  }

  /// Returns a DateTime at the end of the week (Sunday)
  DateTime get endOfWeek => startOfWeek.add(const Duration(days: 6)).endOfDay;

  /// Returns a DateTime at the start of the month
  DateTime get startOfMonth => DateTime(year, month, 1);

  /// Returns a DateTime at the end of the month
  DateTime get endOfMonth => DateTime(year, month + 1, 0).endOfDay;

  /// Checks if this date is today
  bool get isToday {
    final now = DateTime.now();
    return year == now.year && month == now.month && day == now.day;
  }

  /// Checks if this date is yesterday
  bool get isYesterday {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return year == yesterday.year && month == yesterday.month && day == yesterday.day;
  }

  /// Checks if this date is tomorrow
  bool get isTomorrow {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return year == tomorrow.year && month == tomorrow.month && day == tomorrow.day;
  }

  /// Checks if this date is in the past
  bool get isPast => isBefore(DateTime.now().startOfDay);

  /// Checks if this date is in the future
  bool get isFuture => isAfter(DateTime.now().endOfDay);

  /// Returns the number of days between this date and another date
  int daysBetween(DateTime other) {
    return (startOfDay.difference(other.startOfDay).inDays).abs();
  }

  /// Formats the date using the app's display format
  String formatDisplay() => toIso8601String().split('T').first;

  /// Formats the date as 'MMM d, yyyy'
  String formatMedium() {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[month - 1]} $day, $year';
  }

  /// Formats the date as 'MMMM yyyy'
  String formatMonthYear() {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[month - 1]} $year';
  }

  /// Formats the date as 'EEE, MMM d'
  String formatShort() {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${days[weekday - 1]}, ${months[month - 1]} $day';
  }

  /// Returns a copy with time set to zero
  DateTime dateOnly() => DateTime(year, month, day);
}

/// String extensions
extension StringExtensions on String {
  /// Checks if the string is null or empty
  bool get isNullOrEmpty => isEmpty;

  /// Checks if the string is not null and not empty
  bool get isNotNullOrEmpty => isNotEmpty;

  /// Capitalizes the first letter of the string
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }

  /// Capitalizes the first letter of each word
  String capitalizeWords() {
    return split(' ').map((word) => word.capitalize()).join(' ');
  }

  /// Truncates the string to the specified length with ellipsis
  String truncate(int maxLength, {String ellipsis = '...'}) {
    if (length <= maxLength) return this;
    return '${substring(0, maxLength - ellipsis.length)}$ellipsis';
  }

  /// Parses the string as a DateTime using ISO8601 format
  DateTime? tryParseDateTime() {
    try {
      return DateTime.parse(this);
    } catch (_) {
      return null;
    }
  }
}

/// List extensions
extension ListExtensions<T> on List<T> {
  /// Returns the element at the given index or null if out of bounds
  T? getOrNull(int index) {
    if (index >= 0 && index < length) {
      return this[index];
    }
    return null;
  }

  /// Returns a new list with the element at the given index replaced
  List<T> replaceAt(int index, T element) {
    if (index < 0 || index >= length) return [...this];
    final newList = [...this];
    newList[index] = element;
    return newList;
  }

  /// Returns a new list with the element inserted at the given index
  List<T> insertAt(int index, T element) {
    if (index < 0) return [element, ...this];
    if (index >= length) return [...this, element];
    final newList = [...this];
    newList.insert(index, element);
    return newList;
  }

  /// Returns a new list without the element at the given index
  List<T> removeAtIndex(int index) {
    if (index < 0 || index >= length) return [...this];
    final newList = [...this];
    newList.removeAt(index);
    return newList;
  }

  /// Groups elements by the given key function
  Map<K, List<T>> groupBy<K>(K Function(T element) keyFn) {
    final map = <K, List<T>>{};
    for (final element in this) {
      final key = keyFn(element);
      map.putIfAbsent(key, () => []).add(element);
    }
    return map;
  }
}

/// Map extensions
extension MapExtensions<K, V> on Map<K, V> {
  /// Returns the value for the given key or a default value
  V getOrDefault(K key, V defaultValue) {
    return this[key] ?? defaultValue;
  }

  /// Returns the value for the given key or computes it from the default function
  V getOrCompute(K key, V Function() defaultFn) {
    return this[key] ?? defaultFn();
  }
}

/// Iterable extensions
extension IterableExtensions<T> on Iterable<T> {
  /// Returns the first element matching the predicate or null
  T? firstWhereOrNull(bool Function(T element) predicate) {
    for (final element in this) {
      if (predicate(element)) return element;
    }
    return null;
  }

  /// Returns the last element matching the predicate or null
  T? lastWhereOrNull(bool Function(T element) predicate) {
    T? result;
    for (final element in this) {
      if (predicate(element)) result = element;
    }
    return result;
  }

  /// Returns the element with the maximum value for the given key function
  T? maxBy<R extends Comparable<R>>(R Function(T element) keyFn) {
    if (isEmpty) return null;
    T? maxElement;
    R? maxValue;
    for (final element in this) {
      final value = keyFn(element);
      if (maxValue == null || value.compareTo(maxValue) > 0) {
        maxValue = value;
        maxElement = element;
      }
    }
    return maxElement;
  }

  /// Returns the element with the minimum value for the given key function
  T? minBy<R extends Comparable<R>>(R Function(T element) keyFn) {
    if (isEmpty) return null;
    T? minElement;
    R? minValue;
    for (final element in this) {
      final value = keyFn(element);
      if (minValue == null || value.compareTo(minValue) < 0) {
        minValue = value;
        minElement = element;
      }
    }
    return minElement;
  }
}

/// Num extensions
extension NumExtensions on num {
  /// Clamps the value between min and max
  num clampNum(num min, num max) {
    if (this < min) return min;
    if (this > max) return max;
    return this;
  }

  /// Rounds to the specified number of decimal places
  double roundTo(int decimalPlaces) {
    final factor = math.pow(10.0, decimalPlaces);
    return (this * factor).round() / factor;
  }
}

/// Double extensions
extension DoubleExtensions on double {
  /// Returns a formatted string with the specified decimal places
  String toFixed(int decimalPlaces) => toStringAsFixed(decimalPlaces);

  /// Returns a formatted percentage string
  String toPercentage({int decimalPlaces = 1}) => '${(this * 100).toStringAsFixed(decimalPlaces)}%';
}