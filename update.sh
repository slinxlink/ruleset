#!/bin/bash
# ================================================================
# update.sh — SLINX 规则集自动更新（由 GitHub Actions 定时执行）
# 用法: ./update.sh
# 依赖: curl unzip zip python3 sing-box（环境变量 SINGBOX 可指定路径）
# ================================================================
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 路径配置 ──────────────────────────────────────────────────
SINGBOX="${SINGBOX:-sing-box}"
SOURCE_DIR="$SCRIPT_DIR/source"
GEO_DIR="$SCRIPT_DIR/geo"
RULESET_DIR="$SCRIPT_DIR/ruleset"
DIST_DIR="$SCRIPT_DIR/dist"
LOG_FILE="$SCRIPT_DIR/report.log"

GEOIP_URL="https://github.com/SagerNet/sing-geoip/archive/refs/heads/rule-set.zip"
GEOSITE_URL="https://github.com/SagerNet/sing-geosite/archive/refs/heads/rule-set.zip"

# ── 规则分组定义 ──────────────────────────────────────────────
GROUP_NAMES="ai media social game apple google microsoft"

group_tags() {
    case "$1" in
        ai)        echo "anthropic apple-intelligence github github-copilot google-gemini openai perplexity" ;;
        media)     echo "apple-tvplus dazn disney hbo hulu iqiyi@!cn netflix primevideo spotify tiktok tvb youtube" ;;
        social)    echo "discord facebook instagram line telegram threads twitter whatsapp x" ;;
        game)      echo "ea epicgames nintendo playstation steam xbox" ;;
        apple)     echo "apple icloud icloudprivaterelay itunes" ;;
        google)    echo "google" ;;
        microsoft) echo "bing microsoft onedrive" ;;
        *)         echo "" ;;
    esac
}

site_dest_name() {
    case "$1" in
        "category-ads-all.srs")   echo "ads.srs" ;;
        "category-ir.srs")        echo "ir.srs" ;;
        "category-ru.srs")        echo "ru.srs" ;;
        "apple-intelligence.srs") echo "apple-intelligence.srs" ;;
        "apple-tvplus.srs")       echo "apple-tvplus.srs" ;;
        *)                        echo "" ;;
    esac
}

MISSING=0

# ── 1. 下载 ───────────────────────────────────────────────────

fetch_source() {
    local name="$1" url="$2" prefix="$3" dest="$4"
    local tmp="$SOURCE_DIR/tmp_$name"

    rm -rf "$tmp"
    mkdir -p "$tmp"

    if ! curl -fsSL --retry 3 --retry-delay 5 "$url" -o "$tmp/$name.zip"; then
        echo "  ✗ $name  下载失败"
        return 1
    fi
    if ! unzip -q "$tmp/$name.zip" -d "$tmp/extracted"; then
        echo "  ✗ $name  解压失败"
        return 1
    fi

    rm -rf "$dest"
    mkdir -p "$dest"
    find "$tmp/extracted" -name "${prefix}-*.srs" | while read -r f; do
        cp "$f" "$dest/$(basename "$f" | sed "s/^${prefix}-//")"
    done

    rm -rf "$tmp"

    if [ -z "$(ls "$dest" 2>/dev/null)" ]; then
        echo "  ✗ $name  源文件为空"
        return 1
    fi
    echo "  ✓ $name  源文件 ok"
}

stage_download() {
    echo "[1/3] 下载"
    mkdir -p "$SOURCE_DIR"

    local failed=0
    fetch_source geoip   "$GEOIP_URL"   geoip   "$SOURCE_DIR/ip"   || failed=1
    fetch_source geosite "$GEOSITE_URL" geosite "$SOURCE_DIR/site" || failed=1

    if [ "$failed" -ne 0 ]; then
        echo ""
        echo "失败：缺少源文件，未更新，未发布"
        return 1
    fi
}

# ── 2. 整理 ───────────────────────────────────────────────────

merge_json() {
    local out_path="$1"
    shift

    python3 - "$out_path" "$@" << 'PYEOF'
import json
import sys

out_path = sys.argv[1]
json_files = sys.argv[2:]

list_fields = ["domain", "domain_suffix", "domain_keyword", "domain_regex"]

def as_list(v):
    if v is None:
        return []
    if isinstance(v, str):
        return [v]
    return list(v)

combined = {f: [] for f in list_fields}
seen = {f: set() for f in list_fields}

for path in json_files:
    with open(path) as f:
        data = json.load(f)
    for rule in data.get("rules", []):
        for field in list_fields:
            for v in as_list(rule.get(field)):
                if v not in seen[field]:
                    seen[field].add(v)
                    combined[field].append(v)

rule_obj = {f: combined[f] for f in list_fields if combined[f]}
out = {"version": 1, "rules": [rule_obj]}

with open(out_path, "w") as f:
    json.dump(out, f, ensure_ascii=False)
PYEOF
}

