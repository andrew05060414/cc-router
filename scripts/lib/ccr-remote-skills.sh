# ccr remote 技能包管理

ccr_remote_skills_root() {
  printf '%s\n' "${HOME}/.claude/skills"
}

ccr_remote_skills_list() {
  local root
  root="$(ccr_remote_skills_root)"
  if [[ ! -d "$root" ]]; then
    return 0
  fi
  find "$root" -maxdepth 1 -mindepth 1 \( -type d -o -type l \) | while read -r skill; do
    basename "$skill"
  done
}

ccr_remote_skills_list_bundled() {
  local repo_root
  # 尝试找到 cc-router 仓库根目录
  for candidate in "${HOME}/Code/Andrew-tech/cc-router" "${HOME}/Projects/cc-router" "${HOME}/cc-router"; do
    if [[ -d "$candidate/skills" ]]; then
      repo_root="$candidate"
      break
    fi
  done

  if [[ -z "${repo_root:-}" ]]; then
    return 0
  fi

  find "$repo_root/skills" -maxdepth 1 -mindepth 1 -type d | while read -r skill; do
    printf 'bundled:%s\n' "$(basename "$skill")"
  done
}

ccr_remote_skills_list_projects() {
  # 扫描常见项目目录下的 .claude/skills
  local search_roots=(
    "${HOME}/Code"
    "${HOME}/Projects"
    "${HOME}/Workspace"
  )

  for root in "${search_roots[@]}"; do
    if [[ -d "$root" ]]; then
      find "$root" -maxdepth 3 -type d -path "*/.claude/skills" 2>/dev/null | while read -r skills_dir; do
        printf '%s\n' "$skills_dir"
      done
    fi
  done
}

