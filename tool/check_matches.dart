import 'dart:async';
import '../lib/db_helper.dart';

Future<void> main() async {
  final ids = [1483, 1484, 1485, 1486, 1487, 1488];
  try {
    final conn = await DBHelper.getConnection();
    for (final id in ids) {
      print('\n--- MATCH $id ---');
      try {
        final r1 = await conn.execute(
          'SELECT * FROM tbl_double_elimination WHERE match_id = :id',
          {'id': id},
        );
        if (r1.rows.isNotEmpty) {
          print('tbl_double_elimination: ${r1.rows.first.assoc()}');
        } else {
          print('tbl_double_elimination: <NO ROW>');
        }
      } catch (e) {
        print('tbl_double_elimination: ERROR -> $e');
      }

      try {
        final r2 = await conn.execute(
          'SELECT * FROM tbl_explorer_double_elimination WHERE match_id = :id',
          {'id': id},
        );
        if (r2.rows.isNotEmpty) {
          print('tbl_explorer_double_elimination: ${r2.rows.first.assoc()}');
        } else {
          print('tbl_explorer_double_elimination: <NO ROW>');
        }
      } catch (e) {
        print('tbl_explorer_double_elimination: ERROR -> $e');
      }

      try {
        final r3 = await conn.execute(
          'SELECT * FROM tbl_championship_bestof3 WHERE match_round = 1 AND match_position = :pos LIMIT 10',
          {'pos': id},
        );
        if (r3.rows.isNotEmpty) {
          print('tbl_championship_bestof3 (sample by position): ${r3.rows.map((r) => r.assoc()).toList()}');
        } else {
          print('tbl_championship_bestof3: <NO ROWS for position=$id>');
        }
      } catch (e) {
        print('tbl_championship_bestof3: ERROR -> $e');
      }
    }

    try {
      await conn.close();
    } catch (_) {}
  } catch (e) {
    print('Could not connect using DBHelper.getConnection(): $e');
    print('Please ensure your DB credentials in lib/config.dart are correct and the DB is reachable.');
  }
}
