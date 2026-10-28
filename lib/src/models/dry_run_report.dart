import 'package:renombrata/src/models/shooting_log.dart';

enum ProposalStatus {
  ready,
  missingFile,
  unmatchedClip,
  conflict,
  renamed,
  alreadyRenamed,
}

class RenameProposal {
  final String? originalFilePath;
  final String proposedFileName;
  final ShotRecord? associatedRecord;
  final ProposalStatus status;
  final bool isCompanionFile;
  final String? fileTcIn;
  final String? fileTcOut;
  final String? fileReel;

  RenameProposal({
    this.originalFilePath,
    required this.proposedFileName,
    this.associatedRecord,
    required this.status,
    this.isCompanionFile = false,
    this.fileTcIn,
    this.fileTcOut,
    this.fileReel,
  });

  static double? timecodeToSeconds(String? tc, [double fps = 24.0]) {
    if (tc == null || tc.trim().isEmpty) return null;
    final parts = tc.trim().split(':');
    if (parts.length < 3) return null;
    double hours = double.tryParse(parts[0]) ?? 0;
    double minutes = double.tryParse(parts[1]) ?? 0;
    double seconds = double.tryParse(parts[2]) ?? 0;
    double frames = parts.length >= 4 ? (double.tryParse(parts[3]) ?? 0) : 0;
    return (hours * 3600) + (minutes * 60) + seconds + (frames / fps);
  }

  bool get isTimecodeMatched {
    final fileInSec = timecodeToSeconds(fileTcIn);
    final fileOutSec = timecodeToSeconds(fileTcOut);
    final recordInSec = timecodeToSeconds(associatedRecord?.tcIn);

    if (fileInSec != null && recordInSec != null) {
      if (fileOutSec != null) {
        return recordInSec >= (fileInSec - 10.0) && recordInSec <= (fileOutSec + 10.0);
      } else {
        return (fileInSec - recordInSec).abs() <= 30.0;
      }
    }
    return false;
  }

  int? get timecodeDeltaSeconds {
    final fileInSec = timecodeToSeconds(fileTcIn);
    final recordInSec = timecodeToSeconds(associatedRecord?.tcIn);
    if (fileInSec == null || recordInSec == null) return null;
    return (fileInSec - recordInSec).round().abs();
  }

  bool get hasTimecodeDiscrepancy {
    final fileInSec = timecodeToSeconds(fileTcIn);
    final recordInSec = timecodeToSeconds(associatedRecord?.tcIn);
    if (fileInSec != null && recordInSec != null) {
      return !isTimecodeMatched;
    }
    return false;
  }

  static bool isReelMatched(String? fileReel, String? logReel) {
    if (fileReel == null || fileReel.trim().isEmpty) return true;
    if (logReel == null || logReel.trim().isEmpty) return true;

    final fileMatch = RegExp(r'^([A-Za-z]+)(\d+)', caseSensitive: false).firstMatch(fileReel.trim());
    final logMatch = RegExp(r'^([A-Za-z]+)(\d+)', caseSensitive: false).firstMatch(logReel.trim());

    if (fileMatch != null && logMatch != null) {
      final fileCam = fileMatch.group(1)!.toUpperCase();
      final logCam = logMatch.group(1)!.toUpperCase();
      final fileNum = int.tryParse(fileMatch.group(2)!);
      final logNum = int.tryParse(logMatch.group(2)!);

      if (fileCam != logCam) return false;
      if (fileNum != null && logNum != null) {
        return fileNum == logNum;
      }
    }

    // Camera-agnostic comparison: If one reel is numeric (e.g. '001') and the other has a camera prefix (e.g. 'A001')
    if (fileMatch != null && int.tryParse(logReel.trim()) != null) {
      final fileNum = int.tryParse(fileMatch.group(2)!);
      final logNum = int.tryParse(logReel.trim());
      if (fileNum != null && logNum != null) {
        return fileNum == logNum;
      }
    }
    if (logMatch != null && int.tryParse(fileReel.trim()) != null) {
      final logNum = int.tryParse(logMatch.group(2)!);
      final fileNum = int.tryParse(fileReel.trim());
      if (logNum != null && fileNum != null) {
        return fileNum == logNum;
      }
    }

    final cleanFile = fileReel.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final cleanLog = logReel.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    return cleanFile == cleanLog;
  }

  bool get hasReelDiscrepancy {
    if (fileReel == null || fileReel!.trim().isEmpty) return false;
    final logReel = associatedRecord?.reel;
    if (logReel == null || logReel.trim().isEmpty) return false;
    return !isReelMatched(fileReel, logReel);
  }

  RenameProposal copyWith({
    String? originalFilePath,
    String? proposedFileName,
    ShotRecord? associatedRecord,
    ProposalStatus? status,
    bool? isCompanionFile,
    String? fileTcIn,
    String? fileTcOut,
    String? fileReel,
  }) {
    return RenameProposal(
      originalFilePath: originalFilePath ?? this.originalFilePath,
      proposedFileName: proposedFileName ?? this.proposedFileName,
      associatedRecord: associatedRecord ?? this.associatedRecord,
      status: status ?? this.status,
      isCompanionFile: isCompanionFile ?? this.isCompanionFile,
      fileTcIn: fileTcIn ?? this.fileTcIn,
      fileTcOut: fileTcOut ?? this.fileTcOut,
      fileReel: fileReel ?? this.fileReel,
    );
  }
}

class DryRunReport {
  final List<RenameProposal> proposals;

  int get totalMatched => proposals.where((p) => p.status == ProposalStatus.ready && !p.isCompanionFile).length;
  int get totalMissing => proposals.where((p) => p.status == ProposalStatus.missingFile).length;
  int get totalUnmatched => proposals.where((p) => p.status == ProposalStatus.unmatchedClip && !p.isCompanionFile).length;
  bool get hasConflicts => proposals.any((p) => p.status == ProposalStatus.conflict);

  DryRunReport({required this.proposals});
}
