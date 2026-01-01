#!/bin/bash

# 脚本名称: fix_menu_category.sh
# 功能: 根据清单文件修改 LuCI 应用程序的菜单分类（中间层级）
# 用法: ./fix_menu_category.sh [-f list_file] [feeds_dir]

LIST_FILE="menu_category_list.txt"
FEEDS_DIR="feeds"

# 解析参数
while getopts ":f:" opt; do
  case $opt in
    f)
      LIST_FILE="$OPTARG"
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

if [ ! -f "$LIST_FILE" ]; then
    echo "错误: 清单文件 $LIST_FILE 未找到!"
    exit 1
fi

if [ ! -d "$FEEDS_DIR" ]; then
    echo "警告: Feeds 目录 $FEEDS_DIR 未找到。"
fi

echo "开始处理菜单分类..."

# 读取清单文件
grep -vE '^\s*#|^\s*$' "$LIST_FILE" | while read -r pkg_name target_category; do
    if [ -z "$pkg_name" ]; then
        continue
    fi

    # 去除 target_category 可能存在的行尾注释 (简单处理 #)
    target_category=${target_category%%#*}
    # 去除前后空格
    target_category=$(echo "$target_category" | xargs)

    action_desc="修改分类为 '$target_category'"
    if [ -z "$target_category" ]; then
        action_desc="删除中间分类"
    fi

    echo "正在检查软件包: $pkg_name ($action_desc)"

    # 查找软件包路径
    pkg_path=$(find "$FEEDS_DIR" -type d -name "$pkg_name" 2>/dev/null | head -n 1)

    if [ -z "$pkg_path" ]; then
        echo "  -> 未找到软件包目录: $pkg_name"
        continue
    fi

    # --- 处理 Lua Controller 文件 ---
    lua_files=$(find "$pkg_path" -path "*/luasrc/controller/*.lua")
    
    for lua_file in $lua_files; do
        [ -f "$lua_file" ] || continue

        # 仅处理三级结构: entry({"admin", "CAT", "NAME"
        # 1. 双引号
        if grep -q 'entry({"admin", "[^"]*", "[^"]*"' "$lua_file"; then
            current_cat=$(sed -n 's/.*entry({"admin", "\([^"]*\)", "[^"]*".*/\1/p' "$lua_file" | head -n 1)
            
            if [ -n "$current_cat" ]; then
                if [ -n "$target_category" ] && [ "$current_cat" != "$target_category" ]; then
                    echo "  -> 修改 Lua (双引号): $lua_file ($current_cat -> $target_category)"
                    sed -i "s/entry({\"admin\", \"$current_cat\",/entry({\"admin\", \"$target_category\",/g" "$lua_file"
                elif [ -z "$target_category" ]; then
                    echo "  -> 修改 Lua (双引号): $lua_file (删除 $current_cat)"
                    # 删除 "CAT", 注意逗号和空格
                    sed -i "s/entry({\"admin\", \"$current_cat\",[[:space:]]*/entry({\"admin\", /g" "$lua_file"
                fi
            fi
        # 处理二级结构: entry({"admin", "NAME" -> 插入分类
        elif [ -n "$target_category" ] && grep -q 'entry({"admin", "[^"]*", ' "$lua_file"; then
             # 确保不是三级结构 (上面已经匹配过了，但为了保险)
             # 这里的正则匹配 entry({"admin", "NAME", ...
             echo "  -> 插入分类 Lua (双引号): $lua_file (插入 $target_category)"
             sed -i "s/entry({\"admin\", /entry({\"admin\", \"$target_category\", /g" "$lua_file"
        fi

        # 2. 单引号
        if grep -q "entry({'admin', '[^']*', '[^']*'" "$lua_file"; then
            current_cat=$(sed -n "s/.*entry({'admin', '\([^']*\)', '[^']*'.*/\1/p" "$lua_file" | head -n 1)
            
            if [ -n "$current_cat" ]; then
                if [ -n "$target_category" ] && [ "$current_cat" != "$target_category" ]; then
                    echo "  -> 修改 Lua (单引号): $lua_file ($current_cat -> $target_category)"
                    sed -i "s/entry({'admin', '$current_cat',/entry({'admin', '$target_category',/g" "$lua_file"
                elif [ -z "$target_category" ]; then
                    echo "  -> 修改 Lua (单引号): $lua_file (删除 $current_cat)"
                    sed -i "s/entry({'admin', '$current_cat',[[:space:]]*/entry({'admin', /g" "$lua_file"
                fi
            fi
        # 处理二级结构: entry({'admin', 'NAME' -> 插入分类
        elif [ -n "$target_category" ] && grep -q "entry({'admin', '[^']*', " "$lua_file"; then
             echo "  -> 插入分类 Lua (单引号): $lua_file (插入 $target_category)"
             sed -i "s/entry({'admin', /entry({'admin', '$target_category', /g" "$lua_file"
        fi
    done

    # --- 处理 JSON 菜单定义 ---
    # 查找 menu.d 和 acl.d
    json_files=$(find "$pkg_path" -type f \( -path "*/root/usr/share/luci/menu.d/*.json" -o -path "*/root/usr/share/rpcd/acl.d/*.json" \))
    
    for json_file in $json_files; do
        [ -f "$json_file" ] || continue
        
        # 仅处理三级结构: "admin/CAT/NAME"
        if grep -q "\"admin/[^/]*/[^/]*" "$json_file"; then
             current_cat=$(sed -n 's/.*"admin\/\([^/]*\)\/[^/]*".*/\1/p' "$json_file" | head -n 1)
             
             if [ -n "$current_cat" ]; then
                 if [ -n "$target_category" ] && [ "$current_cat" != "$target_category" ]; then
                     echo "  -> 修改 JSON: $json_file ($current_cat -> $target_category)"
                     sed -i "s/\"admin\/$current_cat\//\"admin\/$target_category\//g" "$json_file"
                 elif [ -z "$target_category" ]; then
                     echo "  -> 修改 JSON: $json_file (删除 $current_cat)"
                     # 删除 cat/
                     sed -i "s/\"admin\/$current_cat\//\"admin\//g" "$json_file"
                 fi
             fi
        # 处理二级结构: "admin/NAME" -> 插入分类
        elif [ -n "$target_category" ] && grep -q "\"admin/[^/]*\"" "$json_file"; then
             # 确保匹配的是 admin/name 且没有后续的 /
             # 这里的 grep 比较宽泛，sed 替换时要精确
             echo "  -> 插入分类 JSON: $json_file (插入 $target_category)"
             sed -i "s/\"admin\//\"admin\/$target_category\//g" "$json_file"
        fi
    done

done

echo "处理完成。"
