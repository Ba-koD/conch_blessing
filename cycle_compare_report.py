"""Summarize the latest explicit native/Oath comparison suite from Isaac's log.

Usage: python cycle_compare_report.py --log PATH [--out PATH]
Reads a supplied log once; never controls Isaac or polls for completion.
"""
import argparse
from pathlib import Path
import re

START = "== conch_test severed_oath compare START:"
END = "== conch_test severed_oath compare END:"
MEMBER = re.compile(r"== conch_test severed_oath compare_(\w+)_(native|oath) END: (\d+) PASS, (\d+) FAIL, (\d+) SKIP ==")
FIELDS = re.compile(r"\b(case|arm|phase|status|contract|metadata|before|after|decrease|preview|weightLost|poolKnown|frames|seed|expectedPool|source|newSame|newCross)=([^\s)]+)")


def parse_log(text):
    start = text.rfind(START)
    if start < 0:
        raise ValueError("No explicit 'conch_test severed_oath compare' suite found in this log.")
    text = text[start:]
    match = re.search(re.escape(END) + r" (\d+) PASS, (\d+) FAIL, (\d+) SKIP ==", text)
    if match:
        text = text[:match.end()]
    records, benches, failures = {}, {}, []
    for line in text.splitlines():
        if "DIAG CYCLE_COMPARE (" in line:
            # Assertion prose can contain before=/after= too. Only the fixed
            # header supplies measurements; never let a reason overwrite them.
            header, _, reason = line.partition(" reason=")
            fields = dict(FIELDS.findall(header))
            if {"case", "arm", "phase", "status", "before", "after", "decrease", "preview", "weightLost", "poolKnown", "seed"} <= fields.keys():
                records[(fields["case"], fields["phase"], fields["arm"])] = fields
                if fields["status"] == "FAIL":
                    failures.append(f"{fields['case']} / {fields['arm']} / {fields['phase']}: {reason.rstrip(')')}")
        member = MEMBER.search(line)
        if member:
            case, arm, passed, failed, skipped = member.groups()
            benches[(case, arm)] = (int(passed), int(failed), int(skipped))
        if re.search(r"\bFAIL\b", line) and not MEMBER.search(line) and " END:" not in line and "DIAG CYCLE_COMPARE (" not in line:
            failures.append(line.strip())
    return records, benches, bool(match), failures


def render_report(text):
    records, benches, complete, failures = parse_log(text)
    planned = re.search(re.escape(START) + r" (\d+) benches", text[text.rfind(START):])
    total = int(planned.group(1)) if planned else None
    lines = ["# 적사단지 / 엔진 회전 대조", "",
             "실행 종료 기록: " + ("있음" if complete else "없음 — 진행 중/중단; 미실행을 통과로 보지 않음"), "",
             f"종료 결과가 있는 벤치: {len(benches)}/{total if total is not None else '불명'}. 나머지는 미완료/미실행이다.", "",
             "각 방식은 별도 새 런에서 실행한다. 풀 초기 상태와 난수 경로가 같다는 보장은 없으며, ID 일치나 소비량 차이만으로 우열을 판정하지 않는다.",
             "우선 판정: 방의 풀 출처 / 새 선택지 겹침 / 기존 배열 소실·중복 지급. 정상적인 기존 중복은 보존한다.",
             "관측 추첨에는 외부 모드 콜백도 포함된다. 가중치는 엔진에 등록된 풀만 측정하며 모드의 비공개 Lua 풀은 포함하지 않는다.",
             "방풀 REVIEW 및 새 겹침은 SKIP/검토 대상으로 남는다. 풀 고갈·외부 반환값 교체·정상 중복을 임의로 버그나 PASS로 확정하지 않는다.", "",
             "| 조건 | 엔진 벤치 | 적사단지 벤치 |", "| --- | --- | --- |"]
    cases = sorted({case for case, _ in benches} | {case for case, _, _ in records})
    def bench_cell(case, arm):
        result = benches.get((case, arm))
        if result is None:
            return "미완료/미실행"
        passed, failed, skipped = result
        status = "FAIL" if failed else "SKIP 포함" if skipped else "PASS"
        grant = records.get((case, "grant", arm), {})
        return (f"{status} ({passed}/{failed}/{skipped}); 방풀 {grant.get('source', '미검증')}; "
                f"새 겹침 내부 {grant.get('newSame', '?')} / 다른 받침대 {grant.get('newCross', '?')}")
    for case in cases:
        lines.append(f"| {case} | {bench_cell(case, 'native')} | {bench_cell(case, 'oath')} |")
    lines += ["", "값: `판정; 선택지 전→후; 감소/미감소 콜백; 가중치 감소 합; 런 시드`.",
              "`풀 불명`은 관측 API가 불완전하다는 뜻이다. OBSERVED는 통과 판정이 아니다.", "",
              "| 조건 / 단계 | 엔진 | 적사단지 |", "| --- | --- | --- |"]
    def phase_cell(case, phase, arm):
        row = records.get((case, phase, arm))
        if not row:
            return "기록 없음 (해당 방식에만 있는 단계 또는 미실행)"
        suffix = " / 풀 불명" if row["poolKnown"] != "true" else ""
        if "contract" in row:
            suffix += f" / 주 검사 {row['contract']}, 가격·옵션 {row.get('metadata', 'NA')}"
        return (f"{row['status']}; {row['before']}→{row['after']}; {row['decrease']}/{row['preview']}; "
                f"{row['weightLost']}; {row['seed']}{suffix}")
    for case, phase in sorted({(case, phase) for case, phase, _ in records}):
        lines.append(f"| {case} / {phase} | {phase_cell(case, phase, 'native')} | {phase_cell(case, phase, 'oath')} |")
    if failures:
        lines += ["", "실패 상세:", "", "```text", *dict.fromkeys(failures), "```"]
    lines += ["", "실제 저장·종료·Continue와 시각 표현은 이 자동 비교의 검증 범위에 포함되지 않는다.", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    try:
        report = render_report(args.log.read_text(encoding="utf-8-sig", errors="replace"))
    except (OSError, ValueError) as error:
        parser.error(str(error))
    if args.out:
        args.out.write_text(report, encoding="utf-8")
    else:
        print(report)


if __name__ == "__main__":
    main()
