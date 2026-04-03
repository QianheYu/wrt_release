#!/usr/bin/env python3

import os
import re
import json
import argparse
import glob
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any


class LuCIMenuTool:
    def __init__(self, feed_path: str):
        self.feed_path = Path(feed_path)
        self.packages: Dict[str, Dict[str, Any]] = {}

    def scan_packages(self) -> None:
        """扫描所有luci-app-*包"""
        app_dirs = glob.glob(str(self.feed_path / "luci-app-*"))
        
        for app_dir in app_dirs:
            self._process_package(Path(app_dir))

    def _process_package(self, pkg_path: Path) -> None:
        """处理单个软件包"""
        pkg_name = pkg_path.name
        menu_info = {
            "name": pkg_name,
            "makefile": {},
            "menu_d": {},
            "controller": {},
            "full_path": "",
            "priority": "",
            "source": ""
        }

        makefile_path = pkg_path / "Makefile"
        if makefile_path.exists():
            menu_info["makefile"] = self._parse_makefile(makefile_path)

        menu_info["menu_d"] = self._parse_menu_d(pkg_path)

        controller_path = pkg_path / "luasrc" / "controller"
        if not controller_path.exists():
            controller_path = pkg_path / "controller"
        
        if controller_path.exists():
            menu_info["controller"] = self._parse_controller(controller_path)

        menu_info["full_path"] = self._build_full_path(menu_info)
        menu_info["priority"] = self._get_priority(menu_info)
        menu_info["source"] = self._get_source(menu_info)

        self.packages[pkg_name] = menu_info

    def _parse_makefile(self, makefile_path: Path) -> Dict[str, str]:
        """解析Makefile获取CATEGORY, SUBMENU, PRIORITY"""
        result = {"category": "", "submenu": "", "priority": ""}
        
        try:
            content = makefile_path.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            return result

        pkg_name = makefile_path.parent.name.replace("luci-app-", "luci-app-")

        category_match = re.search(
            r'define\s+Package/\$\(PKG_NAME\)\s*\n\s*CATEGORY\s*:?=\s*(.+)',
            content, re.MULTILINE
        )
        if category_match:
            result["category"] = category_match.group(1).strip()
        else:
            category_match = re.search(
                r'CATEGORY\s*:?=\s*(.+)',
                content
            )
            if category_match:
                result["category"] = category_match.group(1).strip()

        submenu_match = re.search(
            r'define\s+Package/\$\(PKG_NAME\)\s*\n\s*SUBMENU\s*:?=\s*(.+)',
            content, re.MULTILINE
        )
        if submenu_match:
            result["submenu"] = submenu_match.group(1).strip()
        else:
            submenu_match = re.search(
                r'SUBMENU\s*:?=\s*(.+)',
                content
            )
            if submenu_match:
                result["submenu"] = submenu_match.group(1).strip()

        priority_match = re.search(
            r'define\s+Package/\$\(PKG_NAME\)\s*\n\s*PRIORITY\s*:?=\s*(.+)',
            content, re.MULTILINE
        )
        if priority_match:
            result["priority"] = priority_match.group(1).strip()
        else:
            priority_match = re.search(
                r'PRIORITY\s*:?=\s*(.+)',
                content
            )
            if priority_match:
                result["priority"] = priority_match.group(1).strip()

        return result

    def _parse_menu_d(self, pkg_path: Path) -> Dict[str, Any]:
        """解析menu.d目录下的JSON文件"""
        result = {"path": "", "order": "", "entries": []}
        
        possible_paths = [
            pkg_path / "luasrc" / "luci" / "menu.d",
            pkg_path / "menu.d",
            pkg_path / "root" / "usr" / "share" / "luci" / "menu.d"
        ]
        
        all_entries = []
        
        for menu_d_path in possible_paths:
            if not menu_d_path.exists():
                continue
                
            json_files = list(menu_d_path.glob("*.json"))
            
            for json_file in json_files:
                try:
                    with open(json_file, 'r', encoding='utf-8') as f:
                        data = json.load(f)
                        
                    for key, value in data.items():
                        if isinstance(value, dict):
                            entry_info = {
                                "path": key,
                                "title": value.get("title", ""),
                            }
                            if "order" in value and value["order"] is not None:
                                entry_info["order"] = str(value["order"])
                            all_entries.append(entry_info)
                except Exception:
                    continue
        
        if all_entries:
            if not result.get("order"):
                for entry in all_entries:
                    order_val = entry.get("order")
                    if order_val:
                        result["order"] = order_val
                        break
            
            top_level_paths = set()
            for entry in all_entries:
                parts = entry["path"].split("/")
                if len(parts) >= 3:
                    top_level_paths.add("/".join(parts[:3]))
                elif len(parts) == 2:
                    top_level_paths.add(entry["path"])
            
            if top_level_paths:
                result["path"] = "; ".join(sorted(top_level_paths))
                
                for tp in sorted(top_level_paths):
                    existing = next((e for e in all_entries if e.get("path") == tp), None)
                    if not existing:
                        top_entry = {"path": tp, "is_top_level": True}
                        if result.get("order"):
                            top_entry["order"] = result["order"]
                        all_entries.insert(0, top_entry)
                    elif "order" not in existing and result.get("order"):
                        existing["order"] = result["order"]
            else:
                parts = all_entries[0]["path"].split("/")
                result["path"] = "/".join(parts[:2]) if len(parts) >= 2 else all_entries[0]["path"]
            
            result["entries"] = all_entries
                    
        return result

    def _parse_controller(self, controller_path: Path) -> Dict[str, Any]:
        """解析controller目录下的Lua脚本"""
        result = {"path": "", "order": "", "has_variable": False, "entries": []}
        
        lua_files = list(controller_path.rglob("*.lua"))
        
        all_entries = []
        variables = {}
        
        for lua_file in lua_files:
            try:
                content = lua_file.read_text(encoding="utf-8", errors="ignore")
                
                var_matches = re.findall(r'local\s+(\w+)\s*=\s*["\']([^"\']+)["\']', content)
                for var_name, var_value in var_matches:
                    variables[var_name] = var_value
                
                appname_match = re.search(r'appname\s*=\s*["\']([^"\']+)["\']', content)
                if appname_match:
                    variables['appname'] = appname_match.group(1)
                
                node_matches = re.findall(
                    r'page\s*=\s*node\s*\(\s*["\']([^"\']+)["\']\s*,\s*["\']([^"\']+)["\']\s*\)[\s\S]*?page\.order\s*=\s*(\d+)',
                    content
                )
                for node_match in node_matches:
                    entry_info = {
                        "path": node_match[0] + "/" + node_match[1],
                        "order": node_match[2],
                        "is_top_level": True
                    }
                    all_entries.append(entry_info)
                
                lines = content.split('\n')
                for line in lines:
                    line = line.strip()
                    if not ('entry(' in line or 'local ' in line and 'entry(' in line):
                        continue
                    
                    path_match = re.search(r'(?:local\s+\w+\s*=\s*)?entry\s*\(\s*\{([^}]+)\}', line)
                    order_match = re.search(r',\s*(\d+)\s*(?:[,)])', line)
                    
                    if not path_match:
                        continue
                    
                    path_str = path_match.group(1)
                    for var_name, var_value in variables.items():
                        path_str = path_str.replace(var_name, var_value)
                    
                    parts = [p.strip().strip('"').strip("'") for p in path_str.split(',')]
                    full_path = "/".join(parts)
                    
                    entry_info = {"path": full_path}
                    if order_match:
                        entry_info["order"] = order_match.group(1)
                    
                    all_entries.append(entry_info)
                
                if "${" in content or "$(" in content or "local " in content:
                    if "category" in content.lower() or "appname" in content:
                        result["has_variable"] = True
                    
            except Exception as e:
                print(f"Error parsing {lua_file}: {e}")
                continue
        
        if all_entries:
            top_level_paths = set()
            if len(all_entries) > 1:
                for entry in all_entries:
                    parts = entry["path"].split("/")
                    if len(parts) >= 3:
                        top_level_paths.add("/".join(parts[:3]))
                    elif len(parts) == 2:
                        top_level_paths.add(entry["path"])
                
                if not result.get("order"):
                    for entry in all_entries:
                        order_val = entry.get("order")
                        if order_val:
                            result["order"] = order_val
                            break
            
            if top_level_paths:
                result["path"] = "; ".join(sorted(top_level_paths))
                
                for tp in sorted(top_level_paths):
                    existing = next((e for e in all_entries if e.get("path") == tp), None)
                    if not existing:
                        top_entry = {"path": tp, "is_top_level": True}
                        if result.get("order"):
                            top_entry["order"] = result["order"]
                        all_entries.insert(0, top_entry)
                    elif "order" not in existing and result.get("order"):
                        existing["order"] = result["order"]
            else:
                parts = all_entries[0]["path"].split("/")
                result["path"] = "/".join(parts[:2]) if len(parts) >= 2 else all_entries[0]["path"]
            
            result["entries"] = all_entries
                
        return result

    def _build_full_path(self, menu_info: Dict[str, Any]) -> str:
        """构建完整菜单路径"""
        makefile = menu_info.get("makefile", {})
        menu_d = menu_info.get("menu_d", {})
        controller = menu_info.get("controller", {})
        
        if menu_d.get("path"):
            return menu_d["path"]
        
        if controller.get("path"):
            path = controller["path"]
            if controller.get("has_variable"):
                path += " (has variable)"
            return path
        
        category = makefile.get("category", "")
        submenu = makefile.get("submenu", "")
        
        if category and submenu:
            return f"{category}/{submenu}"
        elif category:
            return category
        elif submenu:
            return submenu
            
        return ""

    def _get_priority(self, menu_info: Dict[str, Any]) -> str:
        """获取排序序号"""
        makefile = menu_info.get("makefile", {})
        menu_d = menu_info.get("menu_d", {})
        controller = menu_info.get("controller", {})
        
        if menu_d.get("order"):
            return menu_d["order"]
        
        if controller.get("order"):
            return controller["order"]
            
        return makefile.get("priority", "")

    def _get_source(self, menu_info: Dict[str, Any]) -> str:
        """获取菜单定义来源"""
        if menu_info.get("menu_d", {}).get("path"):
            return "menu.d"
        
        if menu_info.get("controller", {}).get("path"):
            return "controller"
            
        if menu_info.get("makefile", {}).get("category"):
            return "makefile"
            
        return "unknown"

    def export_to_file(self, output_path: str) -> None:
        """导出菜单信息到文件"""
        output_data = {}
        
        for pkg_name, info in self.packages.items():
            if info["source"] == "menu.d":
                menu_d_entries = info["menu_d"].get("entries", [])
                
                export_entry = {
                    "source": info["source"],
                    "makefile_category": info["makefile"].get("category", ""),
                    "makefile_submenu": info["makefile"].get("submenu", ""),
                    "makefile_priority": info["makefile"].get("priority", ""),
                    "entries": menu_d_entries,
                    "has_variable": info["controller"].get("has_variable", False)
                }
            else:
                controller_entries = info["controller"].get("entries", [])
                
                export_entry = {
                    "source": info["source"],
                    "makefile_category": info["makefile"].get("category", ""),
                    "makefile_submenu": info["makefile"].get("submenu", ""),
                    "makefile_priority": info["makefile"].get("priority", ""),
                    "entries": controller_entries,
                    "has_variable": info["controller"].get("has_variable", False)
                }
            
            output_data[pkg_name] = export_entry
        
        with open(output_path, 'w', encoding='utf-8') as f:
            json.dump(output_data, f, ensure_ascii=False, indent=2)
            
        print(f"Exported {len(output_data)} packages to {output_path}")

    def apply_override(self, override_file: str, dry_run: bool = False) -> None:
        """应用覆盖配置"""
        with open(override_file, 'r', encoding='utf-8') as f:
            overrides = json.load(f)
        
        applied = 0
        
        for pkg_name, override in overrides.items():
            pkg_dir = self.feed_path / pkg_name
            
            if not pkg_dir.exists():
                print(f"Package {pkg_name} not found, skipping")
                continue
            
            full_path = override.get("full_path")
            priority = override.get("priority")
            entries = override.get("entries")
            
            if full_path is None and priority is None and entries is None:
                continue
            
            pkg_dir = self.feed_path / pkg_name
            possible_menu_d_paths = [
                pkg_dir / "root" / "usr" / "share" / "luci" / "menu.d",
                pkg_dir / "luasrc" / "luci" / "menu.d",
                pkg_dir / "menu.d"
            ]
            has_menu_d = any(p.exists() for p in possible_menu_d_paths)
            
            possible_controller_paths = [
                pkg_dir / "luasrc" / "controller",
                pkg_dir / "controller"
            ]
            has_controller = any(p.exists() for p in possible_controller_paths)
            
            if has_menu_d:
                full_path = None
                priority = None
            
            if dry_run:
                print(f"[DRY RUN] Would update {pkg_name}:")
                if has_menu_d:
                    print(f"  (has menu.d - only update JSON)")
                elif has_controller:
                    print(f"  (has controller - update Lua)")
                else:
                    print(f"  (no menu.d/controller - update Makefile)")
                if full_path is not None:
                    print(f"  full_path: {full_path}")
                if priority is not None:
                    print(f"  priority: {priority}")
                if entries is not None:
                    print(f"  entries: {entries}")
            else:
                self._apply_override_to_package(pkg_dir, pkg_name, full_path, priority, entries, has_menu_d, has_controller)
                print(f"Updated {pkg_name}")
                
            applied += 1
            
        print(f"Applied {applied} overrides")

    def _apply_override_to_package(self, pkg_dir: Path, pkg_name: str, 
                                     full_path = None, priority = None, 
                                     entries = None, has_menu_d = False,
                                     has_controller = False) -> None:
        """将覆盖配置应用到单个软件包"""
        makefile_path = pkg_dir / "Makefile"
        menu_d_path = None
        
        if has_menu_d:
            possible_menu_d_paths = [
                pkg_dir / "root" / "usr" / "share" / "luci" / "menu.d",
                pkg_dir / "luasrc" / "luci" / "menu.d",
                pkg_dir / "menu.d"
            ]
            for p in possible_menu_d_paths:
                if p.exists():
                    menu_d_path = p
                    break
        
        if entries and menu_d_path:
            json_files = list(menu_d_path.glob("*.json"))
            if json_files:
                try:
                    with open(json_files[0], 'r', encoding='utf-8') as f:
                        menu_data = json.load(f)
                    
                    modified = False
                    
                    for entry in entries:
                        path = entry.get("path", "")
                        new_path = entry.get("new_path", path)
                        title = entry.get("title", "")
                        order = entry.get("order", "")
                        
                        if not path:
                            continue
                        
                        target_path = path
                        if path in menu_data:
                            if new_path != path:
                                entry_data = menu_data.pop(path)
                                menu_data[new_path] = entry_data
                                target_path = new_path
                                modified = True
                            
                            if title and menu_data[target_path].get("title") != title:
                                menu_data[target_path]["title"] = title
                                modified = True
                            if order:
                                old_order = menu_data[target_path].get("order")
                                if old_order is not None:
                                    old_order = int(old_order) if isinstance(old_order, (int, str)) else old_order
                                    if str(old_order) != str(order):
                                        menu_data[target_path]["order"] = int(order)
                                        modified = True
                        else:
                            found_old_path = None
                            for old_path, data in menu_data.items():
                                if data.get("title") == title:
                                    found_old_path = old_path
                                    break
                            
                            if found_old_path:
                                if new_path != found_old_path:
                                    entry_data = menu_data.pop(found_old_path)
                                    menu_data[new_path] = entry_data
                                    target_path = new_path
                                    modified = True
                                    
                                    if title and menu_data[target_path].get("title") != title:
                                        menu_data[target_path]["title"] = title
                                        modified = True
                                    if order:
                                        old_order = menu_data[target_path].get("order")
                                        if old_order is not None:
                                            old_order = int(old_order) if isinstance(old_order, (int, str)) else old_order
                                            if str(old_order) != str(order):
                                                menu_data[target_path]["order"] = int(order)
                                                modified = True
                            elif new_path != path:
                                entry_data = {"title": title} if title else {}
                                if order:
                                    entry_data["order"] = int(order)
                                menu_data[new_path] = entry_data
                                modified = True
                    
                    if modified:
                        with open(json_files[0], 'w', encoding='utf-8') as f:
                            json.dump(menu_data, f, indent=2, ensure_ascii=False)
                        print(f"  Updated menu.d JSON")
                except Exception as e:
                    print(f"  Error updating menu.d: {e}")
        
        if entries is not None and entries and has_controller and not has_menu_d:
            self._update_controller_entries(pkg_dir, entries)
            return
        
        makefile_updated = False
        content = makefile_path.read_text(encoding="utf-8", errors="ignore") if makefile_path.exists() else ""
        is_luci_mk = "include ../../luci.mk" in content
        
        if full_path is not None and ";" not in full_path:
            path_parts = full_path.split("/")
            
            if is_luci_mk:
                if len(path_parts) >= 1:
                    category = path_parts[0]
                    content = self._update_makefile_field(
                        content, "LUCI_CATEGORY", category
                    )
                    makefile_updated = True
                    
                if len(path_parts) >= 2:
                    submenu = "/".join(path_parts[1:])
                    content = self._update_makefile_field(
                        content, "LUCI_SUBMENU", submenu
                    )
            else:
                if len(path_parts) >= 1:
                    category = path_parts[0]
                    content = self._update_makefile_field(
                        content, "CATEGORY", category
                    )
                    makefile_updated = True
                    
                if len(path_parts) >= 2:
                    submenu = "/".join(path_parts[1:])
                    content = self._update_makefile_field(
                        content, "SUBMENU", submenu
                    )
        
        if priority is not None and not (full_path is not None and ";" in full_path):
            if is_luci_mk:
                content = self._update_makefile_field(
                    content, "LUCI_ORDER", priority
                )
            else:
                content = self._update_makefile_field(
                    content, "PRIORITY", priority
                )
            makefile_updated = True
            
        if makefile_updated and content and makefile_path:
            makefile_path.write_text(content, encoding="utf-8")
            print(f"  Updated Makefile")

    def _update_controller_entries(self, pkg_dir: Path, entries: list) -> None:
        """更新controller目录下的Lua脚本中的entry路径和排序"""
        possible_controller_paths = [
            pkg_dir / "luasrc" / "controller",
            pkg_dir / "controller"
        ]
        
        for controller_path in possible_controller_paths:
            if not controller_path.exists():
                continue
            
            lua_files = list(controller_path.rglob("*.lua"))
            
            for lua_file in lua_files:
                try:
                    content = lua_file.read_text(encoding="utf-8", errors="ignore")
                    original_content = content
                    
                    new_order_str = None
                    
                    matched_paths = set()
                    
                    for entry in entries:
                        old_path = entry.get("path", "")
                        new_path = entry.get("new_path") or entry.get("path", "")
                        new_order = entry.get("order", "")
                        
                        if not old_path or not new_path:
                            continue
                        
                        if new_path == old_path and not new_order:
                            continue
                        
                        path_changed = (new_path != old_path)
                        
                        if new_order:
                            new_order_str = str(new_order)
                        
                        old_parts = old_path.split("/")
                        new_parts = new_path.split("/")
                        
                        pattern = r'entry\s*\(\s*\{([^}]+)\}'
                        matches = re.findall(pattern, content)
                        
                        for match in matches:
                            path_str = match
                            parts = [p.strip() for p in path_str.split(',')]
                            
                            if len(parts) == len(old_parts):
                                first_match = parts[0].strip().strip('"').strip("'")
                                if first_match == old_parts[0]:
                                    all_match = True
                                    for i in range(1, len(old_parts)):
                                        part_val = parts[i].strip().strip('"').strip("'")
                                        if part_val != old_parts[i]:
                                            all_match = False
                                            break
                                    
                                    if all_match and path_changed:
                                        path_part = ', '.join([p.strip() for p in parts[:len(old_parts)]])
                                        old_str = '{' + match + '}'
                                        new_str = '{' + path_part + '}'
                                        if old_str != new_str and old_str in content:
                                            content = content.replace(old_str, new_str, 1)
                                            matched_paths.add(old_path)
                    
                    order_needs_update = False
                    if new_order_str:
                        for path in matched_paths:
                            entry_pattern = r'(entry\s*\{[^}]*' + re.escape(path) + r'[^}]*\}(?:,\s*(?:[^,]|,[^,])*){0,2}),\s*(\d+)'
                            match = re.search(entry_pattern, content)
                            if match and match.group(1) != new_order_str:
                                order_needs_update = True
                                break
                        if order_needs_update:
                            content = self._update_lua_order(content, new_order_str, matched_paths)
                    
                    if content != original_content:
                        lua_file.write_text(content, encoding="utf-8")
                        print(f"  Updated {lua_file.name}")
                        
                except Exception as e:
                    print(f"  Error updating {lua_file}: {e} - {type(e)}")

    def _update_lua_order(self, content: str, new_order: str, matched_paths: set = None) -> str:
        """更新Lua中entry的排序参数"""
        if not matched_paths:
            return content
        
        def replace_order(match):
            full_match = match.group(0)
            for path in matched_paths:
                if path in full_match:
                    return full_match.replace(match.group(2), new_order, 1)
            return full_match
        
        entry_pattern = r'(entry\s*\(\s*\{[^}]+\}(?:,\s*(?:[^,]|,[^,])*){0,2}),\s*(\d+)'
        return re.sub(entry_pattern, replace_order, content)

    def _update_makefile_field(self, content: str, field: str, value: str) -> str:
        """更新Makefile中的字段"""
        pattern = rf'^(\s*{field}\s*:=).*$'
        
        if re.search(pattern, content, re.MULTILINE):
            content = re.sub(pattern, rf'\1 {value}', content, flags=re.MULTILINE)
        else:
            if 'include ../../luci.mk' in content:
                content = content.replace(
                    'include ../../luci.mk',
                    f'{field}:= {value}\ninclude ../../luci.mk'
                )
            else:
                define_pattern = r'(define\s+Package/\$\(PKG_NAME\)\s*\n)'
                if re.search(define_pattern, content):
                    content = re.sub(
                        define_pattern,
                        rf'\1\t{field}:= {value}\n',
                        content
                    )
                
        return content


