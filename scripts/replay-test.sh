#!/bin/bash
# 离线回放测试 — 用历史手部轨迹测试当前算法
# 用法: ./scripts/replay-test.sh <trace文件> [版本名]
# 原理: 提取hand位置 → 喂给CursorController → 输出新cursor → 跑23项指标

TRACE="${1:-Docs/logs/v0.5.0-silky-trace.tsv}"
LABEL="${2:-replay}"

if [ ! -f "$TRACE" ]; then
    echo "用法: $0 <trace.tsv文件> [标签]"
    echo "可用trace:"
    ls Docs/logs/*-trace.tsv 2>/dev/null
    exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  离线回放测试"
echo "  输入轨迹: $TRACE ($(wc -l < "$TRACE") 帧)"
echo "  当前算法: $(cat VERSION)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 提取原始指标作为基准
ORIG_META="$(dirname "$TRACE")/$(basename "$TRACE" -trace.tsv)-meta.yaml"
echo "  基准元数据: $ORIG_META"

# 构建回放测试程序
echo ""
echo "=== 构建回放测试 ==="
cd "$(git rev-parse --show-toplevel)"

# 用 Swift 脚本做回放
cat > /tmp/replay_runner.swift << 'SWIFTEOF'
import Foundation
import CoreGraphics

// 解析 CURSOR-ABS 格式的行
func parseLine(_ line: String) -> (hand: CGPoint, filter: CGPoint, target: CGPoint, cursor: CGPoint)? {
    // hand=(0.284,0.373) filter=(0.284,0.373) target=(686,518) cursor=(0,0)
    guard let hRange = line.range(of: "hand=\\("),
          let hEnd = line[hRange.upperBound...].range(of: "\\)") else { return nil }
    let hStr = line[hRange.upperBound..<hEnd.lowerBound]
    let hParts = hStr.split(separator: ",")
    guard hParts.count == 2, let hx = Double(hParts[0]), let hy = Double(hParts[1]) else { return nil }

    let rest1 = line[hEnd.upperBound...]
    guard let fRange = rest1.range(of: "filter=\\("),
          let fEnd = rest1[fRange.upperBound...].range(of: "\\)") else { return nil }
    let fStr = rest1[fRange.upperBound..<fEnd.lowerBound]

    let rest2 = rest1[fEnd.upperBound...]
    guard let tRange = rest2.range(of: "target=\\("),
          let tEnd = rest2[tRange.upperBound...].range(of: "\\)") else { return nil }
    let tStr = rest2[tRange.upperBound..<tEnd.lowerBound]
    let tParts = tStr.split(separator: ",")
    guard tParts.count == 2, let tx = Double(tParts[0]), let ty = Double(tParts[1]) else { return nil }

    return (CGPoint(x: hx, y: hy), CGPoint(x: 0, y: 0), CGPoint(x: tx, y: ty), CGPoint(x: 0, y: 0))
}

let tracePath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]

guard let content = try? String(contentsOfFile: tracePath, encoding: .utf8) else {
    print("无法读取: \(tracePath)")
    exit(1)
}

let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

// 模拟 CursorController 的核心映射逻辑
let screenW: CGFloat = 1920
let screenH: CGFloat = 1080
let screenCX = screenW / 2
let screenCY = screenH / 2
let gain: CGFloat = 2.0
let origin = CGPoint(x: 0.48, y: 0.37)
let lerpFactor: CGFloat = 0.65

var currentPos = CGPoint(x: screenCX, y: screenCY)
var targetPos = CGPoint.zero
var output = ""

for line in lines {
    guard let parsed = parseLine(line) else { continue }
    let hand = parsed.hand

    // 绝对位置映射
    let offsetX = hand.x - origin.x
    let offsetY = hand.y - origin.y
    let cursorX = screenCX - offsetX * screenW * gain
    let cursorY = screenCY + offsetY * screenH * gain

    targetPos = CGPoint(
        x: max(0, min(cursorX, screenW)),
        y: max(0, min(cursorY, screenH))
    )

    // 120Hz lerp 模拟
    let newX = currentPos.x + (targetPos.x - currentPos.x) * lerpFactor
    let newY = currentPos.y + (targetPos.y - currentPos.y) * lerpFactor
    currentPos = CGPoint(x: newX, y: newY)

    // 输出 CURSOR-ABS 格式
    output += "hand=(\(String(format:"%.3f",hand.x)),\(String(format:"%.3f",hand.y))) filter=(\(String(format:"%.3f",hand.x)),\(String(format:"%.3f",hand.y))) target=(\(String(format:"%.0f",targetPos.x)),\(String(format:"%.0f",targetPos.y))) cursor=(\(String(format:"%.0f",currentPos.x)),\(String(format:"%.0f",currentPos.y)))\n"
}

try? output.write(toFile: outputPath, atomically: true, encoding: .utf8)
print("回放完成: \(lines.count) 行 → \(output.components(separatedBy: "\n").filter{!$0.isEmpty}.count) 帧输出")
SWIFTEOF

# 编译并运行回放
swiftc /tmp/replay_runner.swift -o /tmp/replay_runner 2>/dev/null
/tmp/replay_runner "$TRACE" /tmp/replay_output.log

echo ""
echo "=== 运行23项指标分析 ==="
./scripts/analyze-cursor-log.sh /tmp/replay_output.log

echo ""
echo "=== 原始 vs 回放对比 ==="
echo "原始轨迹: $TRACE ($(wc -l < "$TRACE") 帧)"
echo "回放输出: /tmp/replay_output.log"
echo ""
echo "💡 下一步：把回放引擎改成调用真实的 CursorController.updateWithAbsolutePosition()"
echo "   就可以用 Swift 测试框架自动跑了"
