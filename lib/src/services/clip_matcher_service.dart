import 'package:path/path.dart' as p;
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/services/media_scanner_service.dart';
import 'package:renombrata/src/services/convention_name_generator.dart';

class ClipMatcherService {
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

  static DryRunReport matchFiles({
    required List<ScannedFile> scannedFiles,
    required ShootingLog log,
    required String targetCamera,
    String? reelOverride,
    List<Map<String, dynamic>> renameHistory = const [],
    Map<String, String?> manualOverrides = const {},
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
        proposals.add(RenameProposal(
          originalFilePath: video.path,
          proposedFileName: video.basename,
          associatedRecord: record,
          status: ProposalStatus.alreadyRenamed,
        ));
        
        var companion = _findCompanionXml(video, xmlFiles);
        if (companion != null) {
          proposals.add(RenameProposal(
            originalFilePath: companion.path,
            proposedFileName: companion.basename,
            associatedRecord: record,
            status: ProposalStatus.alreadyRenamed,
            isCompanionFile: true,
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

        if (targetRecordId == null) {
          proposals.add(RenameProposal(
            originalFilePath: scanned.path,
            proposedFileName: scanned.basename,
            status: ProposalStatus.unmatchedClip,
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
            proposals.add(RenameProposal(
              originalFilePath: scanned.path,
              proposedFileName: '$proposedBase$ext',
              associatedRecord: record,
              status: ProposalStatus.ready,
            ));

            var companion = _findCompanionXml(scanned, xmlFiles);
            if (companion != null) {
              String xmlExt = companion.extension.toUpperCase();
              proposals.add(RenameProposal(
                originalFilePath: companion.path,
                proposedFileName: '$proposedBase$xmlExt',
                associatedRecord: record,
                status: ProposalStatus.ready,
                isCompanionFile: true,
              ));
              xmlFiles.remove(companion);
            }

            expectedClips.removeWhere((clipName, r) => r.id == record.id);
          } else {
            proposals.add(RenameProposal(
              originalFilePath: scanned.path,
              proposedFileName: scanned.basename,
              status: ProposalStatus.unmatchedClip,
            ));
          }
        }
      }
    }

    Map<String, List<ScannedFile>> filesByClip = {};
    for (var video in videoFiles) {
      if (renamedBasenames.contains(video.basename)) {
        // It's in history but didn't match any expected clip (log changed?)
        proposals.add(RenameProposal(
          originalFilePath: video.path,
          proposedFileName: video.basename,
          status: ProposalStatus.alreadyRenamed,
        ));
        continue;
      }

      String clipNum = extractClipNumber(video.basename);
      if (clipNum.isNotEmpty) {
        filesByClip.putIfAbsent(clipNum, () => []).add(video);
      } else {
        proposals.add(RenameProposal(
          originalFilePath: video.path,
          proposedFileName: video.basename,
          status: ProposalStatus.unmatchedClip,
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
        String ext = video.extension.toUpperCase();
        proposals.add(RenameProposal(
          originalFilePath: video.path,
          proposedFileName: '$proposedBase$ext',
          associatedRecord: record,
          status: ProposalStatus.ready,
        ));

        var companion = _findCompanionXml(video, xmlFiles);
        if (companion != null) {
          String xmlExt = companion.extension.toUpperCase();
          proposals.add(RenameProposal(
            originalFilePath: companion.path,
            proposedFileName: '$proposedBase$xmlExt',
            associatedRecord: record,
            status: ProposalStatus.ready,
            isCompanionFile: true,
          ));
          // Remove companion from list so it doesn't get marked unmatched if we added xml handling
          // Not strictly needed since we don't mark unmatched XMLs per se in the simple loop
        }

        filesByClip.remove(clipName);
      } else {
        for (var video in matchedVideos) {
          proposals.add(RenameProposal(
            originalFilePath: video.path,
            proposedFileName: '$proposedBase${video.extension.toUpperCase()}',
            associatedRecord: record,
            status: ProposalStatus.conflict,
          ));
        }
        filesByClip.remove(clipName);
      }
    });

    filesByClip.forEach((clipName, videos) {
      for (var video in videos) {
        proposals.add(RenameProposal(
          originalFilePath: video.path,
          proposedFileName: video.basename,
          status: ProposalStatus.unmatchedClip,
        ));
      }
    });

    return DryRunReport(proposals: proposals);
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
