#!/usr/bin/env bash
# Claude Code statusline - single line, truecolor gradient
input=$(cat)

# jq isn't installed on this machine, so parse the JSON with node instead
fields=$(printf '%s' "$input" | node -e '
let d = "";
process.stdin.on("data", c => d += c);
process.stdin.on("end", () => {
  let j = {};
  try { j = JSON.parse(d); } catch (e) {}
  const repo = j.workspace?.repo?.name ?? "";
  const cwd = j.workspace?.current_dir ?? j.cwd ?? "";
  const used = j.context_window?.used_percentage ?? 0;
  const cost = j.cost?.total_cost_usd ?? "";
  const added = j.cost?.total_lines_added ?? 0;
  const removed = j.cost?.total_lines_removed ?? 0;
  const model = j.model?.display_name ?? "";
  process.stdout.write([repo, cwd, used, cost, added, removed, model].join("\t"));
});
' 2>/dev/null)

IFS=$'\t' read -r repo cwd used cost added removed model <<< "$fields"

if [ -z "$repo" ]; then
  repo=$(basename "$cwd")
fi

branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)

used_int=$(printf '%.0f' "$used" 2>/dev/null)
if [ -z "$used_int" ]; then used_int=0; fi

RESET=$'\033[0m'
DIM=$'\033[38;2;90;90;90m'
sep="${DIM} | ${RESET}"

REPO_COLOR=$'\033[1;38;2;224;175;104m'
BRANCH_COLOR=$'\033[1;38;2;125;207;255m'
COST_COLOR=$'\033[38;2;224;175;104m'
ADD_COLOR=$'\033[38;2;158;206;106m'
REM_COLOR=$'\033[38;2;247;118;142m'
MODEL_COLOR=$'\033[38;2;187;154;247m'

# 20-block truecolor gradient context bar: green -> yellow -> red
bar=$(awk -v used="$used_int" 'BEGIN{
  total=20;
  filled=int(used*total/100+0.5);
  if (filled>total) filled=total;
  s="";
  for (i=1;i<=total;i++){
    if (i<=filled){
      frac=(total==1)?1:(i-1)/(total-1);
      if (frac<=0.5){
        t=frac/0.5;
        r=158+(224-158)*t; g=206+(175-206)*t; b=106+(104-106)*t;
      } else {
        t=(frac-0.5)/0.5;
        r=224+(247-224)*t; g=175+(118-175)*t; b=104+(142-104)*t;
      }
      s=s sprintf("\033[38;2;%d;%d;%dm█", r+0.5, g+0.5, b+0.5);
    } else {
      s=s "\033[38;2;60;60;60m█";
    }
  }
  s=s "\033[0m";
  printf "%s", s;
}')

if [ "$used_int" -lt 20 ]; then
  emoji="🟢"; pct_color=$'\033[38;2;158;206;106m'
elif [ "$used_int" -lt 70 ]; then
  emoji="⚡"; pct_color=$'\033[38;2;224;175;104m'
elif [ "$used_int" -lt 90 ]; then
  emoji="🔥"; pct_color=$'\033[38;2;255;158;100m'
else
  emoji="🚨"; pct_color=$'\033[38;2;247;118;142m'
fi

out=""

if [ -n "$repo" ]; then
  out="${out}${REPO_COLOR}${repo}${RESET}"
fi

if [ -n "$branch" ]; then
  if [ -n "$out" ]; then out="${out}${sep}"; fi
  out="${out}${BRANCH_COLOR}🌿 (${branch})${RESET}"
fi

if [ -n "$out" ]; then out="${out}${sep}"; fi
out="${out}${bar} ${emoji} ${pct_color}${used_int}%${RESET}"

if [ -n "$cost" ]; then
  cost_fmt=$(printf '%.4f' "$cost" 2>/dev/null)
  out="${out}${sep}${COST_COLOR}\$${cost_fmt}${RESET}"
fi

if [ "$added" != "0" ] || [ "$removed" != "0" ]; then
  out="${out}${sep}${ADD_COLOR}+${added}${RESET}${DIM}/${RESET}${REM_COLOR}-${removed}${RESET}"
fi

if [ -n "$model" ]; then
  out="${out}${sep}${MODEL_COLOR}🤖 ${model}${RESET}"
fi

printf "%s" "$out"
