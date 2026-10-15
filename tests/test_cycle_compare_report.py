"""Log grouping must not promote missing, cancelled or partial evidence to PASS."""
from pathlib import Path
import importlib.util
import unittest

SPEC = importlib.util.spec_from_file_location("cycle_compare_report", Path(__file__).resolve().parents[1] / "cycle_compare_report.py")
REPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPORT)

START = "== conch_test severed_oath compare START: 50 benches ==\n"
END = "== conch_test severed_oath compare END: 9 PASS, 1 FAIL, 2 SKIP ==\n"


def measurement(arm="native", status="PASS"):
    return (f"[ItemTest:SEVERED_OATH] DIAG CYCLE_COMPARE (case=capacity0 arm={arm} phase=grant status={status} "
            "before=1 after=2 decrease=1 preview=0 weightLost=1 poolKnown=true frames=8 seed=123 "
            "ringsBefore=1@0:0:-1:false ringsAfter=1,2@0:0:-1:false reason=done)\n")


class ReportTests(unittest.TestCase):
    def test_only_latest_explicit_suite_and_no_invented_completion(self):
        text = START + measurement() + END + START + measurement("oath")
        rows, benches, complete, _ = REPORT.parse_log(text)
        self.assertFalse(complete)
        self.assertFalse(benches)
        self.assertNotIn(("capacity0", "grant", "native"), rows)
        self.assertIn("미완료/미실행", REPORT.render_report(text))

    def test_failure_outside_measurement_overrides_successful_grant(self):
        text = START + measurement() + "FAIL full queue consumes pool\n"
        text += "== conch_test severed_oath compare_capacity0_native END: 8 PASS, 1 FAIL, 0 SKIP ==\n" + END
        result = REPORT.render_report(text)
        self.assertIn("FAIL (8/1/0)", result)
        self.assertIn("1/50", result)
        self.assertIn("full queue consumes pool", result)

    def test_room_source_and_new_overlap_review_remain_visible(self):
        diag = measurement().replace("reason=done", "expectedPool=3 source=REVIEW newSame=1 newCross=2 reason=done")
        text = START + diag + "== conch_test severed_oath compare_capacity0_native END: 8 PASS, 0 FAIL, 2 SKIP ==\n" + END
        result = REPORT.render_report(text)
        self.assertIn("방풀 REVIEW", result)
        self.assertIn("내부 1 / 다른 받침대 2", result)
        self.assertIn("SKIP 포함", result)

    def test_reason_cannot_overwrite_counts_or_hide_metadata_failure(self):
        diag = measurement(status="FAIL").replace("reason=done", "contract=PASS metadata=FAIL reason=metadata before=0:0:-1:false after=0:0:-1:true")
        check = "FAIL comparison contract (see preceding CYCLE_COMPARE) (price changed)\n"
        text = START + diag + check + END
        rows, _, _, failures = REPORT.parse_log(text)
        row = rows[("capacity0", "grant", "native")]
        self.assertEqual((row["before"], row["after"]), ("1", "2"))
        report = REPORT.render_report(text)
        self.assertIn("주 검사 PASS, 가격·옵션 FAIL", report)
        self.assertIn("metadata before=0:0:-1:false", report)
        self.assertIn(check.strip(), failures)

    def test_duplicate_end_summaries_are_not_double_counted_and_skip_not_pass(self):
        member = "== conch_test severed_oath compare_golden0_oath END: 0 PASS, 0 FAIL, 1 SKIP ==\n"
        rows, benches, complete, _ = REPORT.parse_log(START + member * 2 + END + measurement())
        self.assertTrue(complete)
        self.assertEqual(len(benches), 1)
        self.assertFalse(rows, "unrelated later diagnostics leaked into finished suite")
        self.assertIn("SKIP 포함 (0/0/1)", REPORT.render_report(START + member + END))

    def test_no_suite_rejected_and_truncated_measurement_ignored(self):
        with self.assertRaises(ValueError):
            REPORT.parse_log(measurement())
        rows, _, complete, _ = REPORT.parse_log(START + "DIAG CYCLE_COMPARE (case=capacity0 arm=oath phase=grant")
        self.assertFalse(rows)
        self.assertFalse(complete)


if __name__ == "__main__":
    unittest.main()
