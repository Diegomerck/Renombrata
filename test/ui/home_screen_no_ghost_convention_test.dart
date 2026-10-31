import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renombrata/src/models/dry_run_report.dart';
import 'package:renombrata/src/models/renombrata_project.dart';
import 'package:renombrata/src/models/shooting_log.dart';
import 'package:renombrata/src/ui/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Changing settings does not generate ghost convention lines',
      (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    final project = RenombrataProject(
      log: ShootingLog(metadata: ShootingLogMetadata.empty(), records: []),
      defaultReel: 'A001',
      activeCamera: 'A',
    );
    final report = DryRunReport(proposals: [
      for (var i = 1; i <= 3; i++)
        RenameProposal(
          originalFilePath: '/media/A001C00${i}_260817AB.MP4',
          proposedFileName: 'A001C00${i}_260817AB.MP4',
          fileReel: 'A001',
          status: ProposalStatus.unmatchedClip,
        ),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(initialProject: project, initialReport: report),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Renombrador de Medios'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Modo Estudio'));
    await tester.pumpAndSettle();

    final state = tester.state(find.byType(HomeScreen)) as dynamic;
    expect(state.conventionEditorController.text, '');

    state.updateProject(project.copyWith(showPlane: false));
    await tester.pumpAndSettle();
    state.updateProject(project.copyWith(showPlane: true, showChapter: false));
    await tester.pumpAndSettle();

    expect(state.conventionEditorController.text, '');
    expect(state.livePastedOverrides, isEmpty);
    for (final p in state.reportProposals as List<RenameProposal>) {
      expect(p.status, ProposalStatus.unmatchedClip);
    }
  });
}

