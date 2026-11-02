import '../../data/models/enums.dart';
import '../../data/models/models.dart';

/// Lifecycle states for document processing.
enum ProcessorState { idle, processing, completed, failed, unavailable }

/// Result of a processing attempt. [summary] is only set when processing
/// genuinely happened — never fabricated.
class ProcessResult {
  final ProcessorState state;
  final String? summary;
  final String? message;

  const ProcessResult({required this.state, this.summary, this.message});
}

/// Abstraction for (future) AI/cloud document processing.
///
/// A backend can be added later by implementing this interface. The default
/// implementation reports [ProcessorState.unavailable] and never pretends
/// a document was processed.
abstract class MedicalDocumentProcessor {
  /// Whether any processing backend is currently configured.
  bool get isAvailable;

  /// Current state for [document].
  ProcessorState stateFor(MedicalDocument document);

  /// Attempts processing. Must never invent a summary.
  Future<ProcessResult> process(MedicalDocument document);
}

/// Default local processor: no backend configured.
///
/// Always returns [ProcessorState.unavailable] with a clear message and a
/// null summary. Documents keep `processingStatus: idle` so the UI never
/// claims AI processing happened.
class UnavailableDocumentProcessor implements MedicalDocumentProcessor {
  const UnavailableDocumentProcessor();
  @override
  bool get isAvailable => false;

  @override
  ProcessorState stateFor(MedicalDocument document) {
    switch (document.processingStatus) {
      case DocumentProcessingStatus.completed:
        return ProcessorState.completed;
      case DocumentProcessingStatus.failed:
        return ProcessorState.failed;
      case DocumentProcessingStatus.processing:
        return ProcessorState.processing;
      case DocumentProcessingStatus.unavailable:
        return ProcessorState.unavailable;
      case DocumentProcessingStatus.idle:
        return ProcessorState.idle;
    }
  }

  @override
  Future<ProcessResult> process(MedicalDocument document) async {
    return const ProcessResult(
      state: ProcessorState.unavailable,
      message:
          'Document processing is not set up on this device. Your file stays stored locally.',
    );
  }
}
