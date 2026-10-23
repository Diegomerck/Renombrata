import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/services/media_scanner_service.dart';
import 'package:renombrata/src/services/convention_name_generator.dart';
import 'package:renombrata/src/services/sidecar_metadata_service.dart';
import 'package:renombrata/src/services/embedded_metadata_probe_service.dart';

class ClipMatcherService {
  /// Extracts the reel identifier from standard camera clip filenames.
  /// Examples:
  /// - "A001C001_260608ZY.MP4" -> "A001"
  /// - "B002C015.MOV" -> "B002"
  /// - "A001_C001_..." -> "A001"
  /// - "C0001.MP4" -> null
  static String? extractReel(String filename) {
    final clean = p.basename(filename);
    final match = RegExp(r'^([A-Za-z]\d{1,4})_?[cC]\d+', caseSensitive: false).firstMatch(clean) ??
        RegExp(r'^([A-Za-z]\d{1,4})_', caseSensitive: false).firstMatch(clean);
    if (match != null) {
      return match.group(1)!.toUpperCase();
    }
    return null;
  }

  static String extractClipNumber(String filename) {
    String baseName = p.basenameWithoutExtension(filename);
    
    final priorityMatch = RegExp(r'[cC](\d{3,4})').firstMatch(baseName);
    if (priorityMatch != null) {
      int num = int.parse(priorityMatch.group(1)!);
      return num.toString().padLeft(3, '0');
    }

    final fallbackMatches = RegExp(r'\d+').allMatches(baseName);
    if (fallbackMatches.isNotEmpty) {
      int num = int.parse(fallbackMatches.last.group(0)!);
      return num.toString().padLeft(3, '0');
    }

    return '';
  }

  static SidecarMetadata? _extractSidecar(ScannedFile? companion, [Map<String, String>? testContents]) {
    if (companion == null) return null;
    String? content = testContents?[companion.path];
    if (content == null) {
      try {
        final file = File(companion.path);
        if (file.existsSync()) {
          content = file.readAsStringSync();
        }
      } catch (_) {}
    }
    if (content != null && content.isNotEmpty) {
      return SidecarMetadataService.parseXml(content);
    }
    return null;
  }