ccr_remote_skills_select() {
  local pack_dir
  pack_dir="$(ccr_remote_pack_dir)"
  mkdir -p "$pack_dir"

  echo "[cc-remote] 选择要同步的技能包"
  echo ""
  echo "本地全局技能:"
  local global_skills=()
  while IFS= read -r skill; do
    [[ -n "$skill" ]] && global_skills+=("$skill")
  done < <(ccr_remote_skills_list)
  if ((${#global_skills[@]} == 0)); then
    echo "  (无)"
  else
    local i
    for i in "${!global_skills[@]}"; do
      printf '  [%d] %s\n' "$((i+1))" "${global_skills[$i]}"
    done
  fi

  echo ""
  echo "cc-router 自带技能:"
  local bundled_skills=()
  while IFS= read -r skill; do
    [[ -n "$skill" ]] && bundled_skills+=("$skill")
  done < <(ccr_remote_skills_list_bundled)
  if ((${#bundled_skills[@]} == 0)); then
    echo "  (无)"
  else
    for i in "${!bundled_skills[@]}"; do
      printf '  [%d] %s\n' "$((i+1+${#global_skills[@]}))" "${bundled_skills[$i]}"
    done
  fi

  echo ""
  echo "项目技能目录:"
  local project_skills_dirs=()
  while IFS= read -r skill_dir; do
    [[ -n "$skill_dir" ]] && project_skills_dirs+=("$skill_dir")
  done < <(ccr_remote_skills_list_projects)
  local project_offset=$(( ${#global_skills[@]} + ${#bundled_skills[@]} ))
  if ((${#project_skills_dirs[@]} == 0)); then
    echo "  (未找到)"
  else
    for i in "${!project_skills_dirs[@]}"; do
      printf '  [%d] %s\n' "$((i+1+project_offset))" "${project_skills_dirs[$i]}"
    done
  fi

  echo ""
  echo "请输入要同步的技能编号（空格分隔，空表示不同步）:"
  read -r selection

  if [[ -z "$selection" ]]; then
    echo "[cc-remote] 不同步技能包"
    rm -rf "$pack_dir/skills"
    return 0
  fi

  rm -rf "$pack_dir/skills"
  mkdir -p "$pack_dir/skills"

  for idx in $selection; do
    if [[ "$idx" =~ ^[0-9]+$ ]]; then
      local global_idx=$((idx-1))
      if (( global_idx >= 0 && global_idx < ${#global_skills[@]} )); then
        local skill_name="${global_skills[$global_idx]}"
        local skill_src="$(ccr_remote_skills_root)/$skill_name"
        echo "[cc-remote] 添加技能: $skill_name"
        cp -rL "$skill_src" "$pack_dir/skills/$skill_name"
      elif (( global_idx >= ${#global_skills[@]} && global_idx < ${#global_skills[@]} + ${#bundled_skills[@]} )); then
        local bundled_idx=$((global_idx - ${#global_skills[@]}))
        local bundled_entry="${bundled_skills[$bundled_idx]}"
        local bundled_name="${bundled_entry#bundled:}"
        local repo_root
        for candidate in "${HOME}/Code/Andrew-tech/cc-router" "${HOME}/Projects/cc-router" "${HOME}/cc-router"; do
          if [[ -d "$candidate/skills/$bundled_name" ]]; then
            repo_root="$candidate"
            break
          fi
        done
        echo "[cc-remote] 添加自带技能: $bundled_name"
        cp -rL "$repo_root/skills/$bundled_name" "$pack_dir/skills/$bundled_name"
      elif (( global_idx >= ${#global_skills[@]} + ${#bundled_skills[@]} && global_idx < project_offset + ${#project_skills_dirs[@]} )); then
        local project_idx=$((global_idx - project_offset))
        local project_dir="${project_skills_dirs[$project_idx]}"
        echo "[cc-remote] 添加项目技能目录: $project_dir"
        cp -rL "$project_dir"/* "$pack_dir/skills/" 2>/dev/null || true
      else
        echo "WARN: 无效编号: $idx" >&2
      fi
    fi
  done

  echo "[cc-remote] 已选技能包:"
  ls -1 "$pack_dir/skills/" 2>/dev/null || echo "  (无)"
}

ccr_remote_skills_pack() {
  local dest="$1"
  local pack_dir
  pack_dir="$(ccr_remote_pack_dir)"

  rm -rf "$dest"

  # 如果用户没有手动选择，默认打包所有 bundled skills
  if [[ ! -d "$pack_dir/skills" ]] || [[ -z "$(ls -A "$pack_dir/skills" 2>/dev/null)" ]]; then
    ccr_remote_skills_pack_bundled "$pack_dir/skills"
  fi

  if [[ -d "$pack_dir/skills" ]]; then
    mkdir -p "$dest"
    cp -rL "$pack_dir/skills"/* "$dest/" 2>/dev/null || true
    echo "[cc-remote] 已打包技能包: $(ls -1 "$dest" 2>/dev/null | wc -l | tr -d ' ') 个"
  fi
}

ccr_remote_skills_pack_bundled() {
  local dest="$1"
  local repo_root
  for candidate in "${HOME}/Code/Andrew-tech/cc-router" "${HOME}/Projects/cc-router" "${HOME}/cc-router"; do
    if [[ -d "$candidate/skills" ]]; then
      repo_root="$candidate"
      break
    fi
  done

  if [[ -z "${repo_root:-}" ]]; then
    return 0
  fi

  mkdir -p "$dest"
  find "$repo_root/skills" -maxdepth 1 -mindepth 1 -type d | while read -r skill; do
    local name
    name="$(basename "$skill")"
    cp -rL "$skill" "$dest/$name"
  done

  echo "[cc-remote] 已打包内置技能包: $(ls -1 "$dest" 2>/dev/null | wc -l | tr -d ' ') 个"
}

ccr_remote_skills_copy_from_project() {
  local project_dir="$1"
  local dest="$2"
  local skills_dir="$project_dir/.claude/skills"

  if [[ ! -d "$skills_dir" ]]; then
    return 0
  fi

  mkdir -p "$dest"
  cp -rL "$skills_dir"/* "$dest/" 2>/dev/null || true
}