def main():
    parser = argparse.ArgumentParser(
        description="LuCI Menu Path and Priority Tool for OpenWrt packages"
    )
    
    parser.add_argument(
        "--scan", 
        type=str,
        help="Scan luci-app packages from specified feed path"
    )
    
    parser.add_argument(
        "--export",
        action="store_true",
        help="Export menu info to file (use with --scan and --output)"
    )
    
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Apply override configuration from file (use with --scan and --input)"
    )
    
    parser.add_argument(
        "-i", "--input",
        type=str,
        help="Input file path (for --apply)"
    )
    
    parser.add_argument(
        "-o", "--output",
        type=str,
        help="Output file path (for --export)"
    )
    
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without applying (used with --apply)"
    )
    
    args = parser.parse_args()
    
    tool = None
    
    if args.scan:
        tool = LuCIMenuTool(args.scan)
        tool.scan_packages()
    
    if args.export:
        if not tool:
            print("Error: --scan required with --export")
            sys.exit(1)
        if args.output:
            tool.export_to_file(args.output)
        else:
            print(json.dumps({k: v for k, v in tool.packages.items()}, ensure_ascii=False, indent=2))
    
    elif args.apply:
        if not tool:
            print("Error: --scan required with --apply")
            sys.exit(1)
        if not args.input:
            print("Error: --input required with --apply")
            sys.exit(1)
        tool.apply_override(args.input, dry_run=args.dry_run)
    
    elif tool:
        for pkg_name, info in tool.packages.items():
            print(f"{pkg_name}: {info['full_path']} (priority: {info['priority']}, source: {info['source']})")
    else:
        parser.print_help()


if __name__ == "__main__":
    main()