  static DryRunReport matchFiles({
    required List<ScannedFile> scannedFiles,
    required ShootingLog log,
    required String targetCamera,
    String? reelOverride,
    List<Map<String, dynamic>> renameHistory = const [],
    Map<String, String?> manualOverrides = const {},
    Map<String, String>? xmlContentsForTesting,
  }) {
    List<RenameProposal> proposals = [];
    
    var videoFiles = scannedFiles.where((f) {
      if (!f.isVideo) return false;
      String base = p.basenameWithoutExtension(f.basename).toUpperCase();
      final match = RegExp(r'^([A-Z])\d+C\d+').firstMatch(base);
      if (match != null) {
        String fileCamera = match.group(1)!;
        if (fileCamera != targetCamera.toUpperCase()) {
          return false;
        }
      }
      return true;
    }).toList();
    
    var xmlFiles = scannedFiles.where((f) {
      if (!f.isXml) return false;
      String base = p.basenameWithoutExtension(f.basename).toUpperCase();
      final match = RegExp(r'^([A-Z])\d+C\d+').firstMatch(base);
      if (match != null) {
        String fileCamera = match.group(1)!;
        if (fileCamera != targetCamera.toUpperCase()) {
          return false;
        }
      }
      return true;
    }).toList();

    Set<String> renamedBasenames = renameHistory.map((e) {
      final renamedPath = e['renamedPath'] as String?;
      return renamedPath != null ? p.basename(renamedPath) : '';
    }).where((s) => s.isNotEmpty).toSet();

    Map<String, ShotRecord> expectedClips = {};
    for (var record in log.records) {
      for (var cam in record.cameras) {
        if (cam.cameraName.toUpperCase() == targetCamera.toUpperCase()) {
          // If we have multiple records with the same clip number for the same camera, that's a conflict
          expectedClips[cam.clipName] = record;
        }
      }
    }

    // Process already renamed files based on proposed names or history
    expectedClips.removeWhere((clipName, record) {
      String proposedBase = ConventionNameGenerator.generate(
        nomenclature: log.metadata.nomenclature,
        date: log.metadata.date,
        scene: record.scene,
        plane: record.plane,
        take: record.take,
        reel: record.reel,
        day: log.metadata.day,
        unit: log.metadata.unit,
        activeCamera: targetCamera,
        reelOverride: reelOverride,
      );

      var alreadyRenamedVideoList = videoFiles.where((v) => 
        p.basenameWithoutExtension(v.basename).toUpperCase() == proposedBase.toUpperCase() ||
        renamedBasenames.contains(v.basename)
      ).toList();

      if (alreadyRenamedVideoList.isNotEmpty) {
        var video = alreadyRenamedVideoList.first;
        var companion = _findCompanionXml(video, xmlFiles);
        final sidecar = _extractSidecar(companion, xmlContentsForTesting);

        proposals.add(RenameProposal(
          originalFilePath: video.path,
          proposedFileName: video.basename,
          associatedRecord: record,
          status: ProposalStatus.alreadyRenamed,
          fileTcIn: sidecar?.tcIn,
          fileTcOut: sidecar?.tcOut,
        ));
        
        if (companion != null) {
          proposals.add(RenameProposal(
            originalFilePath: companion.path,
            proposedFileName: companion.basename,
            associatedRecord: record,
            status: ProposalStatus.alreadyRenamed,
            isCompanionFile: true,
            fileTcIn: sidecar?.tcIn,
            fileTcOut: sidecar?.tcOut,
          ));
          xmlFiles.remove(companion);
        }
        videoFiles.remove(video);
        return true;
      }
      return false;
    });

    // Process manual overrides (conflict resolution & explicit assignments)
    for (var scanned in List<ScannedFile>.from(scannedFiles.where((f) => f.isVideo))) {
      if (manualOverrides.containsKey(scanned.path)) {
        videoFiles.removeWhere((v) => v.path == scanned.path);
        final targetRecordId = manualOverrides[scanned.path];
        final fileReel = extractReel(scanned.basename);

        if (targetRecordId == null) {
          var companion = _findCompanionXml(scanned, xmlFiles);
          final sidecar = _extractSidecar(companion, xmlContentsForTesting);
          proposals.add(RenameProposal(
            originalFilePath: scanned.path,
            proposedFileName: scanned.basename,
            status: ProposalStatus.unmatchedClip,
            fileTcIn: sidecar?.tcIn,
            fileTcOut: sidecar?.tcOut,
            fileReel: fileReel,
          ));
        } else {
          final record = log.records.where((r) => r.id == targetRecordId).firstOrNull;
          if (record != null) {
            String proposedBase = ConventionNameGenerator.generate(
              nomenclature: log.metadata.nomenclature,
              date: log.metadata.date,
              scene: record.scene,
              plane: record.plane,
              take: record.take,
              reel: record.reel,
              day: log.metadata.day,
              unit: log.metadata.unit,
              activeCamera: targetCamera,
              reelOverride: reelOverride,
            );
            String ext = scanned.extension.toUpperCase();
            var companion = _findCompanionXml(scanned, xmlFiles);
            final sidecar = _extractSidecar(companion, xmlContentsForTesting);

            proposals.add(RenameProposal(
              originalFilePath: scanned.path,
              proposedFileName: '$proposedBase$ext',
              associatedRecord: record,
              status: ProposalStatus.ready,
              fileTcIn: sidecar?.tcIn,
              fileTcOut: sidecar?.tcOut,
              fileReel: fileReel,
            ));

            if (companion != null) {
              String xmlExt = companion.extension.toUpperCase();
              proposals.add(RenameProposal(
                originalFilePath: companion.path,
                proposedFileName: '$proposedBase$xmlExt',
                associatedRecord: record,
                status: ProposalStatus.ready,
                isCompanionFile: true,
                fileTcIn: sidecar?.tcIn,
                fileTcOut: sidecar?.tcOut,
                fileReel: fileReel,
              ));
              xmlFiles.remove(companion);
            }

            expectedClips.removeWhere((clipName, r) => r.id == record.id);
          } else {
            var companion = _findCompanionXml(scanned, xmlFiles);
            final sidecar = _extractSidecar(companion, xmlContentsForTesting);
            proposals.add(RenameProposal(
              originalFilePath: scanned.path,
              proposedFileName: scanned.basename,
              status: ProposalStatus.unmatchedClip,
              fileTcIn: sidecar?.tcIn,
              fileTcOut: sidecar?.tcOut,
              fileReel: fileReel,
            ));
          }
        }
      }
    }

    Map<String, List<ScannedFile>> filesByClip = {};
    for (var video in videoFiles) {
      final fileReel = extractReel(video.basename);
      if (renamedBasenames.contains(video.basename)) {
        // It's in history but didn't match any expected clip (log changed?)
        proposals.add(RenameProposal(
          originalFilePath: video.path,
          proposedFileName: video.basename,
          status: ProposalStatus.alreadyRenamed,
          fileReel: fileReel,
        ));
        continue;
      }

      String clipNum = extractClipNumber(video.basename);
      if (clipNum.isNotEmpty) {
        filesByClip.putIfAbsent(clipNum, () => []).add(video);
      } else {
        var companion = _findCompanionXml(video, xmlFiles);
        final sidecar = _extractSidecar(companion, xmlContentsForTesting);
        proposals.add(RenameProposal(
          originalFilePath: video.path,
          proposedFileName: video.basename,
          status: ProposalStatus.unmatchedClip,
          fileTcIn: sidecar?.tcIn,
          fileTcOut: sidecar?.tcOut,
          fileReel: fileReel,
        ));
      }
    }

    expectedClips.forEach((clipName, record) {
      var matchedVideos = filesByClip[clipName];
      
      String proposedBase = ConventionNameGenerator.generate(
        nomenclature: log.metadata.nomenclature,
        date: log.metadata.date,
        scene: record.scene,
        plane: record.plane,
        take: record.take,
        reel: record.reel,
        day: log.metadata.day,
        unit: log.metadata.unit,
        activeCamera: targetCamera,
        reelOverride: reelOverride,
      );

      if (matchedVideos == null || matchedVideos.isEmpty) {
        proposals.add(RenameProposal(
          originalFilePath: null,
          proposedFileName: '$proposedBase.MP4',
          associatedRecord: record,
          status: ProposalStatus.missingFile,
        ));
      } else if (matchedVideos.length == 1) {
        var video = matchedVideos.first;
        final fileReel = extractReel(video.basename);
        String ext = video.extension.toUpperCase();
        var companion = _findCompanionXml(video, xmlFiles);
        final sidecar = _extractSidecar(companion, xmlContentsForTesting);

        final initialProposal = RenameProposal(
          originalFilePath: video.path,
          proposedFileName: '$proposedBase$ext',
          associatedRecord: record,
          status: ProposalStatus.ready,
          fileTcIn: sidecar?.tcIn,
          fileTcOut: sidecar?.tcOut,
          fileReel: fileReel,
        );

        final isOverridden = manualOverrides.containsKey(video.path);
        final status = ((initialProposal.hasTimecodeDiscrepancy || initialProposal.hasReelDiscrepancy) && !isOverridden)
            ? ProposalStatus.conflict
            : ProposalStatus.ready;

        proposals.add(initialProposal.copyWith(status: status));

        if (companion != null) {
          String xmlExt = companion.extension.toUpperCase();
          proposals.add(RenameProposal(
            originalFilePath: companion.path,
            proposedFileName: '$proposedBase$xmlExt',
            associatedRecord: record,
            status: status,
            isCompanionFile: true,
            fileTcIn: sidecar?.tcIn,
            fileTcOut: sidecar?.tcOut,
            fileReel: fileReel,
          ));
          xmlFiles.remove(companion);
        }

        filesByClip.remove(clipName);
      } else {
        for (var video in matchedVideos) {
          final fileReel = extractReel(video.basename);
          var companion = _findCompanionXml(video, xmlFiles);
          final sidecar = _extractSidecar(companion, xmlContentsForTesting);
          proposals.add(RenameProposal(
            originalFilePath: video.path,
            proposedFileName: '$proposedBase${video.extension.toUpperCase()}',
            associatedRecord: record,
            status: ProposalStatus.conflict,
            fileTcIn: sidecar?.tcIn,
            fileTcOut: sidecar?.tcOut,
            fileReel: fileReel,
          ));
        }
        filesByClip.remove(clipName);
      }
    });

    filesByClip.forEach((clipName, videos) {
      for (var video in videos) {
        final fileReel = extractReel(video.basename);
        var companion = _findCompanionXml(video, xmlFiles);
        final sidecar = _extractSidecar(companion, xmlContentsForTesting);
        proposals.add(RenameProposal(
          originalFilePath: video.path,
          proposedFileName: video.basename,
          status: ProposalStatus.unmatchedClip,
          fileTcIn: sidecar?.tcIn,
          fileTcOut: sidecar?.tcOut,
          fileReel: fileReel,
        ));
      }
    });

    return DryRunReport(proposals: proposals);
  }

