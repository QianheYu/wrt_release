#!/bin/bash

# 脚本名称: export_menu_order.sh
# 功能: 导出所有软件包在菜单中的排序序号
# 用法: ./export_menu_order.sh [-o output_file] [feeds_dir]

OUTPUT_FILE="menu_order_list.txt"
FEEDS_DIR="feeds"

# 解析参数
while getopts ":o:" opt; do
  case $opt in
    o)
      OUTPUT_FILE="$OPTARG"
      ;;
    \?)
      echo "无效选项: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "选项 -$OPTARG 需要参数." >&2
      exit 1
      ;;
  esac
done

shift $((OPTIND-1))

if [ -n "$1" ]; then
    FEEDS_DIR="$1"
fi

if [ ! -d "$FEEDS_DIR" ]; then
    echo "错误: Feeds 目录 $FEEDS_DIR 未找到。"
    exit 1
fi

echo "正在扫描 $FEEDS_DIR ..."
echo "# 自动生成的菜单排序清单" > "$OUTPUT_FILE"
echo "# 生成时间: $(date)" >> "$OUTPUT_FILE"
echo "# 格式: <package_name> <order>" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

TMP_FILE="${OUTPUT_FILE}.tmp"
rm -f "$TMP_FILE"

# 函数：处理提取到的信息
process_entry() {
    local pkg_name="$1"
    local path="$2"
    local order="$3"

    # 仅处理以 admin 开头的路径
    if [[ "$path" != admin/* ]]; then
        return
    fi

    if [ -n "$pkg_name" ] && [ -n "$order" ]; then
        echo "$pkg_name $order" >> "$TMP_FILE"
    fi
}

# 1. 扫描 Lua Controller
echo "扫描 Lua Controllers..."
find "$FEEDS_DIR" -type f -path "*/luasrc/controller/*.lua" | while read -r lua_file; do
    # 提取包名
    pkg_name=$(echo "$lua_file" | awk -F'/luasrc/' '{print $1}' | awk -F'/' '{print $NF}')
    
    # 提取 entry
    # 使用 grep 提取所有 entry 行，然后逐行处理
    grep -oP 'entry\(\s*\{[^}]+\}[^)]+\)' "$lua_file" | while read -r line; do
        # 提取路径
        # 匹配 {"admin", "foo", "bar"} 或 {'admin', 'foo', 'bar'}
        path=$(echo "$line" | grep -oP '\{["'\'']admin["'\''][^}]+\}' | sed "s/['\"]//g; s/{//; s/}//; s/, /\//g")
        
        # 提取 order
        # 匹配行尾的数字
        order=$(echo "$line" | grep -oP ',\s*\d+\s*\)' | grep -oP '\d+')
        
        if [ -n "$path" ] && [ -n "$order" ]; then
            process_entry "$pkg_name" "$path" "$order"
        fi
    done
done

# 2. 扫描 JSON 菜单定义
echo "扫描 JSON Menu Definitions..."
find "$FEEDS_DIR" -type f \( -path "*/root/usr/share/luci/menu.d/*.json" -o -path "*/root/usr/share/rpcd/acl.d/*.json" \) | while read -r json_file; do
    pkg_name=$(echo "$json_file" | awk -F'/root/' '{print $1}' | awk -F'/' '{print $NF}')
    
    # JSON 比较难用 grep 处理多行，这里假设简单格式
    # 查找 "admin/foo/bar": { ... "order": 10 ... }
    # 这种简单的 grep 只能处理单行或者紧邻的情况，或者我们只提取文件名中的信息？
    # 不，menu.d json 文件通常包含路径作为 key。
    
    # 尝试一种简单的策略：读取整个文件，用 perl 或 python 处理？
    # 为了保持 shell 脚本依赖最小化，我们尝试用 awk 处理
    
    awk -v pkg="$pkg_name" '
    /"admin\/[^"]+"/ {
        # 提取路径
        match($0, /"admin\/[^"]+"/)
        path = substr($0, RSTART+1, RLENGTH-2)
        
        # 重置 order
        order = ""
    }
    /"order":/ {
        # 提取 order
        match($0, /[0-9]+/)
        order = substr($0, RSTART, RLENGTH)
        
        if (path != "" && order != "") {
            print pkg, path, order
            # 清除 path 以避免重复匹配 (假设一个 block 一个 path)
            path = ""
        }
    }
    ' "$json_file" | while read -r p_pkg p_path p_order; do
        process_entry "$p_pkg" "$p_path" "$p_order"
    done
done

# 排序并去重
if [ -f "$TMP_FILE" ]; then
    # 按包名排序
    sort -u "$TMP_FILE" | sort -k1,1 >> "$OUTPUT_FILE"
    rm "$TMP_FILE"
    echo "导出完成。结果已保存至 $OUTPUT_FILE"
else
    echo "未找到任何包含排序信息的菜单项。"
fi
