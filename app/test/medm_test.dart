import 'package:flutter_test/flutter_test.dart';
import 'package:open_cuff/medm_import.dart';

void main() {
  test('reads a MedM blood pressure export', () {
    const csv = '\uFEFF"Date","Time","Sys","Dia","Pulse","Irregular pulse","Source"\n'
        '"2026-01-12","09:15","128","82","96","detected","OxiPro BP2"\n'
        '"2025-03-04","16:40","112","71","74","not detected","OxiPro BP2"\n';
    final rs = MedmImport.parse(csv, 1);
    expect(rs, hasLength(2));
    expect([rs[0].systolic, rs[0].diastolic, rs[0].pulse, rs[0].irregular], [128, 82, 96, true]);
    expect(rs[0].time, DateTime(2026, 1, 12, 9, 15));
    expect(rs[1].irregular, isFalse);
    expect(rs[0].source, 'cuff');
  });

}
