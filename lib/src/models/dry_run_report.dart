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

  RenameProposal({
    this.originalFilePath,
    required this.proposedFileName,
    this.associatedRecord,
    required this.status,
    this.isCompanionFile = false,
  });
}

class DryRunReport {
  final List<RenameProposal> proposals;

  int get totalMatched => proposals.where((p) => p.status == ProposalStatus.ready && !p.isCompanionFile).length;
  int get totalMissing => proposals.where((p) => p.status == ProposalStatus.missingFile).length;
  int get totalUnmatched => proposals.where((p) => p.status == ProposalStatus.unmatchedClip && !p.isCompanionFile).length;
  bool get hasConflicts => proposals.any((p) => p.status == ProposalStatus.conflict);

  DryRunReport({required this.proposals});
}
