import 'dart:io';
import 'package:renombrata/src/models/renombrata_project.dart';
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
    final match =
        RegExp(
          r'^([A-Za-z])_?(\d{1,4})_?[cC]\d+',
          caseSensitive: false,
        ).firstMatch(clean) ??
        RegExp(
          r'^([A-Za-z])_?(\d{1,4})_',
          caseSensitive: false,
        ).firstMatch(clean);
    if (match != null) {
      final cam = match.group(1)!.toUpperCase();
      final numStr = match.group(2)!;
      final parsed = int.tryParse(numStr);
      final padLen = numStr.length == 4 ? 4 : 3;
      final formattedNum = parsed != null
          ? parsed.toString().padLeft(padLen, '0')
          : numStr;
      return '$cam$formattedNum';
    }
    return null;
  }

  /// Extracts the camera letter from standard clip filenames.
  /// Examples:
  /// - "A001C002.MP4" -> "A"
  /// - "A_0001C001...MXF" -> "A"
  /// - "B002C015.MOV" -> "B"
  /// - "C0001.MP4" -> fallback ("A")
  static String extractCamera(String filename, {String fallback = 'A'}) {
    final clean = p.basename(filename);
    final match = RegExp(
      r'^([A-Za-z])_?\d{1,4}_?[cC]\d+',
      caseSensitive: false,
    ).firstMatch(clean);
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

      final reelA =
          a.fileReel ??
          extractReel(a.originalFilePath ?? '') ??
          a.associatedRecord?.reel ??
          '';
      final reelB =
          b.fileReel ??
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
          if (prop.isCompanionFile && prop.companionFilePath != null) {
            String s = p
                .basenameWithoutExtension(prop.companionFilePath!)
                .toUpperCase();
            if (s.endsWith('M01') && s.length > 3) {
              s = s.substring(0, s.length - 3);
            }
            return s;
          }
          String s = p
              .basenameWithoutExtension(prop.originalFilePath!)
              .toUpperCase();
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

      return (a.originalFilePath ?? a.proposedFileName).compareTo(
        b.originalFilePath ?? b.proposedFileName,
      );
    });
    return sorted;
  }

  static String extractClipNumber(String filename) {
    String baseName = p.basenameWithoutExtension(filename);

    // 1. Check standard camera clip pattern: e.g. "A001C001", "A_0001C001", "A001_C001", "B002C015"
    final camClipMatch = RegExp(
      r'[A-Za-z]_?\d{1,4}_?[cC](\d{1,4})',
      caseSensitive: false,
    ).firstMatch(baseName);
    if (camClipMatch != null) {
      int num = int.parse(camClipMatch.group(1)!);
      return num.toString().padLeft(3, '0');
    }

    // GoPro pattern: e.g. "GX018226", "GL018226", "GH010042", "GOPR0042"
    final goProMatch =
        RegExp(
          r'^G[A-Z0-9]{1,3}\d{2}(\d{4})$',
          caseSensitive: false,
        ).firstMatch(baseName) ??
        RegExp(r'^GOPR(\d{4})$', caseSensitive: false).firstMatch(baseName);
    if (goProMatch != null) {
      int num = int.parse(goProMatch.group(1)!);
      return num.toString().padLeft(3, '0');
    }

    // e.g. "_C001_", "C0001", "CLIP_C002"
    final cMatch = RegExp(
      r'(?:^|[_-\s])[cC](\d{1,4})(?:[_-\s.]|$)',
    ).firstMatch(baseName);
    if (cMatch != null) {
      int num = int.parse(cMatch.group(1)!);
      return num.toString().padLeft(3, '0');
    }

    // e.g. "001", "1", "12"
    final pureNumMatch = RegExp(r'^(\d{1,4})$').firstMatch(baseName);
    if (pureNumMatch != null) {
      int num = int.parse(pureNumMatch.group(1)!);
      return num.toString().padLeft(3, '0');
    }

    // 2. Check if this is a multi-token convention string (e.g. MNBOENC_080626_17_11_T1_A001_1_D1_U3)
    final tokens = baseName.split('_');
    if (tokens.length >= 4) {
      // Find reel token (e.g. "A001", "B002", "001")
      final reelIdx = tokens.indexWhere(
        (t) => RegExp(r'^[A-Za-z]?\d{3,4}$').hasMatch(t),
      );
      if (reelIdx != -1) {
        // Look at subsequent tokens for the clip index (a pure number not prefixed by U, D, T, etc.)
        for (int i = reelIdx + 1; i < tokens.length; i++) {
          final token = tokens[i];
          if (RegExp(r'^[Uu]\d+$').hasMatch(token) ||
              token.toUpperCase() == 'DS' ||
              RegExp(r'^[Dd]\d+$').hasMatch(token) ||
              RegExp(r'^[Tt][Ff]?\d+$').hasMatch(token) ||
              RegExp(r'^\d{6,8}$').hasMatch(token)) {
            continue;
          }
          final parsed = int.tryParse(token);
          if (parsed != null && parsed > 0 && parsed <= 9999) {
            return parsed.toString().padLeft(3, '0');
          }
        }
      }
      // If no valid clip index token found in a multi-token string, do NOT fallback to last number (e.g. U3)
      return '';
    }

    // 3. Fallback for simple short filenames (fewer than 4 tokens, e.g. "CLIP_001")
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

  static SidecarMetadata? _extractSidecar(
    ScannedFile? companion, [
    Map<String, String>? testContents,
  ]) {
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

  /// Extracts the camera-clip prefix (e.g. "A001C001", "A_0001C001", "B002C015")
  static String? extractCameraClipPrefix(String filename) {
    final clean = p.basenameWithoutExtension(filename);
    final match = RegExp(
      r'^([A-Za-z]_?\d{1,4}_?[cC]\d{1,4})',
      caseSensitive: false,
    ).firstMatch(clean);
    if (match != null) {
      return match.group(1)!.toUpperCase().replaceAll('_', '');
    }
    final cOnlyMatch = RegExp(
      r'^([cC]\d{1,4})',
      caseSensitive: false,
    ).firstMatch(clean);
    if (cOnlyMatch != null) {
      return cOnlyMatch.group(1)!.toUpperCase().replaceAll('_', '');
    }
    return null;
  }

  /// Checks if [xml] is a Sony M01 metadata sidecar for [video].
  static bool isM01Companion(ScannedFile video, ScannedFile xml) {
    if (!xml.isXml) return false;
    final videoStem = p.basenameWithoutExtension(video.basename).toUpperCase();
    final xmlStem = p.basenameWithoutExtension(xml.basename).toUpperCase();
    return xmlStem == '${videoStem}M01' || videoStem == '${xmlStem}M01';
  }

  /// Checks if [candidate] is a companion file for [masterVideo].
  ///
  /// Matches:
  /// - Exact stem without extension (e.g. GX018226.THM matching GX018226.MP4, A001C001.SRT matching A001C001.MXF)
  /// - GoPro 6-digit chapter + clip index (e.g. GL018226.LRV or GX018226.THM matching GX018226.MP4)
  /// - Sony M01 sidecars (e.g. A001C001M01.XML matching A001C001.MP4)
  static bool isCompanionForVideo(
    ScannedFile masterVideo,
    ScannedFile candidate, {
    bool pairM01Sidecars = true,
  }) {
    if (candidate.path == masterVideo.path) return false;
    final masterStem = p
        .basenameWithoutExtension(masterVideo.basename)
        .toUpperCase();
    final candStem = p
        .basenameWithoutExtension(candidate.basename)
        .toUpperCase();

    // 1. Exact stem match
    if (masterStem == candStem) return true;

    // 2. Sony M01 XML
    if (pairM01Sidecars && candidate.isXml) {
      if (candStem == '${masterStem}M01' || masterStem == '${candStem}M01') {
        return true;
      }
    }

    // 3. GoPro 6-digit chapter + clip index: e.g. GX018226 and GL018226
    final mMatch = RegExp(r'^G[A-Z0-9]{1,3}(\d{6})$').firstMatch(masterStem);
    final cMatch = RegExp(r'^G[A-Z0-9]{1,3}(\d{6})$').firstMatch(candStem);
    if (mMatch != null &&
        cMatch != null &&
        mMatch.group(1) == cMatch.group(1)) {
      return true;
    }

    return false;
  }

  /// Finds all companion files (.xml, .lrv, .thm, .bim, .srt) for [video] from [candidateCompanions].
  static List<ScannedFile> findCompanionsForVideo(
    ScannedFile video,
    List<ScannedFile> candidateCompanions, {
    bool pairM01Sidecars = true,
  }) {
    final matched = <ScannedFile>[];

    // 1. XML sidecar via findCompanionXml (handles exact, M01, prefix, reel/clip)
    final xmls = candidateCompanions.where((f) => f.isXml).toList();
    final xmlComp = findCompanionXml(
      video,
      xmls,
      pairM01Sidecars: pairM01Sidecars,
    );
    if (xmlComp != null) {
      matched.add(xmlComp);
    }

    // 2. Non-XML companions (.lrv, .thm, .bim, .srt, etc.)
    for (final cand in candidateCompanions) {
      if (cand.isXml) continue;
      if (isCompanionForVideo(video, cand, pairM01Sidecars: pairM01Sidecars)) {
        matched.add(cand);
      }
    }

    return matched;
  }

  /// Finds companion XML for a video.
  /// Matches by:
  /// a) Exact basename without extension (case-insensitive)
  /// b) Sony M01 suffix: xml stem == '${videoStem}M01' or videoStem == '${xmlStem}M01'
  /// c) Subdirectory sidecars (e.g. video in 'CLIP/' and xml in 'MEDIAMETA/' with the same stem)
  /// d) Stripped reel/clip stems sharing the same camera-clip prefix (e.g. 'A001C001' or 'A_0001C001')
  static ScannedFile? findCompanionXml(
    ScannedFile video,
    List<ScannedFile> xmlFiles, {
    bool pairM01Sidecars = true,
  }) {
    if (xmlFiles.isEmpty) return null;

    final videoStem = p.basenameWithoutExtension(video.basename).toUpperCase();
    final videoDir = p.dirname(video.path).toLowerCase();
    final videoParentDir = p.dirname(videoDir).toLowerCase();
    final videoPrefix = extractCameraClipPrefix(video.basename);

    // Pass 1: Exact basename match without extension (case-insensitive)
    ScannedFile? exactSameDir;
    ScannedFile? exactSiblingDir;
    ScannedFile? exactAny;

    for (final xml in xmlFiles) {
      final xmlStem = p.basenameWithoutExtension(xml.basename).toUpperCase();
      if (xmlStem == videoStem) {
        final xmlDir = p.dirname(xml.path).toLowerCase();
        final xmlParentDir = p.dirname(xmlDir).toLowerCase();
        if (xmlDir == videoDir) {
          exactSameDir ??= xml;
        } else if (xmlParentDir == videoParentDir) {
          exactSiblingDir ??= xml;
        } else {
          exactAny ??= xml;
        }
      }
    }
    if (exactSameDir != null) return exactSameDir;
    if (exactSiblingDir != null) return exactSiblingDir;
    if (exactAny != null) return exactAny;

    // Pass 2: Sony M01 suffix
    if (pairM01Sidecars) {
      ScannedFile? m01SameDir;
      ScannedFile? m01SiblingDir;
      ScannedFile? m01Any;

      for (final xml in xmlFiles) {
        final xmlStem = p.basenameWithoutExtension(xml.basename).toUpperCase();
        if (xmlStem == '${videoStem}M01' || videoStem == '${xmlStem}M01') {
          final xmlDir = p.dirname(xml.path).toLowerCase();
          final xmlParentDir = p.dirname(xmlDir).toLowerCase();
          if (xmlDir == videoDir) {
            m01SameDir ??= xml;
          } else if (xmlParentDir == videoParentDir) {
            m01SiblingDir ??= xml;
          } else {
            m01Any ??= xml;
          }
        }
      }
      if (m01SameDir != null) return m01SameDir;
      if (m01SiblingDir != null) return m01SiblingDir;
      if (m01Any != null) return m01Any;
    }

    // Pass 3 & 4: Stripped camera-clip prefix matching
    if (videoPrefix != null) {
      ScannedFile? prefixSameDir;
      ScannedFile? prefixSiblingDir;
      ScannedFile? prefixAny;

      for (final xml in xmlFiles) {
        final xmlStem = p.basenameWithoutExtension(xml.basename).toUpperCase();
        if (!pairM01Sidecars && xmlStem.endsWith('M01')) {
          continue;
        }
        final xmlPrefix = extractCameraClipPrefix(xml.basename);
        if (xmlPrefix != null && xmlPrefix == videoPrefix) {
          final xmlDir = p.dirname(xml.path).toLowerCase();
          final xmlParentDir = p.dirname(xmlDir).toLowerCase();
          if (xmlDir == videoDir) {
            prefixSameDir ??= xml;
          } else if (xmlParentDir == videoParentDir) {
            prefixSiblingDir ??= xml;
          } else {
            prefixAny ??= xml;
          }
        }
      }
      if (prefixSameDir != null) return prefixSameDir;
      if (prefixSiblingDir != null) return prefixSiblingDir;
      if (prefixAny != null) return prefixAny;
    }

    // Pass 5: Shared reel and clip number
    final videoReel = extractReel(video.basename);
    final videoClipNum = normalizeClipNumber(extractClipNumber(video.basename));
    if (videoClipNum.isNotEmpty) {
      for (final xml in xmlFiles) {
        final xmlStem = p.basenameWithoutExtension(xml.basename).toUpperCase();
        if (!pairM01Sidecars && xmlStem.endsWith('M01')) {
          continue;
        }
        final xmlReel = extractReel(xml.basename);
        final xmlClipNum = normalizeClipNumber(extractClipNumber(xml.basename));
        if (xmlClipNum == videoClipNum) {
          if (videoReel != null && xmlReel != null) {
            if (RenameProposal.isReelMatched(videoReel, xmlReel)) {
              return xml;
            }
          } else if (videoReel == null && xmlReel == null) {
            return xml;
          }
        }
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
    Map<String, CameraType> cameraTypes = const {},
  }) {
    if (targetCamera.toUpperCase() == 'ALL') {
      final originalPathByRenamedBasename = <String, String>{};
      for (var e in renameHistory) {
        final renamedPath = e['renamedPath'] as String?;
        final originalPath = e['originalPath'] as String?;
        if (renamedPath != null && originalPath != null) {
          originalPathByRenamedBasename[p.basename(renamedPath).toLowerCase()] =
              originalPath;
        }
      }

      final camerasSet = <String>{};
      for (final r in log.records) {
        for (final c in r.cameras) {
          if (c.cameraName.trim().isNotEmpty) {
            camerasSet.add(c.cameraName.trim().toUpperCase());
          }
        }
      }
      for (final f in scannedFiles) {
        final origPath =
            originalPathByRenamedBasename[f.basename.toLowerCase()];
        final camToUse = origPath != null
            ? extractCamera(p.basename(origPath))
            : extractCamera(f.basename);
        camerasSet.add(camToUse);
      }
      if (camerasSet.isEmpty) {
        camerasSet.add('A');
      }
      final sortedCameras = camerasSet.toList()..sort();
      final allProposals = <RenameProposal>[];
      final claimedXml = <String>{};

      for (final cam in sortedCameras) {
        final camFiles = scannedFiles.where((f) {
          if ((f.isXml || f.isCompanion) && claimedXml.contains(f.path)) {
            return false;
          }
          final origPath =
              originalPathByRenamedBasename[f.basename.toLowerCase()];
          final fileCam = origPath != null
              ? extractCamera(p.basename(origPath), fallback: cam)
              : extractCamera(f.basename, fallback: cam);
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
          cameraTypes: cameraTypes,
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

    bool isCompanionLrv(ScannedFile file) {
      if (file.extension != '.lrv') return false;
      return scannedFiles.any(
        (other) =>
            other.path != file.path &&
            other.isPrimaryVideo &&
            isCompanionForVideo(other, file, pairM01Sidecars: pairM01Sidecars),
      );
    }

    var videoFiles = scannedFiles.where((f) {
      if (!f.isVideo && !f.isAudio) return false;
      if (isCompanionLrv(f)) return false;
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

    var companionFiles = scannedFiles.where((f) {
      if (f.isXml || f.isCompanion || isCompanionLrv(f)) {
        String base = p.basenameWithoutExtension(f.basename).toUpperCase();
        final match = RegExp(r'^([A-Z])\d+C\d+').firstMatch(base);
        if (match != null) {
          String fileCamera = match.group(1)!;
          if (fileCamera != targetCamera.toUpperCase()) {
            return false;
          }
        }
        return true;
      }
      return false;
    }).toList();

    void addVideoAndCompanions({
      required ScannedFile video,
      required String proposedFileName,
      required ProposalStatus status,
      ShotRecord? associatedRecord,
      String? fileReel,
      String? fileTcIn,
      String? fileTcOut,
      bool checkConflict = false,
    }) {
      final companions = findCompanionsForVideo(
        video,
        companionFiles,
        pairM01Sidecars: pairM01Sidecars,
      );
      final xmlCompanion = companions.where((f) => f.isXml).firstOrNull;
      final sidecar = _extractSidecar(xmlCompanion, xmlContentsForTesting);
      final effectiveTcIn = sidecar?.tcIn ?? fileTcIn;
      final effectiveTcOut = sidecar?.tcOut ?? fileTcOut;

      var finalStatus = status;
      final initialProposal = RenameProposal(
        originalFilePath: video.path,
        proposedFileName: proposedFileName,
        associatedRecord: associatedRecord,
        status: status,
        fileReel: fileReel,
        fileTcIn: effectiveTcIn,
        fileTcOut: effectiveTcOut,
        companionFilePath: companions.isNotEmpty ? companions.first.path : null,
      );

      if (checkConflict) {
        final isOverridden = manualOverrides.containsKey(video.path);
        finalStatus =
            ((initialProposal.hasTimecodeDiscrepancy ||
                    initialProposal.hasReelDiscrepancy) &&
                !isOverridden)
            ? ProposalStatus.conflict
            : ProposalStatus.ready;
      }

      proposals.add(initialProposal.copyWith(status: finalStatus));

      final proposedBase = p.basenameWithoutExtension(proposedFileName);
      for (final comp in companions) {
        final compExt = p.extension(comp.path).toUpperCase();
        final isM01 = isM01Companion(video, comp);
        final compBase = isM01 ? '${proposedBase}M01' : proposedBase;

        proposals.add(
          RenameProposal(
            originalFilePath: comp.path,
            proposedFileName: '$compBase$compExt',
            associatedRecord: associatedRecord,
            status: finalStatus,
            isCompanionFile: true,
            fileReel: fileReel,
            fileTcIn: effectiveTcIn,
            fileTcOut: effectiveTcOut,
            companionFilePath: video.path,
          ),
        );
        companionFiles.remove(comp);
      }
    }

    Set<String> renamedBasenames = renameHistory
        .map((e) {
          final renamedPath = e['renamedPath'] as String?;
          return renamedPath != null ? p.basename(renamedPath) : '';
        })
        .where((s) => s.isNotEmpty)
        .toSet();

    final originalPathByRenamedBasename = <String, String>{};
    for (var e in renameHistory) {
      final renamedPath = e['renamedPath'] as String?;
      final originalPath = e['originalPath'] as String?;
      if (renamedPath != null && originalPath != null) {
        originalPathByRenamedBasename[p.basename(renamedPath).toLowerCase()] =
            originalPath;
      }
    }

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

    // Process already renamed files based on renameHistory
    for (var video in List<ScannedFile>.from(videoFiles)) {
      final vBaseLower = video.basename.toLowerCase();
      final origPath = originalPathByRenamedBasename[vBaseLower];
      final isHist = origPath != null;

      if (isHist || renamedBasenames.contains(video.basename)) {
        final origBasename = origPath != null ? p.basename(origPath) : null;
        final origReel = origBasename != null
            ? extractReel(origBasename)
            : extractReel(video.basename);
        final origClipNum = origBasename != null
            ? extractClipNumber(origBasename)
            : extractClipNumber(video.basename);
        final normOrigClip = normalizeClipNumber(origClipNum);

        // Find matching ShotRecord from log.records
        ShotRecord? matchingRecord;
        for (final r in log.records) {
          final hasCam = r.cameras.any((c) {
            final cNorm = normalizeClipNumber(c.clipName);
            if (cNorm.isEmpty || cNorm != normOrigClip) return false;
            if (targetCamera.toUpperCase() != 'ALL' &&
                c.cameraName.toUpperCase() != targetCamera.toUpperCase()) {
              return false;
            }
            return true;
          });
          if (hasCam) {
            if (origReel != null && r.reel.trim().isNotEmpty) {
              final rReelNum = r.reel.replaceAll(RegExp(r'^[A-Z]'), '');
              final origReelNum = origReel.replaceAll(RegExp(r'^[A-Z]'), '');
              if (r.reel.toUpperCase() == origReel.toUpperCase() ||
                  rReelNum == origReelNum) {
                matchingRecord = r;
                break;
              }
            } else {
              matchingRecord = r;
              break;
            }
          }
        }

        if (matchingRecord != null) {
          expectedClips.removeWhere((k, r) => r.id == matchingRecord!.id);
        }

        addVideoAndCompanions(
          video: video,
          proposedFileName: video.basename,
          status: ProposalStatus.alreadyRenamed,
          associatedRecord: matchingRecord,
          fileReel: origReel,
        );
        videoFiles.remove(video);
      }
    }

    // Process already renamed files based on proposed convention names
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
        cameraType:
            cameraTypes[targetCamera.toUpperCase()] ?? CameraType.regular,
      );

      var alreadyRenamedVideoList = videoFiles
          .where(
            (v) =>
                p.basenameWithoutExtension(v.basename).toUpperCase() ==
                proposedBase.toUpperCase(),
          )
          .toList();

      if (alreadyRenamedVideoList.isNotEmpty) {
        var video = alreadyRenamedVideoList.first;
        final fileReel = extractReel(video.basename) ?? record.reel;

        addVideoAndCompanions(
          video: video,
          proposedFileName: video.basename,
          status: ProposalStatus.alreadyRenamed,
          associatedRecord: record,
          fileReel: fileReel,
        );
        videoFiles.remove(video);
        return true;
      }
      return false;
    });

    // Process manual overrides (conflict resolution & explicit assignments)
    for (var scanned in List<ScannedFile>.from(
      scannedFiles.where((f) => f.isVideo),
    )) {
      if (manualOverrides.containsKey(scanned.path)) {
        videoFiles.removeWhere((v) => v.path == scanned.path);
        final targetRecordId = manualOverrides[scanned.path];
        final fileReel = extractReel(scanned.basename);

        final isAlt =
            targetRecordId != null &&
            (targetRecordId == '__ALT__' ||
                targetRecordId.startsWith('__ALT__:'));
        final isPrimary = targetRecordId == '__PRIMARY__';
        final effectiveRecordId =
            (targetRecordId != null && targetRecordId.startsWith('__ALT__:'))
            ? targetRecordId.substring('__ALT__:'.length)
            : targetRecordId;

        if (targetRecordId == null) {
          addVideoAndCompanions(
            video: scanned,
            proposedFileName: scanned.basename,
            status: ProposalStatus.unmatchedClip,
            fileReel: fileReel,
          );
        } else {
          final record = log.records
              .where((r) => r.id == effectiveRecordId)
              .firstOrNull;
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
                cameraType:
                    cameraTypes[targetCamera.toUpperCase()] ??
                    CameraType.regular,
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
            addVideoAndCompanions(
              video: scanned,
              proposedFileName: '$proposedBase$ext',
              status: ProposalStatus.ready,
              associatedRecord: record,
              fileReel: fileReel,
            );
          } else {
            addVideoAndCompanions(
              video: scanned,
              proposedFileName: scanned.basename,
              status: ProposalStatus.unmatchedClip,
              fileReel: fileReel,
            );
          }
        }
      }
    }

    Map<String, List<ScannedFile>> filesByClip = {};
    for (var video in videoFiles) {
      final fileReel = extractReel(video.basename);
      if (renamedBasenames.contains(video.basename)) {
        addVideoAndCompanions(
          video: video,
          proposedFileName: video.basename,
          status: ProposalStatus.alreadyRenamed,
          fileReel: fileReel,
        );
        continue;
      }

      String clipNum = extractClipNumber(video.basename);
      final normKey = normalizeClipNumber(clipNum);
      if (normKey.isNotEmpty) {
        final effectiveFileReel = (fileReel ?? targetCamera)
            .trim()
            .toUpperCase();
        final key = '${effectiveFileReel}_$normKey';
        filesByClip.putIfAbsent(key, () => []).add(video);
      } else {
        addVideoAndCompanions(
          video: video,
          proposedFileName: video.basename,
          status: ProposalStatus.unmatchedClip,
          fileReel: fileReel,
        );
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
        final prefixedKey =
            '${targetCamera.trim().toUpperCase()}${record.reel.trim().toUpperCase()}_$normClip';
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
        cameraType:
            cameraTypes[targetCamera.toUpperCase()] ?? CameraType.regular,
      );

      if (matchedVideos == null || matchedVideos.isEmpty) {
        proposals.add(
          RenameProposal(
            originalFilePath: null,
            proposedFileName: '$proposedBase.MP4',
            associatedRecord: record,
            status: ProposalStatus.missingFile,
          ),
        );
      } else if (matchedVideos.length == 1) {
        var video = matchedVideos.first;
        final fileReel = extractReel(video.basename);
        String ext = video.extension.toUpperCase();

        addVideoAndCompanions(
          video: video,
          proposedFileName: '$proposedBase$ext',
          status: ProposalStatus.ready,
          associatedRecord: record,
          fileReel: fileReel,
          checkConflict: true,
        );

        filesByClip.remove(matchedKey);
      } else {
        for (var video in matchedVideos) {
          final fileReel = extractReel(video.basename);
          addVideoAndCompanions(
            video: video,
            proposedFileName: '$proposedBase${video.extension.toUpperCase()}',
            status: ProposalStatus.conflict,
            associatedRecord: record,
            fileReel: fileReel,
          );
        }
        filesByClip.remove(matchedKey);
      }
    });

    filesByClip.forEach((clipName, videos) {
      final isConflict = videos.length > 1;
      for (var video in videos) {
        final fileReel = extractReel(video.basename);
        addVideoAndCompanions(
          video: video,
          proposedFileName: video.basename,
          status: isConflict
              ? ProposalStatus.conflict
              : ProposalStatus.unmatchedClip,
          fileReel: fileReel,
        );
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
    Map<String, CameraType> cameraTypes = const {},
    void Function(int current, int total, String currentFileName)? onProgress,
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
      cameraTypes: cameraTypes,
    );

    final updatedProposals = <RenameProposal>[];
    final conflictedVideoPaths = <String>{};

    final candidatesToProbe = report.proposals.where((prop) {
      if (prop.isCompanionFile ||
          prop.originalFilePath == null ||
          prop.fileTcIn != null) {
        return false;
      }
      final ext = p.extension(prop.originalFilePath!).toLowerCase();
      return ['.mov', '.mxf', '.mp4', '.crm', '.lrv'].contains(ext);
    }).toList();
    final totalToProbe = candidatesToProbe.length;
    int probeIndex = 0;

    for (final proposal in report.proposals) {
      if (!proposal.isCompanionFile &&
          proposal.originalFilePath != null &&
          proposal.fileTcIn == null) {
        final ext = p.extension(proposal.originalFilePath!).toLowerCase();
        if (['.mov', '.mxf', '.mp4', '.crm', '.lrv'].contains(ext)) {
          probeIndex++;
          onProgress?.call(
            probeIndex,
            totalToProbe,
            p.basename(proposal.originalFilePath!),
          );
          final probe = probeFunction != null
              ? await probeFunction(proposal.originalFilePath!)
              : await EmbeddedMetadataProbeService.probeFile(
                  proposal.originalFilePath!,
                );
          if (probe != null && probe.tcIn != null) {
            final probedProposal = proposal.copyWith(
              fileTcIn: probe.tcIn,
              fileTcOut: probe.tcOut,
            );
            final isOverridden = manualOverrides.containsKey(
              proposal.originalFilePath,
            );
            final newStatus =
                ((probedProposal.hasTimecodeDiscrepancy ||
                        probedProposal.hasReelDiscrepancy) &&
                    !isOverridden)
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
          final companionStem = p
              .basenameWithoutExtension(pItem.originalFilePath!)
              .toUpperCase();
          for (final videoPath in conflictedVideoPaths) {
            final videoStem = p
                .basenameWithoutExtension(videoPath)
                .toUpperCase();
            if (pItem.companionFilePath == videoPath ||
                companionStem == videoStem ||
                (pairM01Sidecars && companionStem == '${videoStem}M01')) {
              updatedProposals[i] = pItem.copyWith(
                status: ProposalStatus.conflict,
              );
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

  /// Asynchronous variant of [matchFiles] that probes standalone video files
  /// (.mov, .mxf, .mp4, .crm, .lrv) for embedded timecodes via MediaInfo or FFprobe
  /// whenever no companion XML timecode was found.
  static Future<DryRunReport> matchClipsWithEmbeddedMetadata({
    required List<ScannedFile> scannedFiles,
    required ShootingLog log,
    required String targetCamera,
    String? reelOverride,
    List<Map<String, dynamic>> renameHistory = const [],
    Map<String, String?> manualOverrides = const {},
    Map<String, String>? xmlContentsForTesting,
    Future<SidecarMetadata?> Function(String filePath)? probeFunction,
    bool pairM01Sidecars = true,
    Map<String, CameraType> cameraTypes = const {},
    void Function(int current, int total, String currentFileName)? onProgress,
  }) => matchFilesAsync(
    scannedFiles: scannedFiles,
    log: log,
    targetCamera: targetCamera,
    reelOverride: reelOverride,
    renameHistory: renameHistory,
    manualOverrides: manualOverrides,
    xmlContentsForTesting: xmlContentsForTesting,
    probeFunction: probeFunction,
    pairM01Sidecars: pairM01Sidecars,
    cameraTypes: cameraTypes,
    onProgress: onProgress,
  );
}