process_ip() {
    rm -rf "$GEO_DIR/ip"
    mkdir -p "$GEO_DIR/ip"
    cp "$SOURCE_DIR/ip/"*.srs "$GEO_DIR/ip/"
    printf "  %-8s%-18s✓ %s 个\n" "ip" "全部保留" "$(ls "$GEO_DIR/ip" | wc -l | tr -d ' ')"
}

process_site() {
    rm -rf "$GEO_DIR/site"
    mkdir -p "$GEO_DIR/site"

    for f in "$SOURCE_DIR/site/"*.srs; do
        [ -f "$f" ] || continue
        local base dest
        base=$(basename "$f")
        dest=$(site_dest_name "$base")

        if [ -n "$dest" ]; then
            cp "$f" "$GEO_DIR/site/$dest"
        elif [[ "$base" != *-* ]] && [[ "$base" != *@* ]]; then
            cp "$f" "$GEO_DIR/site/$base"
        fi
    done

    printf "  %-8s%-18s✓ %s 个\n" "site" "精简后保留" "$(ls "$GEO_DIR/site" | wc -l | tr -d ' ')"
}

process_ruleset() {
    local tmp="$SCRIPT_DIR/tmp_ruleset"
    rm -rf "$tmp"
    mkdir -p "$tmp" "$RULESET_DIR"

    echo ""
    echo "  ruleset 合并"

    local group tag
    for group in $GROUP_NAMES; do
        local total=0 json_files=() missing=()

        for tag in $(group_tags "$group"); do
            total=$((total + 1))
            local src="$SOURCE_DIR/site/${tag}.srs"
            local json="$tmp/${group}_${tag//[@!\/]/_}.json"
            if [ -f "$src" ] && "$SINGBOX" rule-set decompile "$src" -o "$json" >/dev/null 2>&1; then
                json_files+=("$json")
            else
                missing+=("$tag")
            fi
        done

        local ok=${#json_files[@]}
        local merged="$tmp/${group}_merged.json"

        if [ "$ok" -gt 0 ] \
            && merge_json "$merged" "${json_files[@]}" 2>/dev/null \
            && "$SINGBOX" rule-set compile "$merged" -o "$RULESET_DIR/${group}.srs" >/dev/null 2>&1; then
            if [ ${#missing[@]} -gt 0 ]; then
                MISSING=$((MISSING + ${#missing[@]}))
                printf "  ✓ %-11s %s/%s   缺失: %s\n" "$group" "$ok" "$total" "${missing[*]}"
            else
                printf "  ✓ %-11s %s/%s\n" "$group" "$ok" "$total"
            fi
        else
            MISSING=$((MISSING + ${#missing[@]} + 1))
            printf "  ✗ %-11s %s/%s   缺失: %s（跳过，保留上次文件）\n" "$group" "0" "$total" "${missing[*]}"
        fi
    done

    rm -rf "$tmp"
}

stage_process() {
    echo "[2/3] 整理"
    process_ip
    process_site
    process_ruleset
}

# ── 3. 打包 ───────────────────────────────────────────────────

pack_dir() {
    local base="$1" name="$2"
    (cd "$base" && zip -qr "$DIST_DIR/$name.zip" "$name" -x "*.DS_Store")
    printf "  ✓ %-12s%s\n" "$name.zip" "$(du -h "$DIST_DIR/$name.zip" | cut -f1)"
}

stage_pack() {
    echo "[3/3] 打包"
    rm -rf "$DIST_DIR"
    mkdir -p "$DIST_DIR"

    pack_dir "$GEO_DIR" ip
    pack_dir "$GEO_DIR" site
    pack_dir "$SCRIPT_DIR" ruleset
}

# ── 主流程 ────────────────────────────────────────────────────

main() {
    echo "SLINX Ruleset 更新  $(TZ=Asia/Shanghai date +%Y-%m-%d)"
    echo ""

    stage_download || return 1
    echo ""
    stage_process
    echo ""
    stage_pack
    echo ""

    if [ "$MISSING" -eq 0 ]; then
        echo "完成：全部成功"
    else
        echo "完成：有 $MISSING 项缺失，其余成功"
    fi
}

main 2>&1 | tee "$LOG_FILE"
exit "${PIPESTATUS[0]}"
