#!/bin/bash

# 脚本名称: extract_menu_path.sh
# 功能: 扫描 feeds 目录，提取所有 LuCI 应用程序的菜单路径，并生成清单文件
# 用法: ./extract_menu_path.sh [-o output_file] [feeds_dir]

OUTPUT_FILE="extracted_menu_paths.txt"
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
echo "# 自动生成的菜单路径清单" > "$OUTPUT_FILE"
echo "# 生成时间: $(date)" >> "$OUTPUT_FILE"
echo "# 格式: <package_name> <menu_path> [order]" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# 查找所有可能的 LuCI app 目录
# 假设目录名以 luci-app- 开头，或者在 luci/applications 下
# 这里简单起见，查找所有包含 controller 或 menu.d 的目录，然后向上推导包名

# 使用关联数组去重 (Bash 4.0+)
declare -A pkg_paths

# 1. 扫描 Lua Controller
echo "扫描 Lua Controllers..."
find "$FEEDS_DIR" -type f -path "*/luasrc/controller/*.lua" | while read -r lua_file; do
    # 提取包名 (假设结构为 .../package_name/luasrc/...)
    # 使用 awk 提取 luasrc 前面的一级目录名
    pkg_name=$(echo "$lua_file" | awk -F'/luasrc/' '{print $1}' | awk -F'/' '{print $NF}')
    
    # 提取菜单路径和 order
    # 查找 entry({"admin", ...
    # 提取 admin/.../... 直到结束引号
    
    # 双引号
    # 尝试提取 order: entry(..., order)
    # 匹配行
    line_dq=$(grep -oP 'entry\(\{"admin", "[^"]+", "[^"]+"[^)]*' "$lua_file" | head -n 1)
    if [ -n "$line_dq" ]; then
        path_dq=$(echo "$line_dq" | grep -oP 'entry\(\{"admin", "[^"]+", "[^"]+"' | sed 's/entry({"//; s/", "/\//g; s/"//g')
        # 提取最后一个数字作为 order
        order=$(echo "$line_dq" | grep -oP ',\s*\d+\s*\)$' | grep -oP '\d+')
        echo "$pkg_name $path_dq $order" >> "$OUTPUT_FILE.tmp"
        continue
    fi
    
    # 单引号
    line_sq=$(grep -oP "entry\({'admin', '[^']+', '[^']+'[^)]*" "$lua_file" | head -n 1)
    if [ -n "$line_sq" ]; then
        path_sq=$(echo "$line_sq" | grep -oP "entry\({'admin', '[^']+', '[^']+" | sed "s/entry({'//; s/', '/\//g; s/'//g")
        order=$(echo "$line_sq" | grep -oP ',\s*\d+\s*\)$' | grep -oP '\d+')
        echo "$pkg_name $path_sq $order" >> "$OUTPUT_FILE.tmp"
        continue
    fi
    
    # 二级菜单 (admin, name)
    line_dq_2=$(grep -oP 'entry\(\{"admin", "[^"]+"[^)]*' "$lua_file" | head -n 1)
    if [ -n "$line_dq_2" ]; then
        path_dq_2=$(echo "$line_dq_2" | grep -oP 'entry\(\{"admin", "[^"]+"' | sed 's/entry({"//; s/", "/\//g; s/"//g')
        order=$(echo "$line_dq_2" | grep -oP ',\s*\d+\s*\)$' | grep -oP '\d+')
        echo "$pkg_name $path_dq_2 $order" >> "$OUTPUT_FILE.tmp"
        continue
    fi
    
    line_sq_2=$(grep -oP "entry\({'admin', '[^']+'[^)]*" "$lua_file" | head -n 1)
    if [ -n "$line_sq_2" ]; then
        path_sq_2=$(echo "$line_sq_2" | grep -oP "entry\({'admin', '[^']+" | sed "s/entry({'//; s/', '/\//g; s/'//g")
        order=$(echo "$line_sq_2" | grep -oP ',\s*\d+\s*\)$' | grep -oP '\d+')
        echo "$pkg_name $path_sq_2 $order" >> "$OUTPUT_FILE.tmp"
        continue
    fi

done

# 2. 扫描 JSON 菜单定义
echo "扫描 JSON Menu Definitions..."
find "$FEEDS_DIR" -type f \( -path "*/root/usr/share/luci/menu.d/*.json" -o -path "*/root/usr/share/rpcd/acl.d/*.json" \) | while read -r json_file; do
    # 提取包名 (假设结构为 .../package_name/root/...)
    pkg_name=$(echo "$json_file" | awk -F'/root/' '{print $1}' | awk -F'/' '{print $NF}')
    
    # 提取菜单路径
    # 查找 "admin/..."
    # 排除 acl.d 中可能出现的纯权限定义，只关注菜单结构
    # 通常 menu.d 中的 key 就是路径
    
    # 提取包含 admin/ 的 key
    # 格式 "admin/foo/bar": {
    path_json=$(grep -oP '"admin/[^"]+"' "$json_file" | head -n 1 | sed 's/"//g')
    
    if [ -n "$path_json" ]; then
        # 尝试提取 order
        # 假设 order 在同一文件中，且在 path_json 之后
        # 这是一个简单的 grep，可能不准确，因为 json 可能是多行的
        # 我们尝试查找 "order": 10 这样的结构
        order=$(grep -oP '"order":\s*\d+' "$json_file" | head -n 1 | grep -oP '\d+')
        echo "$pkg_name $path_json $order" >> "$OUTPUT_FILE.tmp"
    fi
done

# 排序并去重，写入最终文件
if [ -f "$OUTPUT_FILE.tmp" ]; then
    sort -u "$OUTPUT_FILE.tmp" >> "$OUTPUT_FILE"
    rm "$OUTPUT_FILE.tmp"
    echo "提取完成。结果已保存至 $OUTPUT_FILE"
else
    echo "未找到任何菜单路径。"
fi