  /// Asynchronous variant of [matchFiles] that probes standalone video files
  /// (.mov, .mxf, .mp4) for embedded timecodes via MediaInfo or FFprobe
  /// whenever no companion XML timecode was found.
  static Future<DryRunReport> matchFilesAsync({
    required List<ScannedFile> scannedFiles,
    required ShootingLog log,
    required String targetCamera,
    String? reelOverride,
    List<Map<String, dynamic>> renameHistory = const [],
    Map<String, String?> manualOverrides = const {},
    Map<String, String>? xmlContentsForTesting,
    Future<SidecarMetadata?> Function(String filePath)? probeFunction,
  }) async {
    final report = matchFiles(
      scannedFiles: scannedFiles,
      log: log,
      targetCamera: targetCamera,
      reelOverride: reelOverride,
      renameHistory: renameHistory,
      manualOverrides: manualOverrides,
      xmlContentsForTesting: xmlContentsForTesting,
    );

    final updatedProposals = <RenameProposal>[];
    final conflictedVideoPaths = <String>{};

    for (final proposal in report.proposals) {
      if (!proposal.isCompanionFile &&
          proposal.originalFilePath != null &&
          proposal.fileTcIn == null) {
        final ext = p.extension(proposal.originalFilePath!).toLowerCase();
        if (['.mov', '.mxf', '.mp4'].contains(ext)) {
          final probe = probeFunction != null
              ? await probeFunction(proposal.originalFilePath!)
              : await EmbeddedMetadataProbeService.probeFile(proposal.originalFilePath!);
          if (probe != null && probe.tcIn != null) {
            final probedProposal = proposal.copyWith(
              fileTcIn: probe.tcIn,
              fileTcOut: probe.tcOut,
            );
            final isOverridden = manualOverrides.containsKey(proposal.originalFilePath);
            final newStatus = ((probedProposal.hasTimecodeDiscrepancy || probedProposal.hasReelDiscrepancy) && !isOverridden)
                ? ProposalStatus.conflict
                : probedProposal.status;
            if (newStatus == ProposalStatus.conflict) {
              conflictedVideoPaths.add(proposal.originalFilePath!);
            }
            updatedProposals.add(probedProposal.copyWith(status: newStatus));
            continue;
          }
        }
      }
      updatedProposals.add(proposal);
    }

    if (conflictedVideoPaths.isNotEmpty) {
      for (int i = 0; i < updatedProposals.length; i++) {
        final pItem = updatedProposals[i];
        if (pItem.isCompanionFile && pItem.originalFilePath != null) {
          final companionStem = p.basenameWithoutExtension(pItem.originalFilePath!).toUpperCase();
          for (final videoPath in conflictedVideoPaths) {
            final videoStem = p.basenameWithoutExtension(videoPath).toUpperCase();
            if (companionStem == videoStem || (companionStem.startsWith(videoStem) && companionStem.endsWith('M01'))) {
              updatedProposals[i] = pItem.copyWith(status: ProposalStatus.conflict);
              break;
            }
          }
        }
      }
    }

    return DryRunReport(proposals: updatedProposals);
  }

  static ScannedFile? _findCompanionXml(ScannedFile video, List<ScannedFile> xmlFiles) {
    String videoStem = p.basenameWithoutExtension(video.basename).toUpperCase();
    for (var xml in xmlFiles) {
      String xmlStem = p.basenameWithoutExtension(xml.basename).toUpperCase();
      if (xmlStem == videoStem) {
        return xml;
      }
      if (xmlStem.startsWith(videoStem) && xmlStem.endsWith('M01')) {
        return xml;
      }
    }
    return null;
  }
}
