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

  /// Extracts the camera letter from standard clip filenames.
  /// Examples:
  /// - "A001C002.MP4" -> "A"
  /// - "B002C015.MOV" -> "B"
  /// - "C0001.MP4" -> fallback ("A")
  static String extractCamera(String filename, {String fallback = 'A'}) {
    final clean = p.basename(filename);
    final match = RegExp(r'^([A-Za-z])\d{1,4}[cC]\d+').firstMatch(clean);
    if (match != null) {
      return match.group(1)!.toUpperCase();
    }
    final reel = extractReel(clean);
    if (reel != null && reel.isNotEmpty) {
      return reel[0].toUpperCase();
    }
    return fallback.toUpperCase();
  }

  /// Sorts rename proposals so they strictly maintain natural disk scan order:
  /// 1. Camera
  /// 2. Reel
  /// 3. Natural clip number (C001, C002, C003...)
  /// 4. Parent stem (grouping video and companion files together)
  /// 5. Video clips appear first, followed immediately by their companion files (.XML)
  static List<RenameProposal> sortProposals(
    List<RenameProposal> proposals, {
    String targetCamera = 'A',
  }) {
    final sorted = List<RenameProposal>.from(proposals);
    sorted.sort((a, b) {
      final camA = extractCamera(
        a.originalFilePath ??
            a.associatedRecord?.cameras.firstOrNull?.cameraName ??
            targetCamera,
        fallback: targetCamera,
      );
      final camB = extractCamera(
        b.originalFilePath ??
            b.associatedRecord?.cameras.firstOrNull?.cameraName ??
            targetCamera,
        fallback: targetCamera,
      );
      final camComp = camA.compareTo(camB);
      if (camComp != 0) return camComp;

      final reelA = a.fileReel ??
          extractReel(a.originalFilePath ?? '') ??
          a.associatedRecord?.reel ??
          '';
      final reelB = b.fileReel ??
          extractReel(b.originalFilePath ?? '') ??
          b.associatedRecord?.reel ??
          '';
      final reelComp = reelA.compareTo(reelB);
      if (reelComp != 0) return reelComp;

      int extractNum(RenameProposal prop) {
        String raw = extractClipNumber(prop.originalFilePath ?? '');
        if (raw.isEmpty && prop.associatedRecord != null) {
          final camRec = prop.associatedRecord!.cameras.firstWhere(
            (c) => c.cameraName.toUpperCase() == targetCamera.toUpperCase(),
            orElse: () => prop.associatedRecord!.cameras.isNotEmpty
                ? prop.associatedRecord!.cameras.first
                : CameraTakeRecord(cameraName: '', clipName: ''),
          );
          raw = normalizeClipNumber(camRec.clipName);
        }
        if (raw.isEmpty) {
          raw = extractClipNumber(prop.proposedFileName);
        }
        return int.tryParse(raw) ?? 999999;
      }

      final numA = extractNum(a);
      final numB = extractNum(b);
      final numComp = numA.compareTo(numB);
      if (numComp != 0) return numComp;

      String stem(RenameProposal prop) {
        if (prop.originalFilePath != null) {
          String s =
              p.basenameWithoutExtension(prop.originalFilePath!).toUpperCase();
          if (prop.isCompanionFile && s.endsWith('M01') && s.length > 3) {
            s = s.substring(0, s.length - 3);
          }
          return s;
        }
        return prop.proposedFileName.toUpperCase();
      }

      final stemA = stem(a);
      final stemB = stem(b);
      final stemComp = stemA.compareTo(stemB);
      if (stemComp != 0) return stemComp;

      final compA = a.isCompanionFile ? 1 : 0;
      final compB = b.isCompanionFile ? 1 : 0;
      final compDiff = compA.compareTo(compB);
      if (compDiff != 0) return compDiff;

      return (a.originalFilePath ?? a.proposedFileName)
          .compareTo(b.originalFilePath ?? b.proposedFileName);
    });
    return sorted;
  }

  static String extractClipNumber(String filename) {
    String baseName = p.basenameWithoutExtension(filename);
    
    final priorityMatch = RegExp(r'[cC](\d{1,4})').firstMatch(baseName);
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

  /// Normalizes any clip string ("1", "01", "001", "0001", "C001") into
  /// a 3-digit padded number string (e.g. "001").
  static String normalizeClipNumber(String clipNum) {
    final clean = clipNum.trim();
    if (clean.isEmpty) return '';
    final stripped = clean.replaceFirst(RegExp(r'^[cC]'), '');
    final parsed = int.tryParse(stripped);
    if (parsed != null) {
      return parsed.toString().padLeft(3, '0');
    }
    return extractClipNumber(clean);
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

  /// Checks if [xml] is a Sony M01 metadata sidecar for [video].
  static bool isM01Companion(ScannedFile video, ScannedFile xml) {
    if (!xml.isXml) return false;
    final videoStem = p.basenameWithoutExtension(video.basename).toUpperCase();
    final xmlStem = p.basenameWithoutExtension(xml.basename).toUpperCase();
    return xmlStem == '${videoStem}M01';
  }

  /// Finds companion XML for a video.
  /// If [pairM01Sidecars] is true, also pairs Sony M01 sidecars (stem + 'M01').
  static ScannedFile? findCompanionXml(
    ScannedFile video,
    List<ScannedFile> xmlFiles, {
    bool pairM01Sidecars = true,
  }) {
    final videoStem = p.basenameWithoutExtension(video.basename).toUpperCase();
    for (var xml in xmlFiles) {
      final xmlStem = p.basenameWithoutExtension(xml.basename).toUpperCase();
      if (xmlStem == videoStem) {
        return xml;
      }
      if (pairM01Sidecars && xmlStem == '${videoStem}M01') {
        return xml;
      }
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
    bool pairM01Sidecars = true,
  }) {
    if (targetCamera.toUpperCase() == 'ALL') {
      final camerasSet = <String>{};
      for (final r in log.records) {
        for (final c in r.cameras) {
          if (c.cameraName.trim().isNotEmpty) {
            camerasSet.add(c.cameraName.trim().toUpperCase());
          }
        }
      }
      for (final f in scannedFiles) {
        camerasSet.add(extractCamera(f.basename));
      }
      if (camerasSet.isEmpty) {
        camerasSet.add('A');
      }
      final sortedCameras = camerasSet.toList()..sort();
      final allProposals = <RenameProposal>[];
      final claimedXml = <String>{};

      for (final cam in sortedCameras) {
        final camFiles = scannedFiles.where((f) {
          if (f.isXml && claimedXml.contains(f.path)) return false;
          final fileCam = extractCamera(f.basename, fallback: cam);
          return fileCam == cam;
        }).toList();

        final rep = matchFiles(
          scannedFiles: camFiles,
          log: log,
          targetCamera: cam,
          reelOverride: reelOverride,
          renameHistory: renameHistory,
          manualOverrides: manualOverrides,
          xmlContentsForTesting: xmlContentsForTesting,
          pairM01Sidecars: pairM01Sidecars,
        );

        for (final pItem in rep.proposals) {
          allProposals.add(pItem);
          if (pItem.isCompanionFile && pItem.originalFilePath != null) {
            claimedXml.add(pItem.originalFilePath!);
          }
        }
      }

      return DryRunReport(
        proposals: sortProposals(allProposals, targetCamera: 'ALL'),
      );
    }

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
          final reel = record.reel.trim().toUpperCase();
          final normClip = normalizeClipNumber(cam.clipName);
          final key = '${reel}_$normClip';
          expectedClips[key] = record;
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
        var companion = findCompanionXml(video, xmlFiles, pairM01Sidecars: pairM01Sidecars);
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

        final isAlt = targetRecordId != null && (targetRecordId == '__ALT__' || targetRecordId.startsWith('__ALT__:'));
        final isPrimary = targetRecordId == '__PRIMARY__';
        final effectiveRecordId = (targetRecordId != null && targetRecordId.startsWith('__ALT__:'))
            ? targetRecordId.substring('__ALT__:'.length)
            : targetRecordId;

        if (targetRecordId == null) {
          var companion = findCompanionXml(scanned, xmlFiles, pairM01Sidecars: pairM01Sidecars);
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
          final record = log.records.where((r) => r.id == effectiveRecordId).firstOrNull;
          if (record != null || isPrimary || isAlt) {
            String proposedBase;
            if (record != null) {
              proposedBase = ConventionNameGenerator.generate(
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
              if (isAlt) {
                proposedBase = '${proposedBase}_ALT';
              }
              expectedClips.removeWhere((clipName, r) => r.id == record.id);
            } else {
              String base = p.basenameWithoutExtension(scanned.path);
              if (base.endsWith('_ALT')) {
                base = base.substring(0, base.length - 4);
              }
              proposedBase = isAlt ? '${base}_ALT' : base;
            }

            String ext = scanned.extension.toUpperCase();
            var companion = findCompanionXml(scanned, xmlFiles, pairM01Sidecars: pairM01Sidecars);
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
              final isM01 = isM01Companion(scanned, companion);
              final compBase = isM01 ? '${proposedBase}M01' : proposedBase;
              proposals.add(RenameProposal(
                originalFilePath: companion.path,
                proposedFileName: '$compBase$xmlExt',
                associatedRecord: record,
                status: ProposalStatus.ready,
                isCompanionFile: true,
                fileTcIn: sidecar?.tcIn,
                fileTcOut: sidecar?.tcOut,
                fileReel: fileReel,
              ));
              xmlFiles.remove(companion);
            }
          } else {
            var companion = findCompanionXml(scanned, xmlFiles, pairM01Sidecars: pairM01Sidecars);
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
      final normKey = normalizeClipNumber(clipNum);
      if (normKey.isNotEmpty) {
        final effectiveFileReel = (fileReel ?? targetCamera).trim().toUpperCase();
        final key = '${effectiveFileReel}_$normKey';
        filesByClip.putIfAbsent(key, () => []).add(video);
      } else {
        var companion = findCompanionXml(video, xmlFiles, pairM01Sidecars: pairM01Sidecars);
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

    expectedClips.forEach((clipKey, record) {
      final cam = record.cameras.firstWhere(
        (c) => c.cameraName.toUpperCase() == targetCamera.toUpperCase(),
        orElse: () => CameraTakeRecord(cameraName: targetCamera, clipName: ''),
      );
      final normClip = normalizeClipNumber(cam.clipName);
      final exactKey = '${record.reel.trim().toUpperCase()}_$normClip';
      String matchedKey = exactKey;
      var matchedVideos = filesByClip[exactKey];
      if (matchedVideos == null || matchedVideos.isEmpty) {
        final fallbackKey = '${targetCamera.trim().toUpperCase()}_$normClip';
        if (filesByClip.containsKey(fallbackKey)) {
          matchedVideos = filesByClip[fallbackKey];
          matchedKey = fallbackKey;
        }
      }
      if (matchedVideos == null || matchedVideos.isEmpty) {
        final prefixedKey = '${targetCamera.trim().toUpperCase()}${record.reel.trim().toUpperCase()}_$normClip';
        if (filesByClip.containsKey(prefixedKey)) {
          matchedVideos = filesByClip[prefixedKey];
          matchedKey = prefixedKey;
        }
      }
      if (matchedVideos == null || matchedVideos.isEmpty) {
        for (final entry in filesByClip.entries) {
          if (entry.key.endsWith('_$normClip')) {
            // Only consider this candidate if its key is NOT claimed by another expected record
            if (!expectedClips.containsKey(entry.key)) {
              matchedVideos = entry.value;
              matchedKey = entry.key;
              break;
            }
          }
        }
      }
      
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
        var companion = findCompanionXml(video, xmlFiles, pairM01Sidecars: pairM01Sidecars);
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
          final isM01 = isM01Companion(video, companion);
          final compBase = isM01 ? '${proposedBase}M01' : proposedBase;
          proposals.add(RenameProposal(
            originalFilePath: companion.path,
            proposedFileName: '$compBase$xmlExt',
            associatedRecord: record,
            status: status,
            isCompanionFile: true,
            fileTcIn: sidecar?.tcIn,
            fileTcOut: sidecar?.tcOut,
            fileReel: fileReel,
          ));
          xmlFiles.remove(companion);
        }

        filesByClip.remove(matchedKey);
      } else {
        for (var video in matchedVideos) {
          final fileReel = extractReel(video.basename);
          var companion = findCompanionXml(video, xmlFiles, pairM01Sidecars: pairM01Sidecars);
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
          if (companion != null) {
            String xmlExt = companion.extension.toUpperCase();
            final isM01 = isM01Companion(video, companion);
            final compBase = isM01 ? '${proposedBase}M01' : proposedBase;
            proposals.add(RenameProposal(
              originalFilePath: companion.path,
              proposedFileName: '$compBase$xmlExt',
              associatedRecord: record,
              status: ProposalStatus.conflict,
              isCompanionFile: true,
              fileTcIn: sidecar?.tcIn,
              fileTcOut: sidecar?.tcOut,
              fileReel: fileReel,
            ));
            xmlFiles.remove(companion);
          }
        }
        filesByClip.remove(matchedKey);
      }
    });

    filesByClip.forEach((clipName, videos) {
      final isConflict = videos.length > 1;
      for (var video in videos) {
        final fileReel = extractReel(video.basename);
        var companion = findCompanionXml(video, xmlFiles, pairM01Sidecars: pairM01Sidecars);
        final sidecar = _extractSidecar(companion, xmlContentsForTesting);
        proposals.add(RenameProposal(
          originalFilePath: video.path,
          proposedFileName: video.basename,
          status: isConflict ? ProposalStatus.conflict : ProposalStatus.unmatchedClip,
          fileTcIn: sidecar?.tcIn,
          fileTcOut: sidecar?.tcOut,
          fileReel: fileReel,
        ));
      }
    });

    return DryRunReport(
      proposals: sortProposals(proposals, targetCamera: targetCamera),
    );
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
    bool pairM01Sidecars = true,
  }) async {
    final report = matchFiles(
      scannedFiles: scannedFiles,
      log: log,
      targetCamera: targetCamera,
      reelOverride: reelOverride,
      renameHistory: renameHistory,
      manualOverrides: manualOverrides,
      xmlContentsForTesting: xmlContentsForTesting,
      pairM01Sidecars: pairM01Sidecars,
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
            if (companionStem == videoStem || (pairM01Sidecars && companionStem == '${videoStem}M01')) {
              updatedProposals[i] = pItem.copyWith(status: ProposalStatus.conflict);
              break;
            }
          }
        }
      }
    }

    return DryRunReport(
      proposals: sortProposals(updatedProposals, targetCamera: targetCamera),
    );
  }
}
